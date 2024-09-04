// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
// import "../token/RequestNFT.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../chainlink/ChainlinkClient.sol";
import "../dinary/orders/IOrderProcessor.sol";
import "../dinary/WrappedDShare.sol";
import "../vault/NexVault.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./OrderManager.sol";
import "../libraries/Commen.sol" as PrbMath;
// import "./IndexFactory.sol";
// import "./IndexFactoryBalancer.sol";
// import "./IndexFactoryProcessor.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryStorage is
    Initializable,
    ChainlinkClient,
    OwnableUpgradeable
{
    using Chainlink for Chainlink.Request;

    struct ActionInfo {
        uint actionType;
        uint nonce; 
    }
    
    string public baseUrl;
    string public urlParams;

    address public factoryAddress;
    address public factoryBalancerAddress;
    address public factoryProcessorAddress;

    bytes32 public externalJobId;
    uint256 public oraclePayment;
    uint public lastUpdateTime;

    uint public totalOracleList;
    uint public totalCurrentList;

    mapping(uint => address) public oracleList;
    mapping(uint => address) public currentList;

    mapping(address => address) public wrappedDshareAddress;

    mapping(address => uint) public tokenOracleListIndex;
    mapping(address => uint) public tokenCurrentListIndex;

    mapping(address => uint) public tokenCurrentMarketShare;
    mapping(address => uint) public tokenOracleMarketShare;

    
    mapping(address => address) public priceFeedByTokenAddress;

    IndexToken public token;
    NexVault public vault;
    IOrderProcessor public issuer;
    address public usdc;
    uint8 public usdcDecimals;
    OrderManager public orderManager;
    bool public isMainnet;

    // new
    uint8 public feeRate; // 10/10000 = 0.1%
    uint256 public latestFeeUpdate;
    uint public issuanceNonce;
    uint public redemptionNonce;

    uint8 public latestPriceDecimals;

    mapping(uint => bool) public issuanceIsCompleted;
    mapping(uint => bool) public redemptionIsCompleted;
    mapping(uint => uint) public burnedTokenAmountByNonce;
    mapping(uint => mapping(address => uint)) public cancelIssuanceRequestId;
    mapping(uint => mapping(address => uint)) public cancelRedemptionRequestId;
    mapping(uint => mapping(address => uint)) public issuanceRequestId;
    mapping(uint => mapping(address => uint)) public redemptionRequestId;
    mapping(uint => uint) public buyRequestPayedAmountById;
    mapping(uint => uint) public sellRequestAssetAmountById;
    mapping(uint => mapping(address => uint)) public issuanceTokenPrimaryBalance;
    mapping(uint => mapping(address => uint)) public redemptionTokenPrimaryBalance;
    mapping(uint => uint) public issuanceIndexTokenPrimaryTotalSupply;
    mapping(uint => uint) public redemptionIndexTokenPrimaryTotalSupply;
    mapping(uint => address) public issuanceRequesterByNonce;
    mapping(uint => address) public redemptionRequesterByNonce;
    mapping(uint => bool) public cancelIssuanceComplted;
    mapping(uint => bool) public cancelRedemptionComplted;
    mapping(uint =>  IOrderProcessor.Order) public orderInstanceById;
    mapping(uint => uint) public issuanceInputAmount;
    mapping(uint => uint) public redemptionInputAmount;
    mapping(uint => ActionInfo) public actionInfoById;
    mapping(uint => mapping(address => uint)) public cancelIssuanceUnfilledAmount;
    mapping(uint => mapping(address => uint)) public cancelRedemptionUnfilledAmount;

    function initialize(
        address _issuer,
        address _token,
        address _vault,
        address _usdc,
        uint8 _usdcDecimals,
        address _chainlinkToken,
        address _oracleAddress,
        bytes32 _externalJobId,
        bool _isMainnet
    ) external initializer {
        issuer = IOrderProcessor(_issuer);
        token = IndexToken(_token);
        vault = NexVault(_vault);
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        __Ownable_init(msg.sender);
        //set oracle data
        setChainlinkToken(_chainlinkToken);
        setChainlinkOracle(_oracleAddress);
        externalJobId = _externalJobId;
        oraclePayment = ((1 * LINK_DIVISIBILITY) / 10); // n * 10**18
        baseUrl = "https://app.nexlabs.io/api/allFundingRates";
        urlParams = "?multiplyFunc=18&timesNegFund=true&arrays=true";
        isMainnet = _isMainnet;
        feeRate = 10;
    }

    modifier onlyFactory() {
        require(msg.sender == factoryAddress || msg.sender == factoryProcessorAddress || msg.sender == factoryBalancerAddress, "Caller is not a factory contract");
        _;
    }
    //Notice: newFee should be between 1 to 100 (0.01% - 1%)
    function setFeeRate(uint8 _newFee) public onlyOwner {
    uint256 distance = block.timestamp - latestFeeUpdate;
    require(distance / 60 / 60 > 12, "You should wait at least 12 hours after the latest update");
    require(_newFee <= 10000 && _newFee >= 1, "The newFee should be between 1 and 100 (0.01% - 1%)");
    feeRate = _newFee;
    latestFeeUpdate = block.timestamp;
    }

    function setIsMainnet(bool _isMainnet) public onlyOwner {
        isMainnet = _isMainnet;
    }

    function setUsdcAddress(
        address _usdc,
        uint8 _usdcDecimals
    ) public onlyOwner returns (bool) {
        require(_usdc != address(0), "invalid token address");
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        return true;
    }

    function setLatestPriceDecimals(uint8 _decimals) public onlyOwner {
        latestPriceDecimals = _decimals;
    }

    function setTokenAddress(
        address _token
    ) public onlyOwner returns (bool) {
        require(_token != address(0), "invalid token address");
        token = IndexToken(_token);
        return true;
    }

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

    function setWrappedDShareAddresses(address[] memory _dShares, address[] memory _wrappedDShares) public onlyOwner {
        require(_dShares.length == _wrappedDShares.length, "Array length mismatch");
        for(uint i = 0; i < _dShares.length; i++){
            wrappedDshareAddress[_dShares[i]] = _wrappedDShares[i];
        }
    }

    function setPriceFeedAddresses(address[] memory _dShares, address[] memory _priceFeedAddresses) public onlyOwner {
        require(_dShares.length == _priceFeedAddresses.length, "Array length mismatch");
        for(uint i = 0; i < _dShares.length; i++){
            priceFeedByTokenAddress[_dShares[i]] = _priceFeedAddresses[i];
        }
    }

    function setUrl(string memory _beforeAddress, string memory _afterAddress) public onlyOwner{
    baseUrl = _beforeAddress;
    urlParams = _afterAddress;
    }

    function setOracleInfo(address _oracleAddress, bytes32 _externalJobId) public onlyOwner {
        setChainlinkOracle(_oracleAddress);
        externalJobId = _externalJobId;
    }

    function setFactory(address _factoryAddress) public onlyOwner {
        factoryAddress = _factoryAddress;
    }

    function setFactoryBalancer(address _factoryBalancerAddress) public onlyOwner {
        factoryBalancerAddress = _factoryBalancerAddress;
    }

    function setFactoryProcessor(address _factoryProcessorAddress) public onlyOwner {
        factoryProcessorAddress = _factoryProcessorAddress;
    }

    function increaseIssuanceNonce() external onlyFactory {
        issuanceNonce += 1;
    }

    function increaseRedemptionNonce() external onlyFactory {
        redemptionNonce += 1;
    }
    
    function setIssuanceIsCompleted(uint _issuanceNonce , bool _isCompleted) external onlyFactory {
        issuanceIsCompleted[_issuanceNonce] = _isCompleted;
    }

    function setRedemptionIsCompleted(uint _redemptionNonce , bool _isCompleted) external onlyFactory {
        redemptionIsCompleted[_redemptionNonce] = _isCompleted;
    }

    function setBurnedTokenAmountByNonce(uint _redemptionNonce , uint _burnedAmount) external onlyFactory {
        burnedTokenAmountByNonce[_redemptionNonce] = _burnedAmount;
    }

    function setIssuanceRequestId(uint _issuanceNonce, address _token, uint _requestId) external onlyFactory {
        issuanceRequestId[_issuanceNonce][_token] = _requestId;
    }

    function setRedemptionRequestId(uint _redemptionNonce, address _token, uint _requestId) external onlyFactory {
        redemptionRequestId[_redemptionNonce][_token] = _requestId;
    }

    function setIssuanceRequesterByNonce(uint _issuanceNonce, address _requester) external onlyFactory {
        issuanceRequesterByNonce[_issuanceNonce] = _requester;
    }

    function setRedemptionRequesterByNonce(uint _redemptionNonce, address _requester) external onlyFactory {
        redemptionRequesterByNonce[_redemptionNonce] = _requester;
    }

    function setCancelIssuanceRequestId(uint _issuanceNonce, address _token, uint _requestId) external onlyFactory {
        cancelIssuanceRequestId[_issuanceNonce][_token] = _requestId;
    }

    function setCancelRedemptionRequestId(uint _redemptionNonce, address _token, uint _requestId) external onlyFactory {
        cancelRedemptionRequestId[_redemptionNonce][_token] = _requestId;
    }

    function setBuyRequestPayedAmountById(uint _requestId, uint _amount) external onlyFactory {
        buyRequestPayedAmountById[_requestId] = _amount;
    }

    function setSellRequestAssetAmountById(uint _requestId, uint _amount) external onlyFactory {
        sellRequestAssetAmountById[_requestId] = _amount;
    }

    function setIssuanceTokenPrimaryBalance(uint _issuanceNonce, address _token, uint _amount) external onlyFactory {
        issuanceTokenPrimaryBalance[_issuanceNonce][_token] = _amount;
    }

    function setRedemptionTokenPrimaryBalance(uint _redemptionNonce, address _token, uint _amount) external onlyFactory {
        redemptionTokenPrimaryBalance[_redemptionNonce][_token] = _amount;
    }

    function setIssuanceIndexTokenPrimaryTotalSupply(uint _issuanceNonce, uint _amount) external onlyFactory {
        issuanceIndexTokenPrimaryTotalSupply[_issuanceNonce] = _amount;
    }

    function setRedemptionIndexTokenPrimaryTotalSupply(uint _redemptionNonce, uint _amount) external onlyFactory {
        redemptionIndexTokenPrimaryTotalSupply[_redemptionNonce] = _amount;
    }

    function setIssuanceInputAmount(uint _issuanceNonce, uint _amount) external onlyFactory {
        issuanceInputAmount[_issuanceNonce] = _amount;
    }

    function setRedemptionInputAmount(uint _redemptionNonce, uint _amount) external onlyFactory {
        redemptionInputAmount[_redemptionNonce] = _amount;
    }

    function setActionInfoById(uint _requestId, ActionInfo memory _actionInfo) external onlyFactory {
        actionInfoById[_requestId] = _actionInfo;
    }

    function setCancelIssuanceUnfilledAmount(uint _issuanceNonce, address _token, uint _amount) external onlyFactory {
        cancelIssuanceUnfilledAmount[_issuanceNonce][_token] = _amount;
    }

    function setCancelRedemptionUnfilledAmount(uint _redemptionNonce, address _token, uint _amount) external onlyFactory {
        cancelRedemptionUnfilledAmount[_redemptionNonce][_token] = _amount;
    }

    function setCancelIssuanceComplted(uint _issuanceNonce, bool _isCompleted) external onlyFactory {
        cancelIssuanceComplted[_issuanceNonce] = _isCompleted;
    }

    function setCancelRedemptionComplted(uint _redemptionNonce, bool _isCompleted) external onlyFactory {
        cancelRedemptionComplted[_redemptionNonce] = _isCompleted;
    }

    function setOrderInstanceById(uint _requestId, IOrderProcessor.Order memory _order) external onlyFactory {
        orderInstanceById[_requestId] = _order;
    }

    function getOrderInstanceById(uint _id) public view returns(IOrderProcessor.Order memory){
        return orderInstanceById[_id];
    }

    function getActionInfoById(uint _id) public view returns(ActionInfo memory){
        return actionInfoById[_id];
    }

    function getVaultDshareBalance(address _token) public view returns(uint){
        address wrappedDshareAddress = wrappedDshareAddress[_token];
        uint wrappedDshareBalance = IERC20(wrappedDshareAddress).balanceOf(address(vault));
        return WrappedDShare(wrappedDshareAddress).previewRedeem(wrappedDshareBalance);
    }

    function getAmountAfterFee(uint24 percentageFeeRate, uint256 orderValue) internal pure returns (uint256) {
        return percentageFeeRate != 0 ? PrbMath.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate)) : 0;
    }
    
    function getVaultDshareValue(address _token) public view returns(uint){
        uint tokenPrice = priceInWei(_token);
        uint dshareBalance = getVaultDshareBalance(_token);
        return (dshareBalance * tokenPrice)/1e18;
    }
    

    function getPortfolioValue() public view returns(uint){
        uint portfolioValue;
        for(uint i; i < totalCurrentList; i++) {
            uint tokenValue = getVaultDshareValue(currentList[i]);
            portfolioValue += tokenValue;
        }
        return portfolioValue;
    }

    function _toWei(int256 _amount, uint8 _amountDecimals, uint8 _chainDecimals) private pure returns (int256) {        
        if (_chainDecimals > _amountDecimals){
            return _amount * int256(10 **(_chainDecimals - _amountDecimals));
        }else{
            return _amount * int256(10 **(_amountDecimals - _chainDecimals));
        }
    }

    function priceInWei(address _tokenAddress) public view returns (uint256) {
        
        if(isMainnet){
        address feedAddress = priceFeedByTokenAddress[_tokenAddress];
        (,int price,,,) = AggregatorV3Interface(feedAddress).latestRoundData();
        uint8 priceFeedDecimals = AggregatorV3Interface(feedAddress).decimals();
        price = _toWei(price, priceFeedDecimals, 18);
        return uint256(price);
        } else{
        IOrderProcessor.PricePoint memory tokenPriceData = issuer.latestFillPrice(_tokenAddress, address(usdc));
        int price = _toWei(int(tokenPriceData.price), latestPriceDecimals, 18);
        return uint(price);
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
    
    function getIssuanceAmountOut(uint _amount) public view returns(uint){
        uint portfolioValue = getPortfolioValue();
        uint totalSupply = token.totalSupply();
        uint amountOut = _amount * totalSupply / portfolioValue;
        return amountOut;
    }

    function getRedemptionAmountOut(uint _amount) public view returns(uint){
        uint portfolioValue = getPortfolioValue();
        uint totalSupply = token.totalSupply();
        uint amountOut = _amount * portfolioValue / totalSupply;
        return amountOut;
    }

    

    function calculateBuyRequestFee(uint _amount) public view returns(uint){
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint256 fee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, _amount);
        return fee;
    }

    function calculateIssuanceFee(uint _inputAmount) public view returns(uint256){
        uint256 fees;
        for(uint i; i < totalCurrentList; i++) {
        address tokenAddress = currentList[i];
        uint256 amount = _inputAmount * tokenCurrentMarketShare[tokenAddress] / 100e18;
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint256 fee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, amount);
        fees += fee;
        // fees += amount;
        }
        return fees;
    }



    function concatenation(string memory a, string memory b) public pure returns (string memory) {
        return string(bytes.concat(bytes(a), bytes(b)));
    }

    
    function requestAssetsData(
    )
        public
        returns(bytes32)
    {
        string memory url = concatenation(baseUrl, urlParams);
        Chainlink.Request memory req = buildChainlinkRequest(externalJobId, address(this), this.fulfillAssetsData.selector);
        req.add("get", url);
        req.add("path1", "results,addresses");
        req.add("path2", "results,marketShares");
        return sendChainlinkRequestTo(chainlinkOracleAddress(), req, oraclePayment);
    }

  function fulfillAssetsData(bytes32 requestId, address[] memory _tokens, uint256[] memory _marketShares)
    public
    recordChainlinkFulfillment(requestId)
  {
    _initData(_tokens, _marketShares);
  }


    function _initData(address[] memory _tokens, uint256[] memory _marketShares) private {
        address[] memory tokens0 = _tokens;
        uint[] memory marketShares0 = _marketShares;

        // //save mappings
        for(uint i =0; i < tokens0.length; i++){
            oracleList[i] = tokens0[i];
            tokenOracleListIndex[tokens0[i]] = i;
            tokenOracleMarketShare[tokens0[i]] = marketShares0[i];
            if(totalCurrentList == 0){
                currentList[i] = tokens0[i];
                tokenCurrentMarketShare[tokens0[i]] = marketShares0[i];
                tokenCurrentListIndex[tokens0[i]] = i;
            }
        }
        totalOracleList = tokens0.length;
        if(totalCurrentList == 0){
            totalCurrentList  = tokens0.length;
        }
        lastUpdateTime = block.timestamp;
    }

    function updateCurrentList() external {
        require(msg.sender == factoryBalancerAddress, "caller must be factory balancer");
        totalCurrentList = totalOracleList;
        for(uint i = 0; i < totalOracleList; i++){
            address tokenAddress = oracleList[i];
            currentList[i] = tokenAddress;
            tokenCurrentMarketShare[tokenAddress] = tokenOracleMarketShare[tokenAddress];
            tokenCurrentListIndex[tokenAddress] = i;
        }
    }

    function mockFillAssetsList(address[] memory _tokens, uint256[] memory _marketShares)
    public
    onlyOwner
    {
        _initData(_tokens, _marketShares);
    }
    
    function getTimestamp() internal view returns (uint256) {
        // timestamp is only used for data maintaining purpose, it is not relied on for critical logic.
        return block.timestamp; // solhint-disable-line not-rely-on-time
    }

    

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) ==
            keccak256(abi.encodePacked(b)));
    }

    function isEmptyString(string memory a) internal pure returns (bool) {
        return (compareStrings(a, ""));
    }


    function checkCancelIssuanceStatus(uint256 _issuanceNonce) public view returns(bool) {
        uint completedCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            uint receivedAmount = issuer.getReceivedAmount(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED) && receivedAmount == 0){
                completedCount += 1;
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) && receivedAmount == 0){
                uint cancelRequestId = cancelIssuanceRequestId[_issuanceNonce][tokenAddress];
                if(uint8(issuer.getOrderStatus(cancelRequestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)){
                    completedCount += 1;
                }
            }
        }
        if(completedCount == totalCurrentList){
            return true;
        }else{
            return false;
        }
    }

    function isIssuanceOrderActive(uint256 _issuanceNonce) public view returns(bool) {
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                return true;
            }
        }
        return false;
    }

    function checkIssuanceOrdersStatus(uint _issuanceNonce) public view returns(bool) {
        uint completedOrdersCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)){
                completedOrdersCount += 1;
            }
        }
        if(completedOrdersCount == totalCurrentList){
            return true;
        }else{
            return false;
        }
    }

    function checkRedemptionOrdersStatus(uint256 _redemptionNonce) public view returns(bool) {
        uint completedOrdersCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)){
                completedOrdersCount += 1;
            }
        }
        if(completedOrdersCount == totalCurrentList){
            return true;
        }else{
            return false;
        }
    }

    function isRedemptionOrderActive(uint256 _redemptionNonce) public view returns(bool) {
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                return true;
            }
        }
        return false;
    }

    function checkCancelRedemptionStatus(uint256 _redemptionNonce) public view returns(bool) {
        uint completedCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            uint receivedAmount = issuer.getReceivedAmount(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED) && receivedAmount == 0){
                completedCount += 1;
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) && receivedAmount == 0){
                uint cancelRequestId = cancelRedemptionRequestId[_redemptionNonce][tokenAddress];
                if(uint8(issuer.getOrderStatus(cancelRequestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)){
                    completedCount += 1;
                }
            }
        }
        if(completedCount == totalCurrentList){
            return true;
        }else{
            return false;
        }
    }
    
}
