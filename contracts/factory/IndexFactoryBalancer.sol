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
import "../vault/NexVault.sol";
import "../dinary/WrappedDShare.sol";
// import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
// import "../libraries/Commen.sol" as PrbMath;
import "./IndexFactoryStorage.sol";
import "./IndexFactory.sol";
import "./OrderManager.sol";
import "./FunctionsOracle.sol";
import "../libraries/Commen.sol" as PrbMath2;

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryBalancer is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
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
    mapping(uint256 => bool) public rebalanceIsSellById;
    mapping(uint256 => address) public rebalanceTokenById;
    mapping(uint256 => bool) public rebalanceIntentSettledById;
    mapping(uint256 => uint256) public rebalanceUsdcReceivedById;
    mapping(uint256 => uint256) public rebalanceTokenReceivedById;
    uint256 public nextRebalanceIntentId;

    event FirstRebalanceAction(uint256 nonce, uint time);
    event SecondRebalanceAction(uint256 nonce, uint time);
    event CompleteRebalanceActions(uint256 nonce, uint time);

    uint256 public minimumOrderAmount;

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender),
            "Only owner or operator can call this function"
        );
        _;
    }

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

    function setMinimumOrderAmount(uint256 _minimumOrderAmount) public onlyOwnerOrOperator returns (bool) {
        minimumOrderAmount = _minimumOrderAmount;
        return true;
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
        _receiver; // placeholder: receiver is relayer-side concern in V2 async flow
        nextRebalanceIntentId += 1;
        uint256 id = nextRebalanceIntentId;
        rebalanceIsSellById[id] = false;
        rebalanceTokenById[id] = _token;
        return id;
    }

    function requestSellOrder(address _token, uint256 _amount, address _receiver) internal returns (uint256, uint256) {
        address wrappedDshare = factoryStorage.wrappedDshareAddress(_token);
        NexVault(factoryStorage.vault()).withdrawFunds(wrappedDshare, address(this), _amount);
        uint256 orderAmount0 = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        // V2 async placeholder: keep full amount, relayer applies venue-specific rounding.
        uint256 orderAmount = orderAmount0;
        uint256 extraAmount = orderAmount0 - orderAmount;

        if (extraAmount > 0) {
            IERC20(_token).approve(wrappedDshare, extraAmount);
            WrappedDShare(wrappedDshare).deposit(extraAmount, address(factoryStorage.vault()));
        }

        _receiver; // placeholder: receiver is relayer-side concern in V2 async flow
        IERC20(_token).safeTransfer(address(factoryStorage.orderManager()), orderAmount);
        nextRebalanceIntentId += 1;
        uint256 id = nextRebalanceIntentId;
        rebalanceIsSellById[id] = true;
        rebalanceTokenById[id] = _token;
        factoryStorage.increaseTokenPendingRebalanceAmount(_token, rebalanceNonce, orderAmount);
        return (id, orderAmount);
    }

    function _emitSellIntent(address _tokenAddress, uint256 _amount, uint256 _rebalanceNonce) internal {
        factoryStorage.emitOrderIntentCreated(
            msg.sender,
            _tokenAddress,
            _amount,
            IndexFactoryStorage.OrderType.SELL,
            _rebalanceNonce
        );
    }

    function _emitBuyIntent(address _tokenAddress, uint256 _amount, uint256 _rebalanceNonce) internal {
        factoryStorage.emitOrderIntentCreated(
            msg.sender,
            _tokenAddress,
            _amount,
            IndexFactoryStorage.OrderType.BUY,
            _rebalanceNonce
        );
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
                if (tokenValue * amount / tokenBalance > minimumOrderAmount) {
                    (uint256 requestId, uint256 assetAmount) =
                        requestSellOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
                    actionInfoById[requestId] = ActionInfo(5, _rebalanceNonce);
                    rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                    rebalanceSellAssetAmountById[requestId] = amount;
                    _emitSellIntent(tokenAddress, assetAmount, _rebalanceNonce);
                }
            } else {
                uint256 shortagePercent = functionsOracle.tokenOracleMarketShare(tokenAddress) - tokenValuePercent;
                if ((_portfolioValue * shortagePercent) / 100e18 > minimumOrderAmount) {
                    tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress] = shortagePercent;
                    totalShortagePercentByNonce[_rebalanceNonce] += shortagePercent;
                }
            }
        }
    }

    function firstRebalanceAction() public nonReentrant onlyOwnerOrOperator returns (uint256) {
        pauseIndexFactory();
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
        emit FirstRebalanceAction(rebalanceNonce, block.timestamp);
        return rebalanceNonce;
    }

    function _buyUnderweightedAssets(uint256 _rebalanceNonce, uint256 _totalShortagePercent, uint256 _usdcBalance)
        internal
    {
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 tokenShortagePercent = tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress];
            if (tokenShortagePercent > 0) {
                uint256 paymentAmount = (tokenShortagePercent * _usdcBalance) / _totalShortagePercent;
                // TODO: wire Dinari V2 fee schedule from relayer snapshots.
                uint256 amountAfterFee = paymentAmount;

                if (amountAfterFee > 0) {
                    IERC20(factoryStorage.usdc()).approve(address(factoryStorage.orderManager()), paymentAmount);
                    uint256 requestId =
                        requestBuyOrder(tokenAddress, amountAfterFee, address(factoryStorage.orderManager()));
                    actionInfoById[requestId] = ActionInfo(6, _rebalanceNonce);
                    rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                    rebalanceBuyPayedAmountById[requestId] = amountAfterFee;
                    _emitBuyIntent(tokenAddress, amountAfterFee, _rebalanceNonce);
                }
            }
        }
    }

    function secondRebalanceAction(uint256 _rebalanceNonce) public nonReentrant onlyOwnerOrOperator {
        require(checkFirstRebalanceOrdersStatus(_rebalanceNonce), "Rebalance orders are not completed");
        uint256 portfolioValue = portfolioValueByNonce[_rebalanceNonce];
        uint256 totalShortagePercent = totalShortagePercentByNonce[_rebalanceNonce];
        uint256 usdcBalance;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 assetAmount = rebalanceSellAssetAmountById[requestId];
            if (requestId > 0 && assetAmount > 0) {
                // Relayer pushes settled USDC for sell intents via setRebalanceIntentSettlement.
                usdcBalance += rebalanceUsdcReceivedById[requestId];
            }
        }
        _buyUnderweightedAssets(_rebalanceNonce, totalShortagePercent, usdcBalance);
        emit SecondRebalanceAction(_rebalanceNonce, block.timestamp);
    }

    function estimateAmountAfterFee(uint256 _amount) public pure returns (uint256) {
        // TODO: replace with relayer-provided Dinari V2 fee estimation.
        return _amount;
    }

    function updatePendingTokenSellAmounts(uint _rebalanceNonce) internal {
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 assetAmount = rebalanceSellAssetAmountById[requestId];
            if (requestId > 0 && assetAmount > 0 && rebalanceIsSellById[requestId]) {
                factoryStorage.decreaseTokenPendingRebalanceAmount(tokenAddress, _rebalanceNonce, assetAmount);
            }
        }
    }

    function completeRebalanceActions(uint256 _rebalanceNonce) public nonReentrant onlyOwnerOrOperator {
        require(checkSecondRebalanceOrdersStatus(_rebalanceNonce), "Rebalance orders are not completed");
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 payedAmount = rebalanceBuyPayedAmountById[requestId];
            if (requestId > 0 && payedAmount > 0 && !rebalanceIsSellById[requestId]) {
                uint256 tokenBalance = rebalanceTokenReceivedById[requestId];
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
        updatePendingTokenSellAmounts(_rebalanceNonce);
        functionsOracle.updateCurrentList();
        unpauseIndexFactory();
        emit CompleteRebalanceActions(_rebalanceNonce, block.timestamp);
    }

    function checkFirstRebalanceOrdersStatus(uint256 _rebalanceNonce) public view returns (bool) {
        require(_rebalanceNonce <= rebalanceNonce, "Wrong rebalance nonce!");
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 assetAmount = rebalanceSellAssetAmountById[requestId];
            if (requestId > 0 && assetAmount > 0 && !rebalanceIntentSettledById[requestId]) {
                return false;
            }
        }
        return true;
    }

    function checkSecondRebalanceOrdersStatus(uint256 _rebalanceNonce) public view returns (bool) {
        require(_rebalanceNonce <= rebalanceNonce, "Wrong rebalance nonce!");
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 payedAmount = rebalanceBuyPayedAmountById[requestId];
            if (requestId > 0 && payedAmount > 0 && !rebalanceIntentSettledById[requestId]) {
                return false;
            }
        }
        return true;
    }

    function setRebalanceIntentSettlement(
        uint256 _requestId,
        bool _isSettled,
        uint256 _usdcReceived,
        uint256 _tokenReceived
    ) external onlyOwnerOrOperator {
        require(_requestId > 0 && _requestId <= nextRebalanceIntentId, "Invalid request id");
        rebalanceIntentSettledById[_requestId] = _isSettled;
        rebalanceUsdcReceivedById[_requestId] = _usdcReceived;
        rebalanceTokenReceivedById[_requestId] = _tokenReceived;
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

    // pause index factory when rebalance happens
    function pauseIndexFactory() internal {
        address indexFactoryAddress = factoryStorage.factoryAddress();
        IndexFactory indexFactory = IndexFactory(payable(indexFactoryAddress));
        if(!indexFactory.paused()){
        indexFactory.pause();
        }
    }

    // unpause index factory when rebalance is done
    function unpauseIndexFactory() internal {
        address indexFactoryAddress = factoryStorage.factoryAddress();
        IndexFactory indexFactory = IndexFactory(payable(indexFactoryAddress));
        if(indexFactory.paused()){
        indexFactory.unpause();
        }
    }
}
