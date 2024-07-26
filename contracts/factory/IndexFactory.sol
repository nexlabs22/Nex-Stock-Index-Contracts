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
import {FeeLib} from "../dinary/common/FeeLib.sol";
import "../coa/ContractOwnedAccount.sol";
import "../vault/NexVault.sol";
import "../dinary/WrappedDShare.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../libraries/Commen.sol" as PrbMath;

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactory is
    Initializable,
    ChainlinkClient,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using Chainlink for Chainlink.Request;

    string baseUrl;
    string urlParams;

    struct ActionInfo {
        uint actionType;
        uint nonce; 
    }

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

    mapping(uint => bool) public issuanceIsCompleted;
    mapping(uint => bool) public redemptionIsCompleted;

    mapping(uint => uint) public burnedTokenAmountByNonce;



    IndexToken public token;

    NexVault public vault;

    address public custodianWallet;
    IOrderProcessor public issuer;

    address public usdc;
    uint8 public usdcDecimals;

    uint8 public feeRate; // 10/10000 = 0.1%


    // mapping between a mint request hash and the corresponding request nonce.
    uint public issuanceNonce;

    // mapping between a burn request hash and the corresponding request nonce.
    uint public redemptionNonce;

    uint public rebalanceNonce;

    bool public isMainnet;

    mapping(uint => mapping(address => uint)) public cancelIssuanceRequestId;
    mapping(uint => mapping(address => uint)) public cancelRedemptionRequestId;

    mapping(uint => mapping(address => uint)) public issuanceRequestId;
    mapping(uint => mapping(address => uint)) public redemptionRequestId;

    mapping(uint => mapping(address => uint)) public rebalanceRequestId;

    mapping(uint => uint) public buyRequestPayedAmountById;
    mapping(uint => uint) public sellRequestAssetAmountById;

    mapping(uint => uint) public rebalanceBuyPayedAmountById;
    mapping(uint => uint) public rebalanceSellAssetAmountById;

    mapping(uint => mapping(address => uint)) public issuanceTokenPrimaryBalance;
    mapping(uint => mapping(address => uint)) public redemptionTokenPrimaryBalance;

    mapping(uint => uint) public issuanceIndexTokenPrimaryTotalSupply;
    mapping(uint => uint) public redemptionIndexTokenPrimaryTotalSupply;

    mapping(uint => address) public issuanceRequesterByNonce;
    mapping(uint => address) public redemptionRequesterByNonce;

    mapping(uint => address) public coaByIssuanceNonce;
    mapping(uint => address) public coaByRedemptionNonce;

    mapping(uint => bool) public cancelIssuanceComplted;
    mapping(uint => bool) public cancelRedemptionComplted;

    mapping(uint =>  IOrderProcessor.Order) public orderInstanceById;

    mapping(address => address) public priceFeedByTokenAddress;

    mapping(uint => uint) public portfolioValueByNonce;
    mapping(uint => mapping(address => uint)) public tokenValueByNonce;
    mapping(uint => mapping(address => uint)) public tokenShortagePercentByNonce;
    mapping(uint => uint) public totalShortagePercentByNonce;

    mapping(uint => uint) public issuanceInputAmount;
    mapping(uint => uint) public redemptionInputAmount;

    mapping(uint => ActionInfo) public actionInfoById; 
    // RequestNFT public nft;
    uint256 public latestFeeUpdate;

    event RequestIssuance(
        uint indexed nonce,
        address indexed user,
        address inputToken,
        uint inputAmount,
        uint outputAmount,
        uint time
    );

    event Issuanced(
        uint indexed nonce,
        address indexed user,
        address inputToken,
        uint inputAmount,
        uint outputAmount,
        uint time
    );

    event RequestRedemption(
        uint indexed nonce,
        address indexed user,
        address outputToken,
        uint inputAmount,
        uint outputAmount,
        uint time
    );

    event Redemption(
        uint indexed nonce,
        address indexed user,
        address outputToken,
        uint inputAmount,
        uint outputAmount,
        uint time
    );

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
        __Pausable_init();
        feeRate = 10;
        //set oracle data
        setChainlinkToken(_chainlinkToken);
        setChainlinkOracle(_oracleAddress);
        externalJobId = _externalJobId;
        oraclePayment = ((1 * LINK_DIVISIBILITY) / 10); // n * 10**18
        baseUrl = "https://app.nexlabs.io/api/allFundingRates";
        urlParams = "?multiplyFunc=18&timesNegFund=true&arrays=true";
        isMainnet = _isMainnet;
    }

    

