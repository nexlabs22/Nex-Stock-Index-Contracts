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

    

    bytes32 public externalJobId;
    uint256 public oraclePayment;
    uint public lastUpdateTime;

    uint public totalOracleList;
    uint public totalCurrentList;

    mapping(uint => address) public oracleList;
    mapping(uint => address) public currentList;

    mapping(address => uint) public tokenOracleListIndex;
    mapping(address => uint) public tokenCurrentListIndex;

    mapping(address => uint) public tokenCurrentMarketShare;
    mapping(address => uint) public tokenOracleMarketShare;


    IndexToken public token;

    address public custodianWallet;
    IOrderProcessor public issuer;

    address public usdc;
    uint8 public usdcDecimals;

    uint8 public feeRate; // 10/10000 = 0.1%


    // mapping between a mint request hash and the corresponding request nonce.
    uint public issuanceNonce;

    // mapping between a burn request hash and the corresponding request nonce.
    uint public redemptionNonce;

    mapping(uint => mapping(address => uint)) public issuanceRequestId;
    mapping(uint => mapping(address => uint)) public redemptionRequestId;

    mapping(uint => uint) public buyRequestPayedAmountById;
    mapping(uint => uint) public sellRequestAssetAmountById;

    mapping(uint => mapping(address => uint)) public issuanceTokenPrimaryBalance;
    mapping(uint => mapping(address => uint)) public redemptionTokenPrimaryBalance;

    mapping(uint => uint) public issuanceIndexTokenPrimaryTotalSupply;

    mapping(uint => address) public issuanceRequesterByNonce;
    mapping(uint => address) public redemptionRequesterByNonce;

    // RequestNFT public nft;
    uint256 public latestFeeUpdate;


    function initialize(
        address _issuer,
        address _token,
        address _usdc,
        uint8 _usdcDecimals,
        address _chainlinkToken,
        address _oracleAddress,
        bytes32 _externalJobId
    ) external initializer {
        issuer = IOrderProcessor(_issuer);
        token = IndexToken(_token);
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        // nft = RequestNFT(_nft);
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


    function mockFillAssetsList(address[] memory _tokens, uint256[] memory _marketShares)
    public
    onlyOwner
    {
        _initData(_tokens, _marketShares);
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
    
    function requestBuyOrder(address _token, uint256 orderAmount) internal returns(uint) {
       
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        
        IOrderProcessor.Order memory order = getPrimaryOrder(false);
        order.recipient = address(this);
        order.assetToken = address(_token);
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        IERC20(usdc).transferFrom(msg.sender, address(this), quantityIn);
       
        IERC20(usdc).approve(address(issuer), quantityIn);
        uint256 id = issuer.createOrderStandardFees(order);
        return id;
    }

    


    function requestSellOrder(address _token, uint256 _orderAmount) internal returns(uint) {
        
        IOrderProcessor.Order memory order = getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = _orderAmount;

       IERC20(token).transferFrom(msg.sender, address(this), _orderAmount);

       IERC20(token).approve(address(issuer), _orderAmount);

        // balances before
        uint256 id = issuer.createOrderStandardFees(order);
        return id;
    }
    

    function issuance(uint _inputAmount) public {
        issuanceNonce += 1;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint256 amount = _inputAmount * tokenCurrentMarketShare[tokenAddress] / 100;
            uint requestId = requestBuyOrder(tokenAddress, amount);
            buyRequestPayedAmountById[requestId] = amount;
            issuanceRequestId[issuanceNonce][tokenAddress] = requestId;
            issuanceRequesterByNonce[issuanceNonce] = msg.sender;
            issuanceTokenPrimaryBalance[issuanceNonce][tokenAddress] = IERC20(tokenAddress).balanceOf(address(this));
            issuanceIndexTokenPrimaryTotalSupply[issuanceNonce] = IERC20(token).totalSupply();
        }

    }

    function completeIssuance(uint issuanceNonce) public {
        require(checkIssuance(issuanceNonce), "Issuance not completed");
        address reqeuster = issuanceRequesterByNonce[issuanceNonce];
        uint primaryPortfolioValue;
        uint secondaryPortfolioValue;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint256 tokenRequestId = issuanceRequestId[issuanceNonce][tokenAddress];
            IOrderProcessor.PricePoint memory tokenPriceData = issuer.latestFillPrice(tokenAddress, address(usdc));
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            uint256 primaryBalance = issuanceTokenPrimaryBalance[issuanceNonce][tokenAddress];
            uint256 primaryValue = primaryBalance*tokenPriceData.price;
            uint256 secondaryValue = primaryValue + buyRequestPayedAmountById[tokenRequestId];
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;
        }
            uint256 primaryTotalSupply = issuanceIndexTokenPrimaryTotalSupply[issuanceNonce];
            uint256 secondaryTotalSupply = primaryTotalSupply * secondaryPortfolioValue / primaryPortfolioValue;
            uint256 mintAmount = secondaryTotalSupply - primaryTotalSupply;
            token.mint(reqeuster, mintAmount);
    }

    function checkIssuance(uint _issuanceNonce) public view returns(bool) {
        uint completedOrdersCount;
        for(uint i; i < totalCurrentList; i++) {
            address tokenAddress = currentList[i];
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED)){
                completedOrdersCount += 1;
            }
        }
        if(completedOrdersCount == totalCurrentList){
            return true;
        }else{
            return false;
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
