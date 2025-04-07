// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../dinary/orders/IOrderProcessor.sol";
import "../dinary/WrappedDShare.sol";
import "../vault/NexVault.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./OrderManager.sol";
import "./FunctionsOracle.sol";
import "../libraries/Commen.sol" as PrbMath;

/// @title Index Token Factory Storage
/// @notice Stores data and provides functions for managing index token issuance and redemption
/// @custom:oz-upgrades-from IndexFactoryStorageV2
contract IndexFactoryStorage is Initializable, OwnableUpgradeable {
    using FunctionsRequest for FunctionsRequest.Request;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    // Addresses of factory contracts
    address public factoryAddress;
    address public factoryBalancerAddress;
    address public factoryProcessorAddress;

    uint256 totalDshareAddresses;

    // Mappings for wrapped DShare addresses
    mapping(address => address) public wrappedDshareAddress;

    // Mappings for price feeds by token address
    mapping(address => address) public priceFeedByTokenAddress;

    // Contract instances
    IndexToken public token;
    NexVault public vault;
    IOrderProcessor public issuer;
    address public usdc;
    uint8 public usdcDecimals;
    OrderManager public orderManager;
    bool public isMainnet;
    FunctionsOracle public functionsOracle;

    // New variables
    uint8 public feeRate; // 10/10000 = 0.1%
    uint256 public latestFeeUpdate;
    uint256 public issuanceNonce;
    uint256 public redemptionNonce;

    uint8 public latestPriceDecimals;
    address public feeReceiver;

    // Mappings for issuance and redemption data
    mapping(uint256 => bool) public issuanceIsCompleted;
    mapping(uint256 => bool) public redemptionIsCompleted;
    mapping(uint256 => uint256) public burnedTokenAmountByNonce;
    mapping(uint256 => mapping(address => uint256)) public cancelIssuanceRequestId;
    mapping(uint256 => mapping(address => uint256)) public cancelRedemptionRequestId;
    mapping(uint256 => mapping(address => uint256)) public issuanceRequestId;
    mapping(uint256 => mapping(address => uint256)) public redemptionRequestId;
    mapping(uint256 => uint256) public buyRequestPayedAmountById;
    mapping(uint256 => uint256) public sellRequestAssetAmountById;
    mapping(uint256 => mapping(address => uint256)) public issuanceTokenPrimaryBalance;
    mapping(uint256 => mapping(address => uint256)) public redemptionTokenPrimaryBalance;
    mapping(uint256 => uint256) public issuanceIndexTokenPrimaryTotalSupply;
    mapping(uint256 => uint256) public redemptionIndexTokenPrimaryTotalSupply;
    mapping(uint256 => address) public issuanceRequesterByNonce;
    mapping(uint256 => address) public redemptionRequesterByNonce;
    mapping(uint256 => bool) public cancelIssuanceComplted;
    mapping(uint256 => bool) public cancelRedemptionComplted;
    mapping(uint256 => IOrderProcessor.Order) public orderInstanceById;
    mapping(uint256 => uint256) public issuanceInputAmount;
    mapping(uint256 => uint256) public redemptionInputAmount;
    mapping(uint256 => ActionInfo) public actionInfoById;
    mapping(uint256 => mapping(address => uint256)) public cancelIssuanceUnfilledAmount;
    mapping(uint256 => mapping(address => uint256)) public cancelRedemptionUnfilledAmount;

    mapping(address => uint256) public tokenPendingRebalanceAmount;
    mapping(address => mapping(uint256 => uint256)) public tokenPendingRebalanceAmountByNonce;

    /// @notice Initializes the contract with the given parameters
    /// @param _issuer The address of the issuer
    /// @param _token The address of the token
    /// @param _vault The address of the vault
    /// @param _usdc The address of the USDC token
    /// @param _usdcDecimals The decimals of the USDC token
    //  @param _functionsOracle the address of functions oracle contract
    /// @param _isMainnet Boolean indicating if the contract is on mainnet
    function initialize(
        address _issuer,
        address _token,
        address _vault,
        address _usdc,
        uint8 _usdcDecimals,
        address _functionsOracle,
        bool _isMainnet
    ) external initializer {
        require(_issuer != address(0), "invalid issuer address");
        require(_token != address(0), "invalid token address");
        require(_vault != address(0), "invalid vault address");
        require(_usdc != address(0), "invalid usdc address");
        require(_functionsOracle != address(0), "invalid functions oracle address");
        require(_usdcDecimals > 0, "invalid decimals");
        issuer = IOrderProcessor(_issuer);
        token = IndexToken(_token);
        vault = NexVault(_vault);
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        functionsOracle = FunctionsOracle(_functionsOracle);
        __Ownable_init(msg.sender);
        isMainnet = _isMainnet;
        feeRate = 10;
        feeReceiver = msg.sender;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Modifier to restrict access to factory contracts
    modifier onlyFactory() {
        require(
            msg.sender == factoryAddress || msg.sender == factoryProcessorAddress
                || msg.sender == factoryBalancerAddress,
            "Caller is not a factory contract"
        );
        _;
    }

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner() || functionsOracle.isOperator(msg.sender), "Caller is not the owner or operator");
        _;
    }

    /// @notice Sets the functions oracle address
    /// @param _functionsOracle The address of the functions oracle
    function setFunctionsOracle(address _functionsOracle) public onlyOwner {
        require(_functionsOracle != address(0), "invalid functions oracle address");
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    /// @notice Sets the fee rate for transactions
    /// @param _newFee The new fee rate to set
    function setFeeRate(uint8 _newFee) public onlyOwner {
        uint256 distance = block.timestamp - latestFeeUpdate;
        require(distance / 60 / 60 >= 12, "You should wait at least 12 hours after the latest update");
        require(_newFee <= 10000 && _newFee >= 1, "The newFee should be between 1 and 100 (0.01% - 1%)");
        feeRate = _newFee;
        latestFeeUpdate = block.timestamp;
    }

    /// @notice Sets the fee receiver address
    /// @param _feeReceiver The address to receive fees
    function setFeeReceiver(address _feeReceiver) public onlyOwner {
        require(_feeReceiver != address(0), "invalid fee receiver address");
        feeReceiver = _feeReceiver;
    }

    /// @notice Sets the mainnet status
    /// @param _isMainnet Boolean indicating if the contract is on mainnet
    function setIsMainnet(bool _isMainnet) public onlyOwner {
        isMainnet = _isMainnet;
    }

    /// @notice Sets the USDC address and decimals
    /// @param _usdc The address of the USDC token
    /// @param _usdcDecimals The decimals of the USDC token
    /// @return bool indicating success
    function setUsdcAddress(address _usdc, uint8 _usdcDecimals) public onlyOwner returns (bool) {
        require(_usdc != address(0), "invalid token address");
        require(_usdcDecimals > 0, "invalid decimals");
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        return true;
    }

    /// @notice Sets the latest price decimals
    /// @param _decimals The decimals of the latest price
    function setLatestPriceDecimals(uint8 _decimals) public onlyOwner {
        require(_decimals > 0, "invalid decimals");
        latestPriceDecimals = _decimals;
    }

    /// @notice Sets the token address
    /// @param _token The address of the token
    /// @return bool indicating success
    function setTokenAddress(address _token) public onlyOwner returns (bool) {
        require(_token != address(0), "invalid token address");
        token = IndexToken(_token);
        return true;
    }

    /// @notice Sets the order manager address
    /// @param _orderManager The address of the order manager
    /// @return bool indicating success
    function setOrderManager(address _orderManager) external onlyOwner returns (bool) {
        require(_orderManager != address(0), "invalid order manager address");
        orderManager = OrderManager(_orderManager);
        return true;
    }

    /// @notice Allows the owner of the contract to set the issuer
    /// @param _issuer address
    /// @return bool
    function setIssuer(address _issuer) external onlyOwner returns (bool) {
        require(_issuer != address(0), "invalid issuer address");
        issuer = IOrderProcessor(_issuer);

        return true;
    }

    function setWrappedDshareAndPriceFeedAddresses(
        address[] memory _dShares,
        address[] memory _wrappedDShares,
        address[] memory _priceFeedAddresses
    ) public onlyOwner {
        require(_dShares.length == _wrappedDShares.length, "Array length mismatch");
        require(_dShares.length == _priceFeedAddresses.length, "Array length mismatch");
        for (uint256 i = 0; i < _dShares.length; i++) {
            wrappedDshareAddress[_dShares[i]] = _wrappedDShares[i];
            priceFeedByTokenAddress[_dShares[i]] = _priceFeedAddresses[i];
        }
    }

    function setFactory(address _factoryAddress) public onlyOwner {
        require(_factoryAddress != address(0), "invalid factory address");
        factoryAddress = _factoryAddress;
    }

    function setFactoryBalancer(address _factoryBalancerAddress) public onlyOwner {
        require(_factoryBalancerAddress != address(0), "invalid factory balancer address");
        factoryBalancerAddress = _factoryBalancerAddress;
    }

    function setFactoryProcessor(address _factoryProcessorAddress) public onlyOwner {
        require(_factoryProcessorAddress != address(0), "invalid factory processor address");
        factoryProcessorAddress = _factoryProcessorAddress;
    }

    function increaseTokenPendingRebalanceAmount(address _token, uint256 _nonce, uint256 _amount)
        external
        onlyFactory
    {
        require(_token != address(0), "invalid token address");
        require(_amount > 0, "Invalid amount");
        tokenPendingRebalanceAmount[_token] += _amount;
        tokenPendingRebalanceAmountByNonce[_token][_nonce] += _amount;
    }

    function decreaseTokenPendingRebalanceAmount(address _token, uint256 _nonce, uint256 _amount)
        external
        onlyFactory
    {
        require(_token != address(0), "invalid token address");
        require(_amount > 0, "Invalid amount");
        require(tokenPendingRebalanceAmount[_token] >= _amount, "Insufficient pending rebalance amount");
        tokenPendingRebalanceAmount[_token] -= _amount;
        tokenPendingRebalanceAmountByNonce[_token][_nonce] -= _amount;
    }

    function resetTokenPendingRebalanceAmount(address _token, uint256 _nonce) public onlyOwnerOrOperator {
        require(_token != address(0), "invalid token address");
        tokenPendingRebalanceAmount[_token] = 0;
        tokenPendingRebalanceAmountByNonce[_token][_nonce] = 0;
    }

    function resetAllTokenPendingRebalanceAmount(uint256 _nonce) public onlyOwnerOrOperator {
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            resetTokenPendingRebalanceAmount(tokenAddress, _nonce);
        }
    }

    function increaseIssuanceNonce() external onlyFactory {
        issuanceNonce += 1;
    }

    function increaseRedemptionNonce() external onlyFactory {
        redemptionNonce += 1;
    }

    function setIssuanceIsCompleted(uint256 _issuanceNonce, bool _isCompleted) external onlyFactory {
        issuanceIsCompleted[_issuanceNonce] = _isCompleted;
    }

    function setRedemptionIsCompleted(uint256 _redemptionNonce, bool _isCompleted) external onlyFactory {
        redemptionIsCompleted[_redemptionNonce] = _isCompleted;
    }

    function setBurnedTokenAmountByNonce(uint256 _redemptionNonce, uint256 _burnedAmount) external onlyFactory {
        require(_burnedAmount > 0, "Invalid burn amount");
        burnedTokenAmountByNonce[_redemptionNonce] = _burnedAmount;
    }

    function setIssuanceRequestId(uint256 _issuanceNonce, address _token, uint256 _requestId) external onlyFactory {
        require(_requestId > 0, "Invalid issuance Request Id");
        require(_token != address(0), "Invalid token address");
        issuanceRequestId[_issuanceNonce][_token] = _requestId;
    }

    function setRedemptionRequestId(uint256 _redemptionNonce, address _token, uint256 _requestId)
        external
        onlyFactory
    {
        require(_requestId > 0, "Invalid redemption request id");
        require(_token != address(0), "Invalid token address");
        redemptionRequestId[_redemptionNonce][_token] = _requestId;
    }

    function setIssuanceRequesterByNonce(uint256 _issuanceNonce, address _requester) external onlyFactory {
        require(_requester != address(0), "Invalid issuance requester address");
        issuanceRequesterByNonce[_issuanceNonce] = _requester;
    }

    function setRedemptionRequesterByNonce(uint256 _redemptionNonce, address _requester) external onlyFactory {
        require(_requester != address(0), "Invalid redemption requester address");
        redemptionRequesterByNonce[_redemptionNonce] = _requester;
    }

    function setCancelIssuanceRequestId(uint256 _issuanceNonce, address _token, uint256 _requestId)
        external
        onlyFactory
    {
        require(_requestId > 0, "Invalid issuance request id");
        require(_token != address(0), "Invalid token address");
        cancelIssuanceRequestId[_issuanceNonce][_token] = _requestId;
    }

    function setCancelRedemptionRequestId(uint256 _redemptionNonce, address _token, uint256 _requestId)
        external
        onlyFactory
    {
        require(_requestId > 0, "Invalid redemption request id");
        require(_token != address(0), "Invalid token address");
        cancelRedemptionRequestId[_redemptionNonce][_token] = _requestId;
    }

    function setBuyRequestPayedAmountById(uint256 _requestId, uint256 _amount) external onlyFactory {
        require(_amount > 0, "Invalid buy request amount");
        require(_requestId > 0, "Invalid Request Id");
        buyRequestPayedAmountById[_requestId] = _amount;
    }

    function setSellRequestAssetAmountById(uint256 _requestId, uint256 _amount) external onlyFactory {
        require(_amount > 0, "Invalid sell request amount");
        sellRequestAssetAmountById[_requestId] = _amount;
    }

    function setIssuanceTokenPrimaryBalance(uint256 _issuanceNonce, address _token, uint256 _amount)
        external
        onlyFactory
    {
        require(_token != address(0), "Invalid issuance primary token address");
        issuanceTokenPrimaryBalance[_issuanceNonce][_token] = _amount;
    }

    function setIssuanceIndexTokenPrimaryTotalSupply(uint256 _issuanceNonce, uint256 _amount) external onlyFactory {
        issuanceIndexTokenPrimaryTotalSupply[_issuanceNonce] = _amount;
    }

    function setIssuanceInputAmount(uint256 _issuanceNonce, uint256 _amount) external onlyFactory {
        require(_amount > 0, "Invalid issuance input amount");
        issuanceInputAmount[_issuanceNonce] = _amount;
    }

    function setRedemptionInputAmount(uint256 _redemptionNonce, uint256 _amount) external onlyFactory {
        require(_amount > 0, "Invalid redemption input amount");
        redemptionInputAmount[_redemptionNonce] = _amount;
    }

    function setActionInfoById(uint256 _requestId, ActionInfo memory _actionInfo) external onlyFactory {
        require(_requestId > 0, "Invalid Request Id");
        actionInfoById[_requestId] = _actionInfo;
    }

    function setCancelIssuanceUnfilledAmount(uint256 _issuanceNonce, address _token, uint256 _amount)
        external
        onlyFactory
    {
        require(_amount > 0, "Invalid cancel issuance unfilled amount");
        require(_token != address(0), "Invalid token address");
        cancelIssuanceUnfilledAmount[_issuanceNonce][_token] = _amount;
    }

    function setCancelRedemptionUnfilledAmount(uint256 _redemptionNonce, address _token, uint256 _amount)
        external
        onlyFactory
    {
        require(_amount > 0, "Invalid cancel redemption unfilled amount");
        require(_token != address(0), "Invalid token address");
        cancelRedemptionUnfilledAmount[_redemptionNonce][_token] = _amount;
    }

    function setCancelIssuanceComplted(uint256 _issuanceNonce, bool _isCompleted) external onlyFactory {
        cancelIssuanceComplted[_issuanceNonce] = _isCompleted;
    }

    function setCancelRedemptionComplted(uint256 _redemptionNonce, bool _isCompleted) external onlyFactory {
        cancelRedemptionComplted[_redemptionNonce] = _isCompleted;
    }

    function setOrderInstanceById(uint256 _requestId, IOrderProcessor.Order memory _order) external onlyFactory {
        require(_requestId > 0, "Invalid Request Id");
        orderInstanceById[_requestId] = _order;
    }

    function getOrderInstanceById(uint256 _id) public view returns (IOrderProcessor.Order memory) {
        require(_id > 0, "Invalid Request Id");
        return orderInstanceById[_id];
    }

    function getActionInfoById(uint256 _id) public view returns (ActionInfo memory) {
        require(_id > 0, "Invalid Request Id");
        return actionInfoById[_id];
    }

    function getVaultDshareBalance(address _token) public view returns (uint256) {
        require(_token != address(0), "invalid token address");
        address wrappedDshareAddress = wrappedDshareAddress[_token];
        uint256 wrappedDshareBalance = IERC20(wrappedDshareAddress).balanceOf(address(vault));
        uint256 dshareBalance = WrappedDShare(wrappedDshareAddress).previewRedeem(wrappedDshareBalance);
        uint256 finalDshareBalance = dshareBalance + tokenPendingRebalanceAmount[_token];
        return finalDshareBalance;
    }

    function getAmountAfterFee(uint24 percentageFeeRate, uint256 orderValue) public pure returns (uint256) {
        return percentageFeeRate != 0 ? PrbMath.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate)) : 0;
    }

    function getVaultDshareValue(address _token) public view returns (uint256) {
        require(_token != address(0), "invalid token address");
        uint256 tokenPrice = priceInWei(_token);
        uint256 dshareBalance = getVaultDshareBalance(_token);
        return (dshareBalance * tokenPrice) / 1e18;
    }

    function getPortfolioValue() public view returns (uint256) {
        uint256 portfolioValue;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            uint256 tokenValue = getVaultDshareValue(functionsOracle.currentList(i));
            portfolioValue += tokenValue;
        }
        return portfolioValue;
    }

    function getIndexTokenPrice() public view returns (uint256) {
        uint256 totalSupply = token.totalSupply();
        uint256 portfolioValue = getPortfolioValue();
        if (totalSupply == 0) {
            return 0;
        }
        return portfolioValue * 1e18 / totalSupply;
    }

    function _toWei(int256 _amount, uint8 _amountDecimals, uint8 _chainDecimals) private pure returns (int256) {
        require(_amountDecimals <= 18, "amount decimals should be less than or equal to 18");
        require(_chainDecimals <= 18, "chain decimals should be less than or equal to 18");

        if (_chainDecimals > _amountDecimals) {
            return _amount * int256(10 ** (_chainDecimals - _amountDecimals));
        } else {
            return _amount * int256(10 ** (_amountDecimals - _chainDecimals));
        }
    }

    function priceInWei(address _tokenAddress) public view returns (uint256) {
        require(_tokenAddress != address(0), "invalid token address");
        if (isMainnet) {
            address feedAddress = priceFeedByTokenAddress[_tokenAddress];
            (uint80 roundId, int256 price,, uint256 _updatedAt,) = AggregatorV3Interface(feedAddress).latestRoundData();
            require(roundId != 0, "invalid round id");
            require(_updatedAt != 0 && _updatedAt <= block.timestamp, "invalid updated time");
            require(price > 0, "invalid price");
            require(block.timestamp - _updatedAt < 1 days, "invalid updated time");

            uint8 priceFeedDecimals = AggregatorV3Interface(feedAddress).decimals();
            price = _toWei(price, priceFeedDecimals, 18);
            return uint256(price);
        } else {
            IOrderProcessor.PricePoint memory tokenPriceData = issuer.latestFillPrice(_tokenAddress, address(usdc));
            int256 price = _toWei(int256(tokenPriceData.price), latestPriceDecimals, 18);
            return uint256(price);
        }
    }

    function getPrimaryOrder(bool sell) external view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: address(this),
            assetToken: address(token),
            paymentToken: address(usdc),
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? 100 ether : 0,
            paymentTokenQuantity: sell ? 0 : 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function getIssuanceAmountOut(uint256 _amount) public view returns (uint256) {
        require(_amount > 0, "Invalid amount");
        uint256 portfolioValue = getPortfolioValue();
        uint256 totalSupply = token.totalSupply();
        uint256 amountOut = _amount * totalSupply / portfolioValue;
        return amountOut;
    }

    function getRedemptionAmountOut(uint256 _amount) public view returns (uint256) {
        require(_amount > 0, "Invalid amount");
        uint256 portfolioValue = getPortfolioValue();
        uint256 totalSupply = token.totalSupply();
        uint256 amountOut = _amount * portfolioValue / totalSupply;
        return amountOut;
    }

    function calculateBuyRequestFee(uint256 _amount) public view returns (uint256) {
        require(_amount > 0, "Invalid amount");
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint256 fee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, _amount);
        return fee;
    }

    function calculateIssuanceFee(uint256 _inputAmount) public view returns (uint256) {
        require(_inputAmount > 0, "Invalid amount");
        uint256 fees;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 amount = _inputAmount * functionsOracle.tokenCurrentMarketShare(tokenAddress) / 100e18;
            (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
            uint256 fee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, amount);
            fees += fee;
        }
        return fees;
    }

    function checkCancelIssuanceStatus(uint256 _issuanceNonce) public view returns (bool) {
        uint256 completedCount;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            uint256 receivedAmount = issuer.getReceivedAmount(requestId);
            if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED)) {
                if (receivedAmount == 0) {
                    completedCount += 1;
                } else {
                    uint256 cancelRequestId = cancelIssuanceRequestId[_issuanceNonce][tokenAddress];
                    if (uint8(issuer.getOrderStatus(cancelRequestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                        completedCount += 1;
                    }
                }
            } else if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                uint256 cancelRequestId = cancelIssuanceRequestId[_issuanceNonce][tokenAddress];
                if (uint8(issuer.getOrderStatus(cancelRequestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                    completedCount += 1;
                }
            }
        }
        if (completedCount == functionsOracle.totalCurrentList()) {
            return true;
        } else {
            return false;
        }
    }

    function isIssuanceOrderActive(uint256 _issuanceNonce) public view returns (bool) {
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)) {
                return true;
            }
        }
        return false;
    }

    function checkIssuanceOrdersStatus(uint256 _issuanceNonce) public view returns (bool) {
        uint256 completedOrdersCount;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                completedOrdersCount += 1;
            }
        }
        if (completedOrdersCount == functionsOracle.totalCurrentList()) {
            return true;
        } else {
            return false;
        }
    }

    function checkRedemptionOrdersStatus(uint256 _redemptionNonce) public view returns (bool) {
        uint256 completedOrdersCount;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                completedOrdersCount += 1;
            }
        }
        if (completedOrdersCount == functionsOracle.totalCurrentList()) {
            return true;
        } else {
            return false;
        }
    }

    function isRedemptionOrderActive(uint256 _redemptionNonce) public view returns (bool) {
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)) {
                return true;
            }
        }
        return false;
    }

    function checkCancelRedemptionStatus(uint256 _redemptionNonce) public view returns (bool) {
        uint256 completedCount;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            uint256 receivedAmount = issuer.getReceivedAmount(requestId);
            if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED)) {
                if (receivedAmount == 0) {
                    completedCount += 1;
                } else {
                    uint256 cancelRequestId = cancelRedemptionRequestId[_redemptionNonce][tokenAddress];
                    if (uint8(issuer.getOrderStatus(cancelRequestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                        completedCount += 1;
                    }
                }
            } else if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                uint256 cancelRequestId = cancelRedemptionRequestId[_redemptionNonce][tokenAddress];
                if (uint8(issuer.getOrderStatus(cancelRequestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)) {
                    completedCount += 1;
                }
            }
        }
        if (completedCount == functionsOracle.totalCurrentList()) {
            return true;
        } else {
            return false;
        }
    }
}