//Notice: newFee should be between 1 to 100 (0.01% - 1%)
  function setFeeRate(uint8 _newFee) public onlyOwner {
    uint256 distance = block.timestamp - latestFeeUpdate;
    require(distance / 60 / 60 > 12, "You should wait at least 12 hours after the latest update");
    require(_newFee <= 100 && _newFee >= 1, "The newFee should be between 1 and 100 (0.01% - 1%)");
    feeRate = _newFee;
    latestFeeUpdate = block.timestamp;
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

    function setTokenAddress(
        address _token
    ) public onlyOwner returns (bool) {
        require(_token != address(0), "invalid token address");
        token = IndexToken(_token);
        return true;
    }

    function setCustodianWallet(address _custodianWallet) external onlyOwner returns (bool) {
        require(_custodianWallet != address(0), "invalid custodian wallet address");
        custodianWallet = _custodianWallet;
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


    function concatenation(string memory a, string memory b) public pure returns (string memory) {
        return string(bytes.concat(bytes(a), bytes(b)));
    }

    function setUrl(string memory _beforeAddress, string memory _afterAddress) public onlyOwner{
    baseUrl = _beforeAddress;
    urlParams = _afterAddress;
    }

    function setOracleInfo(address _oracleAddress, bytes32 _externalJobId) public onlyOwner {
        setChainlinkOracle(_oracleAddress);
        externalJobId = _externalJobId;
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

    function _updateCurrentList() internal {
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
    function getOrderInstanceById(uint256 id) external view returns(IOrderProcessor.Order memory){
        return orderInstanceById[id];
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
        return tokenPriceData.price;
        }
    }
    
    function getPrimaryOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
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
        }
        return fees;
    }

    function requestBuyOrder(address _token, uint256 _orderAmount, address _receiver) internal returns(uint) {
       
        // (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        // uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, _orderAmount);
        
        IOrderProcessor.Order memory order = getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;
        // uint256 quantityIn = order.paymentTokenQuantity + fees;
        
        /**
        IERC20(usdc).transferFrom(msg.sender, address(this), quantityIn);
        IERC20(usdc).approve(address(issuer), quantityIn);
        */
        uint256 id = issuer.createOrderStandardFees(order);
        orderInstanceById[id] = order;
        return id;
        // return 1;
    }

    


    function requestSellOrder(address _token, uint256 _amount, address _receiver) internal returns(uint) {
        address wrappedDshare = wrappedDshareAddress[_token];
        vault.withdrawFunds(wrappedDshare, address(this), _amount);
        uint orderAmount = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        IOrderProcessor.Order memory order = getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;
        /**
        IERC20(token).transferFrom(msg.sender, address(this), _orderAmount);
        IERC20(token).approve(address(issuer), _orderAmount);
        */
        
        IERC20(_token).approve(address(issuer), orderAmount);
        // balances before
        uint256 id = issuer.createOrderStandardFees(order);
        orderInstanceById[id] = order;
        return id;
    }
    


    function issuance(uint _inputAmount) public returns(uint256) {
        
        uint256 orderProcessorFee = calculateIssuanceFee(_inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        IERC20(usdc).transferFrom(msg.sender, address(this), quantityIn);
        IERC20(usdc).approve(address(issuer), quantityIn);
        
        
        issuanceNonce += 1;
        ContractOwnedAccount coa = new ContractOwnedAccount(address(this));
        coaByIssuanceNonce[issuanceNonce] = address(coa);
        issuanceInputAmount[issuanceNonce] = _inputAmount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint256 amount = _inputAmount * tokenCurrentMarketShare[tokenAddress] / 100e18;
            uint requestId = requestBuyOrder(tokenAddress, amount, address(coa));
            actionInfoById[requestId] = ActionInfo(1, issuanceNonce);
            buyRequestPayedAmountById[requestId] = amount;
            issuanceRequestId[issuanceNonce][tokenAddress] = requestId;
            issuanceRequesterByNonce[issuanceNonce] = msg.sender;
            uint wrappedDsharesBalance = IERC20(wrappedDshareAddress[tokenAddress]).balanceOf(address(vault));
            uint dShareBalance = WrappedDShare(wrappedDshareAddress[tokenAddress]).previewRedeem(wrappedDsharesBalance);
            issuanceTokenPrimaryBalance[issuanceNonce][tokenAddress] = dShareBalance;
            issuanceIndexTokenPrimaryTotalSupply[issuanceNonce] = IERC20(token).totalSupply();
        }
        emit RequestIssuance(issuanceNonce, msg.sender, usdc, _inputAmount, 0, block.timestamp);
        return issuanceNonce;
    }

    function completeIssuance(uint _issuanceNonce) public {
        require(checkIssuanceOrdersStatus(_issuanceNonce), "Orders are not completed");
        require(!issuanceIsCompleted[_issuanceNonce], "Issuance is completed");
        address requester = issuanceRequesterByNonce[_issuanceNonce];
        uint primaryPortfolioValue;
        uint secondaryPortfolioValue;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint256 tokenRequestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            IOrderProcessor.PricePoint memory tokenPriceData = issuer.latestFillPrice(tokenAddress, address(usdc));
            address coaAddress = coaByIssuanceNonce[_issuanceNonce];
            uint256 balance = IERC20(tokenAddress).balanceOf(coaAddress);
            uint256 primaryBalance = issuanceTokenPrimaryBalance[_issuanceNonce][tokenAddress];
            uint256 primaryValue = primaryBalance*tokenPriceData.price;
            uint256 secondaryValue = primaryValue + buyRequestPayedAmountById[tokenRequestId];
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;
            ContractOwnedAccount(coaAddress).sendToken(tokenAddress, address(this), balance);
            IERC20(tokenAddress).approve(wrappedDshareAddress[tokenAddress], balance);
            WrappedDShare(wrappedDshareAddress[tokenAddress]).deposit(balance, address(vault));
        }
            uint256 primaryTotalSupply = issuanceIndexTokenPrimaryTotalSupply[_issuanceNonce];
            if(primaryTotalSupply == 0){
                uint256 mintAmount = secondaryPortfolioValue*100;
                token.mint(requester, mintAmount);
                emit Issuanced(_issuanceNonce, requester, usdc, issuanceInputAmount[_issuanceNonce], mintAmount, block.timestamp);
            }else{
                uint256 secondaryTotalSupply = primaryTotalSupply * secondaryPortfolioValue / primaryPortfolioValue;
                uint256 mintAmount = secondaryTotalSupply - primaryTotalSupply;
                token.mint(requester, mintAmount);
                emit Issuanced(_issuanceNonce, requester, usdc, issuanceInputAmount[_issuanceNonce], mintAmount, block.timestamp);
            }
            issuanceIsCompleted[issuanceNonce] = true;
    }

    function cancelIssuance(uint256 _issuanceNonce) public {
        require(!issuanceIsCompleted[_issuanceNonce], "Issuance is completed");
        address requester = issuanceRequesterByNonce[_issuanceNonce];
        address coaAddress = coaByIssuanceNonce[_issuanceNonce];
        require(msg.sender == requester, "Only requester can cancel the issuance");
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            IOrderProcessor.Order memory order = orderInstanceById[requestId];
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                issuer.requestCancel(requestId);
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || IERC20(tokenAddress).balanceOf(coaAddress) > 0){
                uint256 balance = IERC20(tokenAddress).balanceOf(coaAddress);
                ContractOwnedAccount(coaAddress).sendToken(tokenAddress, address(this), balance);
                uint cancelRequestId = requestSellOrder(tokenAddress, balance, address(coaAddress));
                actionInfoById[cancelRequestId] = ActionInfo(3, _issuanceNonce);

                cancelIssuanceRequestId[_issuanceNonce][tokenAddress] = cancelRequestId;
            }
        }
    }

    function completeCancelIssuance(uint256 _issuanceNonce) public {
        require(checkCancelIssuanceStatus(_issuanceNonce), "Cancel issuance is not completed");
        require(!cancelIssuanceComplted[_issuanceNonce], "The process has been completed before");
        address requester = issuanceRequesterByNonce[_issuanceNonce];
        address coaAddress = coaByIssuanceNonce[_issuanceNonce];
        uint256 balance = IERC20(usdc).balanceOf(coaAddress);
        ContractOwnedAccount(coaAddress).sendToken(usdc, requester, balance);
        cancelIssuanceComplted[_issuanceNonce] = true;
    }

    function checkCancelIssuanceStatus(uint256 _issuanceNonce) public view returns(bool) {
        uint completedCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            address coaAddress = coaByIssuanceNonce[_issuanceNonce];
            uint coaBalance = IERC20(tokenAddress).balanceOf(coaAddress);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED) && coaBalance == 0){
                completedCount += 1;
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) && coaBalance == 0){
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


    function redemption(uint _inputAmount) public returns(uint) {
        redemptionNonce += 1;
        ContractOwnedAccount coa = new ContractOwnedAccount(address(this));
        coaByRedemptionNonce[redemptionNonce] = address(coa);
        redemptionInputAmount[redemptionNonce] = _inputAmount;
        uint tokenBurnPercent = _inputAmount*1e18/token.totalSupply(); 
        token.burn(msg.sender, _inputAmount);
        burnedTokenAmountByNonce[redemptionNonce] = _inputAmount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint256 amount = tokenBurnPercent * IERC20(wrappedDshareAddress[tokenAddress]).balanceOf(address(vault)) / 1e18;
            uint requestId = requestSellOrder(tokenAddress, amount, address(coa));
            actionInfoById[requestId] = ActionInfo(2, redemptionNonce);
            sellRequestAssetAmountById[requestId] = amount;
            redemptionRequestId[redemptionNonce][tokenAddress] = requestId;
            redemptionRequesterByNonce[redemptionNonce] = msg.sender;
            uint wrappedDsharesBalance = IERC20(wrappedDshareAddress[tokenAddress]).balanceOf(address(vault));
            uint dShareBalance = WrappedDShare(wrappedDshareAddress[tokenAddress]).previewRedeem(wrappedDsharesBalance);
            redemptionTokenPrimaryBalance[redemptionNonce][tokenAddress] = dShareBalance;
            redemptionIndexTokenPrimaryTotalSupply[redemptionNonce] = IERC20(token).totalSupply();
        }
        emit RequestRedemption(redemptionNonce, msg.sender, usdc, _inputAmount, 0, block.timestamp);
        return redemptionNonce;
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

    function completeRedemption(uint _redemptionNonce) public {
        require(checkRedemptionOrdersStatus(_redemptionNonce), "Redemption orders are not completed");
        require(!redemptionIsCompleted[_redemptionNonce], "Redemption is completed");
        address requester = redemptionRequesterByNonce[_redemptionNonce];
        address coaAddress = coaByRedemptionNonce[_redemptionNonce];
        uint256 balance = IERC20(usdc).balanceOf(coaAddress);
        ContractOwnedAccount(address(coaAddress)).sendToken(usdc, requester, balance);
        redemptionIsCompleted[_redemptionNonce] = true;
        emit Redemption(_redemptionNonce, requester, usdc, redemptionInputAmount[_redemptionNonce], balance, block.timestamp);
    }

    function cancelRedemption(uint _redemptionNonce) public {
        require(!redemptionIsCompleted[_redemptionNonce], "Redemption is completed");
        address requester = redemptionRequesterByNonce[_redemptionNonce];
        address coaAddress = coaByRedemptionNonce[_redemptionNonce];
        require(msg.sender == requester, "Only requester can cancel the redemption");
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            IOrderProcessor.Order memory order = orderInstanceById[requestId];
            uint filledAmount = issuer.getReceivedAmount(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || filledAmount > 0){
                ContractOwnedAccount(coaAddress).sendToken(address(usdc), address(this), filledAmount);
                uint cancelRequestId = requestBuyOrder(tokenAddress, filledAmount, address(coaAddress));
                actionInfoById[cancelRequestId] = ActionInfo(4, _redemptionNonce);
                cancelRedemptionRequestId[_redemptionNonce][tokenAddress] = requestId;
            }
        }
    }

    function completeCancelRedemption(uint256 _redemptionNonce) public {
        require(checkCancelRedemptionStatus(_redemptionNonce), "Cancel redemption is not completed");
        require(!cancelRedemptionComplted[_redemptionNonce], "The process has been completed before");

        address requester = redemptionRequesterByNonce[_redemptionNonce];
        address coaAddress = coaByRedemptionNonce[_redemptionNonce];
        uint256 balance = IERC20(usdc).balanceOf(coaAddress);
        for(uint i; i < totalCurrentList; i++){
            address tokenAddress = currentList[i];
            uint tokenBalance = IERC20(tokenAddress).balanceOf(coaAddress);
            if(tokenBalance > 0){
                ContractOwnedAccount(coaAddress).sendToken(tokenAddress, address(vault), tokenBalance);
            }
        }
        token.mint(requester, burnedTokenAmountByNonce[_redemptionNonce]);
        cancelRedemptionComplted[_redemptionNonce] = true;
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
            address coaAddress = coaByRedemptionNonce[_redemptionNonce];
            uint coaBalance = IERC20(tokenAddress).balanceOf(coaAddress);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED) && coaBalance == 0){
                completedCount += 1;
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) && coaBalance == 0){
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

    function firstRebalanceAction() public onlyOwner returns(uint) {
        rebalanceNonce += 1;
        uint portfolioValue;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            // uint tokenPrice = priceInWei(tokenAddress);
            // uint tokenBalance = IERC20(tokenAddress).balanceOf(address(vault));
            // uint tokenValue = tokenBalance * tokenPrice;
            uint tokenValue = getVaultDshareValue(tokenAddress);
            tokenValueByNonce[rebalanceNonce][tokenAddress] = tokenValue;
            portfolioValue += tokenValue;
        }
        portfolioValueByNonce[rebalanceNonce] = portfolioValue;
        for(uint i; i< totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint tokenValue = tokenValueByNonce[rebalanceNonce][tokenAddress];
            uint tokenBalance = getVaultDshareBalance(tokenAddress);
            uint tokenValuePercent = (tokenValue * 100e18) / portfolioValue;
            if(tokenValuePercent > tokenOracleMarketShare[tokenAddress]){
            uint amount = tokenBalance - (tokenBalance * tokenOracleMarketShare[tokenAddress] / tokenValuePercent);
            uint requestId = requestSellOrder(tokenAddress, amount, address(this));
            actionInfoById[requestId] = ActionInfo(5, rebalanceNonce);
            rebalanceRequestId[rebalanceNonce][tokenAddress] = requestId;
            rebalanceSellAssetAmountById[requestId] = amount;
            }else{
            uint shortagePercent = tokenOracleMarketShare[tokenAddress] - tokenValuePercent;
            tokenShortagePercentByNonce[rebalanceNonce][tokenAddress] = shortagePercent;
            totalShortagePercentByNonce[rebalanceNonce] += shortagePercent;
            }
        }

        return rebalanceNonce;
    }

    function secondRebalanceAction(uint _rebalanceNonce) public onlyOwner {
        require(checkFirstRebalanceOrdersStatus(rebalanceNonce), "Rebalance orders are not completed");
        uint portfolioValue = portfolioValueByNonce[_rebalanceNonce];
        uint totalShortagePercent = totalShortagePercentByNonce[_rebalanceNonce];
        uint usdcBalance = IERC20(usdc).balanceOf(address(this));
        for(uint i; i< totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint tokenShortagePercent = tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress];
            if(tokenShortagePercent > 0){
            uint paymentAmount = (tokenShortagePercent * usdcBalance) / totalShortagePercent;
            (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
            uint amountAfterFee = getAmountAfterFee(percentageFeeRate, paymentAmount) - flatFee;
            uint256 esFee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, amountAfterFee);
            IERC20(usdc).approve(address(issuer), paymentAmount);
            uint requestId = requestBuyOrder(tokenAddress, amountAfterFee, address(this));
            actionInfoById[requestId] = ActionInfo(6, _rebalanceNonce);
            rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
            rebalanceBuyPayedAmountById[requestId] = amountAfterFee;
            }
        }
    }

    function estimateAmountAfterFee(uint _amount) public view returns(uint256){
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint amountAfterFee = getAmountAfterFee(percentageFeeRate, _amount) - flatFee;
        return amountAfterFee;
    }

    function completeRebalanceActions(uint _rebalanceNonce) public onlyOwner {
        require(checkSecondRebalanceOrdersStatus(_rebalanceNonce), "Rebalance orders are not completed");
        for(uint i; i< totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
            if(tokenBalance > 0){
            IERC20(tokenAddress).approve(wrappedDshareAddress[tokenAddress], tokenBalance);
            WrappedDShare(wrappedDshareAddress[tokenAddress]).deposit(tokenBalance, address(vault));
            }
        }
        _updateCurrentList();
    }


    function checkFirstRebalanceOrdersStatus(uint256 _rebalanceNonce) public view returns(bool) {
        uint completedOrdersCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint assetAmount = rebalanceSellAssetAmountById[requestId];
            if(requestId > 0 && assetAmount > 0 && uint8(issuer.getOrderStatus(requestId)) != uint8(IOrderProcessor.OrderStatus.FULFILLED)){
                return false;
            }
        }
        return true;
    }

    function checkSecondRebalanceOrdersStatus(uint256 _rebalanceNonce) public view returns(bool) {
        uint completedOrdersCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint payedAmount = rebalanceBuyPayedAmountById[requestId];
            if(requestId > 0 && payedAmount > 0 && uint8(issuer.getOrderStatus(requestId)) != uint8(IOrderProcessor.OrderStatus.FULFILLED)){
                return false;
            }
        }
        return true;
    }


    function checkMultical(uint _reqeustId) public view returns (bool){
        ActionInfo memory actionInfo = actionInfoById[_reqeustId];
        if(actionInfo.actionType == 1){
            return checkIssuanceOrdersStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 2){
            return checkRedemptionOrdersStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 3){
            return checkCancelIssuanceStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 4){
            return checkCancelRedemptionStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 5){
            return checkFirstRebalanceOrdersStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 6){
            return checkSecondRebalanceOrdersStatus(actionInfo.nonce);
        }
        return false;
    }

    function multical(uint _requestId) public {
        ActionInfo memory actionInfo = actionInfoById[_requestId];
        if(actionInfo.actionType == 1){
            completeIssuance(actionInfo.nonce);
        }else if(actionInfo.actionType == 2){
            completeRedemption(actionInfo.nonce);
        }else if(actionInfo.actionType == 3){
            completeCancelIssuance(actionInfo.nonce);
        }else if(actionInfo.actionType == 4){
            completeCancelRedemption(actionInfo.nonce);
        }else if(actionInfo.actionType == 5){
            secondRebalanceAction(actionInfo.nonce);
        }else if(actionInfo.actionType == 6){
            completeRebalanceActions(actionInfo.nonce);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
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

    
}
