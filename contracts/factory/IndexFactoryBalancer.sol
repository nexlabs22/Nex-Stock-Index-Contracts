// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
// import "../token/RequestNFT.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// import "../chainlink/ChainlinkClient.sol";
import "../dinary/orders/IOrderProcessor.sol";
import {FeeLib} from "../dinary/common/FeeLib.sol";
import "../coa/ContractOwnedAccount.sol";
import "../vault/NexVault.sol";
import "../dinary/WrappedDShare.sol";
// import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
// import "../libraries/Commen.sol" as PrbMath;
import "./IndexFactoryStorage.sol";
import "./OrderManager.sol";
import "../libraries/Commen.sol" as PrbMath2;

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryBalancer is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    struct ActionInfo {
        uint actionType;
        uint nonce;
    }

    uint public rebalanceNonce;

    IndexFactoryStorage public factoryStorage;


    mapping(uint => mapping(address => uint)) public rebalanceRequestId;

    mapping(uint => uint) public rebalanceBuyPayedAmountById;
    mapping(uint => uint) public rebalanceSellAssetAmountById;

    mapping(uint => uint) public portfolioValueByNonce;
    mapping(uint => mapping(address => uint)) public tokenValueByNonce;
    mapping(uint => mapping(address => uint))
        public tokenShortagePercentByNonce;
    mapping(uint => uint) public totalShortagePercentByNonce;

    mapping(uint => ActionInfo) public actionInfoById;

    function initialize(address _factoryStorage) external initializer {
        require(_factoryStorage != address(0), "invalid token address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setIndexFactoryStorage(
        address _indexFactoryStorage
    ) public onlyOwner returns (bool) {
        factoryStorage = IndexFactoryStorage(_indexFactoryStorage);
        return true;
    }

    function getAmountAfterFee(
        uint24 percentageFeeRate,
        uint256 orderValue
    ) internal pure returns (uint256) {
        return
            percentageFeeRate != 0
                ? PrbMath2.mulDiv(
                    orderValue,
                    1_000_000,
                    (1_000_000 + percentageFeeRate)
                )
                : 0;
    }

   

    function requestBuyOrder(
        address _token,
        uint256 _orderAmount,
        address _receiver
    ) internal returns (uint) {
        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(
            false
        );
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;

        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestBuyOrderFromCurrentBalance(
            _token,
            _orderAmount,
            _receiver
        );
        factoryStorage.setOrderInstanceById(id, order);
        return id;
    }

    function requestSellOrder(
        address _token,
        uint256 _amount,
        address _receiver
    ) internal returns (uint, uint) {
        address wrappedDshare = factoryStorage.wrappedDshareAddress(_token);
        NexVault(factoryStorage.vault()).withdrawFunds(
            wrappedDshare,
            address(this),
            _amount
        );
        uint orderAmount0 = WrappedDShare(wrappedDshare).redeem(
            _amount,
            address(this),
            address(this)
        );

        //rounding order
        IOrderProcessor issuer = factoryStorage.issuer();
        uint8 decimalReduction = issuer.orderDecimalReduction(_token);
        uint256 orderAmount = orderAmount0 -
            (orderAmount0 % 10 ** (decimalReduction - 1));
        uint extraAmount = orderAmount0 - orderAmount;

        if (extraAmount > 0) {
            IERC20(_token).approve(wrappedDshare, extraAmount);
            WrappedDShare(wrappedDshare).deposit(
                extraAmount,
                address(factoryStorage.vault())
            );
        }

        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(
            true
        );
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;

        IERC20(_token).safeTransfer(
                address(factoryStorage.orderManager()),
                orderAmount
            );
        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(
            _token,
            orderAmount,
            _receiver
        );
        factoryStorage.setOrderInstanceById(id, order);
        return (id, orderAmount);
    }

    function _sellOverweightedAssets(
        uint256 _rebalanceNonce,
        uint256 _portfolioValue
    ) internal {
        for (uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenValue = tokenValueByNonce[_rebalanceNonce][tokenAddress];
            uint tokenBalance = factoryStorage.getVaultDshareBalance(
                tokenAddress
            );
            uint tokenValuePercent = (tokenValue * 100e18) / _portfolioValue;
            if (
                tokenValuePercent >
                factoryStorage.tokenOracleMarketShare(tokenAddress)
            ) {
                uint amount = tokenBalance -
                    ((tokenBalance *
                        factoryStorage.tokenOracleMarketShare(tokenAddress)) /
                        tokenValuePercent);
                (uint requestId, uint assetAmount) = requestSellOrder(
                    tokenAddress,
                    amount,
                    address(factoryStorage.orderManager())
                );
                actionInfoById[requestId] = ActionInfo(5, _rebalanceNonce);
                rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                rebalanceSellAssetAmountById[requestId] = amount;
            } else {
                uint shortagePercent = factoryStorage.tokenOracleMarketShare(
                    tokenAddress
                ) - tokenValuePercent;
                tokenShortagePercentByNonce[_rebalanceNonce][
                    tokenAddress
                ] = shortagePercent;
                totalShortagePercentByNonce[_rebalanceNonce] += shortagePercent;
            }
        }
    }

    function firstRebalanceAction()
        public
        nonReentrant
        onlyOwner
        returns (uint)
    {
        rebalanceNonce += 1;
        uint portfolioValue;
        for (uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenValue = factoryStorage.getVaultDshareValue(tokenAddress);
            tokenValueByNonce[rebalanceNonce][tokenAddress] = tokenValue;
            portfolioValue += tokenValue;
        }
        portfolioValueByNonce[rebalanceNonce] = portfolioValue;
        _sellOverweightedAssets(rebalanceNonce, portfolioValue);
        return rebalanceNonce;
    }

    function _buyUnderweightedAssets(
        uint _rebalanceNonce,
        uint _totalShortagePercent,
        uint _usdcBalance
    ) internal {
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenShortagePercent = tokenShortagePercentByNonce[
                _rebalanceNonce
            ][tokenAddress];
            if (tokenShortagePercent > 0) {
                uint paymentAmount = (tokenShortagePercent * _usdcBalance) /
                    _totalShortagePercent;
                (uint256 flatFee, uint24 percentageFeeRate) = issuer
                    .getStandardFees(false, address(factoryStorage.usdc()));
                uint amountAfterFee = getAmountAfterFee(
                    percentageFeeRate,
                    paymentAmount
                ) - flatFee;
                uint256 esFee = flatFee +
                    FeeLib.applyPercentageFee(
                        percentageFeeRate,
                        amountAfterFee
                    );
                IERC20(factoryStorage.usdc()).approve(
                    address(factoryStorage.orderManager()),
                    paymentAmount
                );
                uint requestId = requestBuyOrder(
                    tokenAddress,
                    amountAfterFee,
                    address(factoryStorage.orderManager())
                );
                actionInfoById[requestId] = ActionInfo(6, _rebalanceNonce);
                rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                rebalanceBuyPayedAmountById[requestId] = amountAfterFee;
            }
        }
    }

    function secondRebalanceAction(
        uint _rebalanceNonce
    ) public nonReentrant onlyOwner {
        require(
            checkFirstRebalanceOrdersStatus(rebalanceNonce),
            "Rebalance orders are not completed"
        );
        uint portfolioValue = portfolioValueByNonce[_rebalanceNonce];
        uint totalShortagePercent = totalShortagePercentByNonce[
            _rebalanceNonce
        ];
        IOrderProcessor issuer = factoryStorage.issuer();
        uint usdcBalance;
        for (uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = factoryStorage
                    .getOrderInstanceById(requestId);
                uint assetAmount = order.assetTokenQuantity;
                if (order.sell) {
                    uint256 balance = issuer.getReceivedAmount(requestId);
                    uint256 feeTaken = issuer.getFeesTaken(requestId);
                    usdcBalance += balance - feeTaken;
                }
            }
        }
        _buyUnderweightedAssets(
            _rebalanceNonce,
            totalShortagePercent,
            usdcBalance
        );
    }

    function estimateAmountAfterFee(
        uint _amount
    ) public view returns (uint256) {
        IOrderProcessor issuer = factoryStorage.issuer();
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(
            false,
            address(factoryStorage.usdc())
        );
        uint amountAfterFee = getAmountAfterFee(percentageFeeRate, _amount) -
            flatFee;
        return amountAfterFee;
    }

    function completeRebalanceActions(
        uint _rebalanceNonce
    ) public nonReentrant onlyOwner {
        require(
            checkSecondRebalanceOrdersStatus(_rebalanceNonce),
            "Rebalance orders are not completed"
        );
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = factoryStorage
                    .getOrderInstanceById(requestId);
                if (!order.sell) {
                    uint tokenBalance = issuer.getReceivedAmount(requestId);
                    if (tokenBalance > 0) {
                        OrderManager(factoryStorage.orderManager())
                            .withdrawFunds(
                                tokenAddress,
                                address(this),
                                tokenBalance
                            );
                        IERC20(tokenAddress).approve(
                            factoryStorage.wrappedDshareAddress(tokenAddress),
                            tokenBalance
                        );
                        WrappedDShare(
                            factoryStorage.wrappedDshareAddress(tokenAddress)
                        ).deposit(
                                tokenBalance,
                                address(factoryStorage.vault())
                            );
                    }
                }
            }
        }
        factoryStorage.updateCurrentList();
    }

    function checkFirstRebalanceOrdersStatus(
        uint256 _rebalanceNonce
    ) public view returns (bool) {
        uint completedOrdersCount;
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint assetAmount = rebalanceSellAssetAmountById[requestId];
            if (
                requestId > 0 &&
                assetAmount > 0 &&
                uint8(issuer.getOrderStatus(requestId)) !=
                uint8(IOrderProcessor.OrderStatus.FULFILLED)
            ) {
                return false;
            }
        }
        return true;
    }

    function checkSecondRebalanceOrdersStatus(
        uint256 _rebalanceNonce
    ) public view returns (bool) {
        uint completedOrdersCount;
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint payedAmount = rebalanceBuyPayedAmountById[requestId];
            if (
                requestId > 0 &&
                payedAmount > 0 &&
                uint8(issuer.getOrderStatus(requestId)) !=
                uint8(IOrderProcessor.OrderStatus.FULFILLED)
            ) {
                return false;
            }
        }
        return true;
    }

    function checkMultical(uint _reqeustId) public view returns (bool) {
        ActionInfo memory actionInfo = actionInfoById[_reqeustId];
        if (actionInfo.actionType == 5) {
            return checkFirstRebalanceOrdersStatus(actionInfo.nonce);
        } else if (actionInfo.actionType == 6) {
            return checkSecondRebalanceOrdersStatus(actionInfo.nonce);
        }
        return false;
    }

    function multical(uint _requestId) public {
        require(_requestId > 0, "Invalid request id");
        ActionInfo memory actionInfo = actionInfoById[_requestId];
        if (actionInfo.actionType == 5) {
            secondRebalanceAction(actionInfo.nonce);
        } else if (actionInfo.actionType == 6) {
            completeRebalanceActions(actionInfo.nonce);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
