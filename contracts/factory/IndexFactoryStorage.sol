// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../dinary/WrappedDShare.sol";
import "../vault/NexVault.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./OrderManager.sol";
import "./FunctionsOracle.sol";
import "../libraries/Commen.sol" as PrbMath;

/// @title Index Token Factory Storage
/// @notice Stores data and provides functions for managing index token issuance and redemption
contract IndexFactoryStorage is
    Initializable,
    OwnableUpgradeable
{
    using FunctionsRequest for FunctionsRequest.Request;

    enum ActionState {
        NONE,
        PENDING,
        CANCEL_REQUESTED,
        COMPLETED,
        CANCELLED
    }

    enum OrderType {
        BUY,
        SELL
    }

    error NonMainnetPriceUnavailable();
    error InsufficientPendingIssuanceUsdc();
    error InsufficientPendingRedemptionAsset();

    // Addresses of factory contracts
    address public factoryAddress;
    address public factoryBalancerAddress;
    address public factoryProcessorAddress;


    uint totalDshareAddresses;



    // Mappings for wrapped DShare addresses
    mapping(address => address) public wrappedDshareAddress;

    

    // Mappings for price feeds by token address
    mapping(address => address) public priceFeedByTokenAddress;

    // Contract instances
    IndexToken public token;
    NexVault public vault;
    address public usdc;
    uint8 public usdcDecimals;
    OrderManager public orderManager;
    bool public isMainnet;
    FunctionsOracle public functionsOracle;

    // New variables
    uint8 public feeRate; // 10/10000 = 0.1%
    uint256 public latestFeeUpdate;
    uint public issuanceNonce;
    uint public redemptionNonce;

    uint8 public latestPriceDecimals;
    address public feeReceiver;

    // Mappings for issuance and redemption data
    mapping(uint256 => ActionState) public issuanceState;
    mapping(uint256 => ActionState) public redemptionState;
    mapping(uint => uint) public burnedTokenAmountByNonce;
    mapping(uint => mapping(address => uint)) public issuanceTokenPrimaryBalance;
    mapping(uint => uint) public issuanceIndexTokenPrimaryTotalSupply;
    mapping(uint => address) public issuanceRequesterByNonce;
    mapping(uint => address) public redemptionRequesterByNonce;
    mapping(uint => bool) public cancelIssuanceCompleted;
    mapping(uint => bool) public cancelRedemptionCompleted;
    mapping(uint => uint) public issuanceInputAmount;
    mapping(uint => uint) public redemptionInputAmount;

    mapping(address => uint) public tokenPendingRebalanceAmount;
    mapping(address => mapping(uint => uint)) public tokenPendingRebalanceAmountByNonce;
    mapping(address => bool) public isUserActionPending;
    /// @notice Latest issuance nonce opened by this user while `isUserActionPending` (O(1) emergency checks). 0 = none.
    mapping(address => uint256) public userPendingIssuanceNonce;
    /// @notice Latest redemption nonce opened by this user while `isUserActionPending` (O(1) emergency checks). 0 = none.
    mapping(address => uint256) public userPendingRedemptionNonce;

    /// @notice USDC held in OrderManager that is reserved for unsettled issuance intents (logical escrow).
    uint256 public pendingIssuanceUsdc;
    /// @notice dShare units (underlying asset) reserved across all pending redemptions, per asset.
    mapping(address => uint256) public pendingRedemptionAsset;
    /// @notice Wall-clock start of an issuance intent (for timeout cancel).
    mapping(uint256 => uint256) public issuanceIntentTimestamp;
    /// @notice Wall-clock start of a redemption intent (for timeout cancel).
    mapping(uint256 => uint256) public redemptionIntentTimestamp;
    /// @notice Per-redemption-nonce dShare amount escrowed per asset (must match decrements on settle/cancel).
    mapping(uint256 => mapping(address => uint256)) public redemptionEscrowedAssetByNonce;
    /// @notice Constituent order at issuance intent creation (TOCTOU-safe vs oracle list changes).
    mapping(uint256 => address[]) private _issuanceSnapshotTokens;
    /// @notice Tokens that received redemption escrow for this nonce (TOCTOU-safe vs oracle list changes).
    mapping(uint256 => address[]) private _redemptionEscrowSnapshotTokens;

    event OrderIntentCreated(
        bytes32 indexed intentId,
        address indexed user,
        address indexed assetAddress,
        uint256 amountIn,
        uint8 orderType,
        uint256 nonce
    );

    /// @notice Initializes the contract with the given parameters
    /// @param _token The address of the token
    /// @param _vault The address of the vault
    /// @param _usdc The address of the USDC token
    /// @param _usdcDecimals The decimals of the USDC token
    //  @param _functionsOracle the address of functions oracle contract
    /// @param _isMainnet Boolean indicating if the contract is on mainnet
    function initialize(
        address _token,
        address _vault,
        address _usdc,
        uint8 _usdcDecimals,
        address _functionsOracle,
        bool _isMainnet
    ) external initializer {
        require(_token != address(0), "invalid token address");
        require(_vault != address(0), "invalid vault address");
        require(_usdc != address(0), "invalid usdc address");
        require(_functionsOracle != address(0), "invalid functions oracle address");
        require(_usdcDecimals > 0, "invalid decimals");
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
        require(msg.sender == factoryAddress || msg.sender == factoryProcessorAddress || msg.sender == factoryBalancerAddress, "Caller is not a factory contract");
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
    function setUsdcAddress(
        address _usdc,
        uint8 _usdcDecimals
    ) public onlyOwner returns (bool) {
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
    function setTokenAddress(
        address _token
    ) public onlyOwner returns (bool) {
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

    

    function setWrappedDshareAndPriceFeedAddresses(address[] memory _dShares, address[] memory _wrappedDShares, address[] memory _priceFeedAddresses) public onlyOwner {
        require(_dShares.length == _wrappedDShares.length, "Array length mismatch");
        require(_dShares.length == _priceFeedAddresses.length, "Array length mismatch");
        for(uint i = 0; i < _dShares.length; i++){
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

    function increaseTokenPendingRebalanceAmount(address _token, uint _nonce, uint _amount) external onlyFactory {
        require(_token != address(0), "invalid token address");
        require(_amount > 0, "Invalid amount");
        tokenPendingRebalanceAmount[_token] += _amount;
        tokenPendingRebalanceAmountByNonce[_token][_nonce] += _amount;
    }
    
    function decreaseTokenPendingRebalanceAmount(address _token, uint _nonce, uint _amount) external onlyFactory {
        require(_token != address(0), "invalid token address");
        require(_amount > 0, "Invalid amount");
        require(tokenPendingRebalanceAmount[_token] >= _amount, "Insufficient pending rebalance amount");
        tokenPendingRebalanceAmount[_token] -= _amount;
        tokenPendingRebalanceAmountByNonce[_token][_nonce] -= _amount;
    }

    function resetTokenPendingRebalanceAmount(address _token, uint _nonce) public onlyOwnerOrOperator {
        require(_token != address(0), "invalid token address");
        tokenPendingRebalanceAmount[_token] = 0;
        tokenPendingRebalanceAmountByNonce[_token][_nonce] = 0;
    }

    function resetAllTokenPendingRebalanceAmount(uint _nonce) public onlyOwnerOrOperator {
        for(uint i; i < functionsOracle.totalCurrentList(); i++) {
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
    
    function setIssuanceState(uint256 _issuanceNonce, ActionState _state) external onlyFactory {
        issuanceState[_issuanceNonce] = _state;
    }

    function setRedemptionState(uint256 _redemptionNonce, ActionState _state) external onlyFactory {
        redemptionState[_redemptionNonce] = _state;
    }

    function setUserActionPending(address _user, bool _isPending) external onlyFactory {
        require(_user != address(0), "invalid user");
        isUserActionPending[_user] = _isPending;
    }

    function setUserPendingIssuanceNonce(address user, uint256 nonce) external onlyFactory {
        require(user != address(0), "invalid user");
        userPendingIssuanceNonce[user] = nonce;
    }

    function setUserPendingRedemptionNonce(address user, uint256 nonce) external onlyFactory {
        require(user != address(0), "invalid user");
        userPendingRedemptionNonce[user] = nonce;
    }

    /// @notice Clears issuance pointer if it matches `nonce`. Returns whether the pointer matched.
    function tryClearUserPendingIssuanceNonce(address user, uint256 nonce) external onlyFactory returns (bool) {
        if (userPendingIssuanceNonce[user] != nonce) {
            return false;
        }
        userPendingIssuanceNonce[user] = 0;
        return true;
    }

    /// @notice Clears redemption pointer if it matches `nonce`. Returns whether the pointer matched.
    function tryClearUserPendingRedemptionNonce(address user, uint256 nonce) external onlyFactory returns (bool) {
        if (userPendingRedemptionNonce[user] != nonce) {
            return false;
        }
        userPendingRedemptionNonce[user] = 0;
        return true;
    }

    /// @notice Clears both intent pointers (e.g. emergency unlock).
    function clearUserPendingIntentNonces(address user) external onlyFactory {
        require(user != address(0), "invalid user");
        userPendingIssuanceNonce[user] = 0;
        userPendingRedemptionNonce[user] = 0;
    }

    function emitOrderIntentCreated(
        address _user,
        address _assetAddress,
        uint256 _amountIn,
        OrderType _orderType,
        uint256 _nonce
    ) external onlyFactory returns (bytes32) {
        require(_user != address(0), "invalid user");
        require(_assetAddress != address(0), "invalid asset");
        bytes32 intentId =
            keccak256(abi.encodePacked(block.chainid, address(this), _nonce, _user, _assetAddress, _amountIn, _orderType));
        emit OrderIntentCreated(intentId, _user, _assetAddress, _amountIn, uint8(_orderType), _nonce);
        return intentId;
    }

    function setBurnedTokenAmountByNonce(uint _redemptionNonce , uint _burnedAmount) external onlyFactory {
        require(_burnedAmount > 0, "Invalid burn amount");
        burnedTokenAmountByNonce[_redemptionNonce] = _burnedAmount;
    }

    function setIssuanceRequesterByNonce(uint _issuanceNonce, address _requester) external onlyFactory {
        require(_requester != address(0), "Invalid issuance requester address");
        issuanceRequesterByNonce[_issuanceNonce] = _requester;
    }

    function setRedemptionRequesterByNonce(uint _redemptionNonce, address _requester) external onlyFactory {
        require(_requester != address(0), "Invalid redemption requester address");
        redemptionRequesterByNonce[_redemptionNonce] = _requester;
    }

    function setIssuanceTokenPrimaryBalance(uint _issuanceNonce, address _token, uint _amount) external onlyFactory {
        require(_token != address(0), "Invalid issuance primary token address");
        issuanceTokenPrimaryBalance[_issuanceNonce][_token] = _amount;
    }

    

    function setIssuanceIndexTokenPrimaryTotalSupply(uint _issuanceNonce, uint _amount) external onlyFactory {
        issuanceIndexTokenPrimaryTotalSupply[_issuanceNonce] = _amount;
    }

    

    function setIssuanceInputAmount(uint _issuanceNonce, uint _amount) external onlyFactory {
        require(_amount > 0, "Invalid issuance input amount");
        issuanceInputAmount[_issuanceNonce] = _amount;
    }

    function setRedemptionInputAmount(uint _redemptionNonce, uint _amount) external onlyFactory {
        require(_amount > 0, "Invalid redemption input amount");
        redemptionInputAmount[_redemptionNonce] = _amount;
    }

    function setCancelIssuanceCompleted(uint _issuanceNonce, bool _isCompleted) external onlyFactory {
        cancelIssuanceCompleted[_issuanceNonce] = _isCompleted;
    }

    function setCancelRedemptionCompleted(uint _redemptionNonce, bool _isCompleted) external onlyFactory {
        cancelRedemptionCompleted[_redemptionNonce] = _isCompleted;
    }

    function getVaultDshareBalance(address _token) public view returns(uint){
        require(_token != address(0), "invalid token address");
        address wrappedDshareAddress = wrappedDshareAddress[_token];
        uint wrappedDshareBalance = IERC20(wrappedDshareAddress).balanceOf(address(vault));
        uint dshareBalance = WrappedDShare(wrappedDshareAddress).previewRedeem(wrappedDshareBalance);
        uint finalDshareBalance = dshareBalance + tokenPendingRebalanceAmount[_token];
        return finalDshareBalance;
    }

    function getAmountAfterFee(uint24 percentageFeeRate, uint256 orderValue) public pure returns (uint256) {
        return percentageFeeRate != 0 ? PrbMath.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate)) : 0;
    }
    
    function getVaultDshareValue(address _token) public view returns(uint){
        require(_token != address(0), "invalid token address");
        uint tokenPrice = priceInWei(_token);
        uint dshareBalance = getVaultDshareBalance(_token);
        return (dshareBalance * tokenPrice)/1e18;
    }
    

    function getPortfolioValue() public view returns(uint){
        uint portfolioValue;
        for(uint i; i < functionsOracle.totalCurrentList(); i++) {
            uint tokenValue = getVaultDshareValue(functionsOracle.currentList(i));
            portfolioValue += tokenValue;
        }
        return portfolioValue;
    }

    /// @notice Aggregate USD value (18 decimals) of dShares marked pending for redemption settlement.
    function getPendingRedemptionAssetsValue() public view returns (uint256) {
        uint256 pendingValue;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 qty = pendingRedemptionAsset[tokenAddress];
            if (qty > 0) {
                uint256 tokenPrice = priceInWei(tokenAddress);
                pendingValue += (qty * tokenPrice) / 1e18;
            }
        }
        return pendingValue;
    }

    /// @notice USDC on OrderManager that is not reserved for pending issuances, normalized to 18 decimals.
    function getDeployableOrderManagerUsdcValue() public view returns (uint256) {
        uint256 bal = IERC20(usdc).balanceOf(address(orderManager));
        uint256 deployable = bal > pendingIssuanceUsdc ? bal - pendingIssuanceUsdc : 0;
        if (deployable == 0) {
            return 0;
        }
        if (usdcDecimals > 18) {
            return deployable / (10 ** (usdcDecimals - 18));
        }
        return deployable * (10 ** (18 - usdcDecimals));
    }

    /// @notice NAV numerator for index pricing: vault TVL minus pending redemption claims plus deployable USDC on OrderManager.
    function getNavPortfolioValue() public view returns (uint256) {
        uint256 vaultVal = getPortfolioValue();
        uint256 pendingRedVal = getPendingRedemptionAssetsValue();
        uint256 vaultNet = vaultVal > pendingRedVal ? vaultVal - pendingRedVal : 0;
        return vaultNet + getDeployableOrderManagerUsdcValue();
    }

    function getIndexTokenPrice() public view returns(uint){
        uint totalSupply = token.totalSupply();
        uint256 portfolioValue = getNavPortfolioValue();
        if(totalSupply == 0){
            return 0;
        }
        return uint256(portfolioValue * 1e18 / totalSupply);
    }

    function _toWei(int256 _amount, uint8 _amountDecimals, uint8 _chainDecimals) private pure returns (int256) {     
        require(_amountDecimals <= 18, "amount decimals should be less than or equal to 18");
        require(_chainDecimals <= 18, "chain decimals should be less than or equal to 18");

        if (_chainDecimals > _amountDecimals){
            return _amount * int256(10 **(_chainDecimals - _amountDecimals));
        }else{
            return _amount * int256(10 **(_amountDecimals - _chainDecimals));
        }
    }

    function priceInWei(address _tokenAddress) public view returns (uint256) {
        require(_tokenAddress != address(0), "invalid token address");
        if (!isMainnet) {
            revert NonMainnetPriceUnavailable();
        }
        address feedAddress = priceFeedByTokenAddress[_tokenAddress];
        (uint80 roundId,int price,,uint256 _updatedAt,) = AggregatorV3Interface(feedAddress).latestRoundData();
        require(roundId != 0, "invalid round id");
        require(_updatedAt != 0 && _updatedAt <= block.timestamp, "invalid updated time");
        require(price > 0, "invalid price");
        require(block.timestamp - _updatedAt < 1 days, "invalid updated time");

        uint8 priceFeedDecimals = AggregatorV3Interface(feedAddress).decimals();
        price = _toWei(price, priceFeedDecimals, 18);
        return uint256(price);
    }
    
    function getIssuanceAmountOut(uint _amount) public view returns(uint){
        require(_amount > 0, "Invalid amount");
        uint256 portfolioValue = getNavPortfolioValue();
        require(portfolioValue > 0, "Invalid portfolio value");
        uint totalSupply = token.totalSupply();
        uint amountOut = _amount * totalSupply / portfolioValue;
        return amountOut;
    }

    function getRedemptionAmountOut(uint _amount) public view returns(uint){
        require(_amount > 0, "Invalid amount");
        uint256 portfolioValue = getNavPortfolioValue();
        uint totalSupply = token.totalSupply();
        require(totalSupply > 0, "Invalid total supply");
        uint amountOut = _amount * portfolioValue / totalSupply;
        return amountOut;
    }

    

    function calculateBuyRequestFee(uint _amount) public pure returns(uint){
        require(_amount > 0, "Invalid amount");
        return 0;
    }

    function calculateIssuanceFee(uint _inputAmount) public pure returns(uint256){
        require(_inputAmount > 0, "Invalid amount");
        return 0;
    }

    /// @notice USDC sent to OrderManager for this issuance nonce (matches initiation escrow).
    function getIssuanceEscrowedUsdc(uint256 _issuanceNonce) public view returns (uint256) {
        uint256 input = issuanceInputAmount[_issuanceNonce];
        if (input == 0) {
            return 0;
        }
        return calculateIssuanceFee(input) + input;
    }

    function increasePendingIssuanceUsdc(uint256 _amount) external onlyFactory {
        pendingIssuanceUsdc += _amount;
    }

    function decreasePendingIssuanceUsdc(uint256 _amount) external onlyFactory {
        if (_amount > pendingIssuanceUsdc) {
            revert InsufficientPendingIssuanceUsdc();
        }
        pendingIssuanceUsdc -= _amount;
    }

    function recordRedemptionEscrowSlice(uint256 _nonce, address _token, uint256 _amount) external onlyFactory {
        require(_token != address(0), "invalid token address");
        require(_amount > 0, "Invalid amount");
        require(redemptionEscrowedAssetByNonce[_nonce][_token] == 0, "escrow already recorded");
        redemptionEscrowedAssetByNonce[_nonce][_token] = _amount;
        pendingRedemptionAsset[_token] += _amount;
        _redemptionEscrowSnapshotTokens[_nonce].push(_token);
    }

    /// @notice Length of the issuance constituent snapshot for this nonce (0 = pre-migration, use live oracle in processor).
    function issuanceSnapshotLength(uint256 _nonce) external view returns (uint256) {
        return _issuanceSnapshotTokens[_nonce].length;
    }

    /// @notice Token at index in the issuance snapshot (same order as at intent creation).
    function issuanceSnapshotTokenAt(uint256 _nonce, uint256 _index) external view returns (address) {
        return _issuanceSnapshotTokens[_nonce][_index];
    }

    function pushIssuanceSnapshotToken(uint256 _nonce, address _token) external onlyFactory {
        require(_token != address(0), "invalid token address");
        _issuanceSnapshotTokens[_nonce].push(_token);
    }

    function clearIssuanceSnapshot(uint256 _nonce) external onlyFactory {
        delete _issuanceSnapshotTokens[_nonce];
    }

    function consumeRedemptionEscrowForNonce(uint256 _nonce) external onlyFactory {
        address[] storage snapshot = _redemptionEscrowSnapshotTokens[_nonce];
        if (snapshot.length > 0) {
            for (uint256 i; i < snapshot.length; i++) {
                address tokenAddress = snapshot[i];
                uint256 amt = redemptionEscrowedAssetByNonce[_nonce][tokenAddress];
                if (amt == 0) {
                    continue;
                }
                if (amt > pendingRedemptionAsset[tokenAddress]) {
                    revert InsufficientPendingRedemptionAsset();
                }
                pendingRedemptionAsset[tokenAddress] -= amt;
                redemptionEscrowedAssetByNonce[_nonce][tokenAddress] = 0;
            }
            delete _redemptionEscrowSnapshotTokens[_nonce];
        } else {
            for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
                address tokenAddress = functionsOracle.currentList(i);
                uint256 amt = redemptionEscrowedAssetByNonce[_nonce][tokenAddress];
                if (amt == 0) {
                    continue;
                }
                if (amt > pendingRedemptionAsset[tokenAddress]) {
                    revert InsufficientPendingRedemptionAsset();
                }
                pendingRedemptionAsset[tokenAddress] -= amt;
                redemptionEscrowedAssetByNonce[_nonce][tokenAddress] = 0;
            }
        }
    }

    function setIssuanceIntentTimestamp(uint256 _issuanceNonce, uint256 _createdAt) external onlyFactory {
        issuanceIntentTimestamp[_issuanceNonce] = _createdAt;
    }

    function setRedemptionIntentTimestamp(uint256 _redemptionNonce, uint256 _createdAt) external onlyFactory {
        redemptionIntentTimestamp[_redemptionNonce] = _createdAt;
    }
}
