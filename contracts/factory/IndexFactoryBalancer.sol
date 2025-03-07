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
import "./FunctionsOracle.sol";
import "../libraries/Commen.sol" as PrbMath2;

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
/// @custom:oz-upgrades-from IndexFactoryBalancerV3
contract IndexFactoryBalancerV4 is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    uint256 public rebalanceNonce;

    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    mapping(uint256 => mapping(address => uint256)) public rebalanceRequestId;

    mapping(uint256 => uint256) public rebalanceBuyPayedAmountById;
    mapping(uint256 => uint256) public rebalanceSellAssetAmountById;

    mapping(uint256 => uint256) public portfolioValueByNonce;
    mapping(uint256 => mapping(address => uint256)) public tokenValueByNonce;
    mapping(uint256 => mapping(address => uint256)) public tokenShortagePercentByNonce;
    mapping(uint256 => uint256) public totalShortagePercentByNonce;

    mapping(uint256 => ActionInfo) public actionInfoById;

    function initialize(address _factoryStorage, address _functionsOracle) external initializer {
        require(_factoryStorage != address(0), "invalid token address");
        require(_functionsOracle != address(0), "invalid functions oracle address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setIndexFactoryStorage(address _indexFactoryStorage) public onlyOwner returns (bool) {
        factoryStorage = IndexFactoryStorage(_indexFactoryStorage);
        return true;
    }

    function setFunctionsOracle(address _functionsOracle) public onlyOwner returns (bool) {
        functionsOracle = FunctionsOracle(_functionsOracle);
        return true;
    }

    function getAmountAfterFee(uint24 percentageFeeRate, uint256 orderValue) internal pure returns (uint256) {
        return percentageFeeRate != 0
            ? PrbMath2.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate))
            : orderValue;
    }

    function requestBuyOrder(address _token, uint256 _orderAmount, address _receiver) internal returns (uint256) {
        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;

        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestBuyOrderFromCurrentBalance(_token, _orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return id;
    }

    function requestSellOrder(address _token, uint256 _amount, address _receiver) internal returns (uint256, uint256) {
        address wrappedDshare = factoryStorage.wrappedDshareAddress(_token);
        NexVault(factoryStorage.vault()).withdrawFunds(wrappedDshare, address(this), _amount);
        uint256 orderAmount0 = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        //rounding order
        IOrderProcessor issuer = factoryStorage.issuer();
        uint8 decimalReduction = issuer.orderDecimalReduction(_token);

        uint256 orderAmount;
        if (decimalReduction > 0) {
            orderAmount = orderAmount0 - (orderAmount0 % 10 ** (decimalReduction - 1));
        } else {
            orderAmount = orderAmount0;
        }
        uint256 extraAmount = orderAmount0 - orderAmount;

        if (extraAmount > 0) {
            IERC20(_token).approve(wrappedDshare, extraAmount);
            WrappedDShare(wrappedDshare).deposit(extraAmount, address(factoryStorage.vault()));
        }

        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;

        IERC20(_token).safeTransfer(address(factoryStorage.orderManager()), orderAmount);
        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return (id, orderAmount);
    }

    function _sellOverweightedAssets(uint256 _rebalanceNonce, uint256 _portfolioValue) internal {
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 tokenValue = tokenValueByNonce[_rebalanceNonce][tokenAddress];
            address wrappedDshare = factoryStorage.wrappedDshareAddress(tokenAddress);
            uint256 tokenBalance = IERC20(wrappedDshare).balanceOf(address(factoryStorage.vault()));
            uint256 tokenValuePercent = (tokenValue * 100e18) / _portfolioValue;
            if (tokenValuePercent > functionsOracle.tokenOracleMarketShare(tokenAddress)) {
                uint256 amount = tokenBalance
                    - ((tokenBalance * functionsOracle.tokenOracleMarketShare(tokenAddress)) / tokenValuePercent);
                if (tokenValue * amount / tokenBalance > 1e18) {
                    (uint256 requestId, uint256 assetAmount) =
                        requestSellOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
                    actionInfoById[requestId] = ActionInfo(5, _rebalanceNonce);
                    rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                    rebalanceSellAssetAmountById[requestId] = amount;
                }
            } else {
                uint256 shortagePercent = functionsOracle.tokenOracleMarketShare(tokenAddress) - tokenValuePercent;
                if ((_portfolioValue * shortagePercent) / 100e18 > 1e18) {
                    tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress] = shortagePercent;
                    totalShortagePercentByNonce[_rebalanceNonce] += shortagePercent;
                }
            }
        }
    }

    function firstRebalanceAction() public nonReentrant onlyOwner returns (uint256) {
        rebalanceNonce += 1;
        uint256 portfolioValue;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 tokenValue = factoryStorage.getVaultDshareValue(tokenAddress);
            tokenValueByNonce[rebalanceNonce][tokenAddress] = tokenValue;
            portfolioValue += tokenValue;
        }
        portfolioValueByNonce[rebalanceNonce] = portfolioValue;
        _sellOverweightedAssets(rebalanceNonce, portfolioValue);
        return rebalanceNonce;
    }

    function _buyUnderweightedAssets(uint256 _rebalanceNonce, uint256 _totalShortagePercent, uint256 _usdcBalance)
        internal
    {
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 tokenShortagePercent = tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress];
            if (tokenShortagePercent > 0) {
                uint256 paymentAmount = (tokenShortagePercent * _usdcBalance) / _totalShortagePercent;
                (uint256 flatFee, uint24 percentageFeeRate) =
                    issuer.getStandardFees(false, address(factoryStorage.usdc()));

                uint256 amountAfterFee = getAmountAfterFee(percentageFeeRate, paymentAmount) > flatFee
                    ? getAmountAfterFee(percentageFeeRate, paymentAmount) - flatFee
                    : 0;

                if (amountAfterFee > 0) {
                    uint256 esFee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, amountAfterFee);
                    IERC20(factoryStorage.usdc()).approve(address(factoryStorage.orderManager()), paymentAmount);
                    uint256 requestId =
                        requestBuyOrder(tokenAddress, amountAfterFee, address(factoryStorage.orderManager()));
                    actionInfoById[requestId] = ActionInfo(6, _rebalanceNonce);
                    rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                    rebalanceBuyPayedAmountById[requestId] = amountAfterFee;
                }
            }
        }
    }

    function secondRebalanceAction(uint256 _rebalanceNonce) public nonReentrant onlyOwner {
        require(checkFirstRebalanceOrdersStatus(rebalanceNonce), "Rebalance orders are not completed");
        uint256 portfolioValue = portfolioValueByNonce[_rebalanceNonce];
        uint256 totalShortagePercent = totalShortagePercentByNonce[_rebalanceNonce];
        IOrderProcessor issuer = factoryStorage.issuer();
        uint256 usdcBalance;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = factoryStorage.getOrderInstanceById(requestId);
                uint256 assetAmount = order.assetTokenQuantity;
                if (order.sell) {
                    uint256 balance = issuer.getReceivedAmount(requestId);
                    uint256 feeTaken = issuer.getFeesTaken(requestId);
                    usdcBalance += balance - feeTaken;
                }
            }
        }
        _buyUnderweightedAssets(_rebalanceNonce, totalShortagePercent, usdcBalance);
    }

    function estimateAmountAfterFee(uint256 _amount) public view returns (uint256) {
        IOrderProcessor issuer = factoryStorage.issuer();
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(factoryStorage.usdc()));
        uint256 amountAfterFee = getAmountAfterFee(percentageFeeRate, _amount) - flatFee;
        return amountAfterFee;
    }

    function completeRebalanceActions(uint256 _rebalanceNonce) public nonReentrant onlyOwner {
        require(checkSecondRebalanceOrdersStatus(_rebalanceNonce), "Rebalance orders are not completed");
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = factoryStorage.getOrderInstanceById(requestId);
                if (!order.sell) {
                    uint256 tokenBalance = issuer.getReceivedAmount(requestId);
                    if (tokenBalance > 0) {
                        OrderManager(factoryStorage.orderManager()).withdrawFunds(
                            tokenAddress, address(this), tokenBalance
                        );
                        IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), tokenBalance);
                        WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(
                            tokenBalance, address(factoryStorage.vault())
                        );
                    }
                }
            }
        }
        functionsOracle.updateCurrentList();
    }

    function checkFirstRebalanceOrdersStatus(uint256 _rebalanceNonce) public view returns (bool) {
        uint256 completedOrdersCount;
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 assetAmount = rebalanceSellAssetAmountById[requestId];
            if (
                requestId > 0 && assetAmount > 0
                    && uint8(issuer.getOrderStatus(requestId)) != uint8(IOrderProcessor.OrderStatus.FULFILLED)
            ) {
                return false;
            }
        }
        return true;
    }

    function checkSecondRebalanceOrdersStatus(uint256 _rebalanceNonce) public view returns (bool) {
        uint256 completedOrdersCount;
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 payedAmount = rebalanceBuyPayedAmountById[requestId];
            if (
                requestId > 0 && payedAmount > 0
                    && uint8(issuer.getOrderStatus(requestId)) != uint8(IOrderProcessor.OrderStatus.FULFILLED)
            ) {
                return false;
            }
        }
        return true;
    }

    function checkMultical(uint256 _reqeustId) public view returns (bool) {
        ActionInfo memory actionInfo = actionInfoById[_reqeustId];
        if (actionInfo.actionType == 5) {
            return checkFirstRebalanceOrdersStatus(actionInfo.nonce);
        } else if (actionInfo.actionType == 6) {
            return checkSecondRebalanceOrdersStatus(actionInfo.nonce);
        }
        return false;
    }

    function multical(uint256 _requestId) public {
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
