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
import "./IndexFactory.sol";
import "./IndexFactoryBalancer.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryStorage is
    Initializable,
    ChainlinkClient,
    OwnableUpgradeable
{
    using Chainlink for Chainlink.Request;

    string public baseUrl;
    string public urlParams;

    IndexFactory public factory;
    IndexFactoryBalancer public factoryBalancer;

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
    

    function initialize(
        address _issuer,
        address _token,
        address _vault,
        address _usdc,
        uint8 _usdcDecimals,
        address _chainlinkToken,
        address _oracleAddress,
        bytes32 _externalJobId
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

    function setFactory(address _factoryAddress) public onlyOwner {
        factory = IndexFactory(_factoryAddress);
    }

    function setFactoryBalancer(address _factoryBalancerAddress) public onlyOwner {
        factoryBalancer = IndexFactoryBalancer(_factoryBalancerAddress);
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
        require(msg.sender == address(factoryBalancer), "caller must be factory balancer");
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
            uint requestId = factory.issuanceRequestId(_issuanceNonce, tokenAddress);
            address coaAddress = factory.coaByIssuanceNonce(_issuanceNonce);
            uint coaBalance = IERC20(tokenAddress).balanceOf(coaAddress);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED) && coaBalance == 0){
                completedCount += 1;
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) && coaBalance == 0){
                uint cancelRequestId = factory.cancelIssuanceRequestId(_issuanceNonce,tokenAddress);
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
            uint requestId = factory.issuanceRequestId(_issuanceNonce, tokenAddress);
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
            uint requestId = factory.issuanceRequestId(_issuanceNonce, tokenAddress);
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
            uint requestId = factory.redemptionRequestId(_redemptionNonce,tokenAddress);
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
            uint requestId = factory.redemptionRequestId(_redemptionNonce, tokenAddress);
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
            uint requestId = factory.redemptionRequestId(_redemptionNonce,tokenAddress);
            address coaAddress = factory.coaByRedemptionNonce(_redemptionNonce);
            uint coaBalance = IERC20(tokenAddress).balanceOf(coaAddress);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.CANCELLED) && coaBalance == 0){
                completedCount += 1;
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) && coaBalance == 0){
                uint cancelRequestId = factory.cancelRedemptionRequestId(_redemptionNonce, tokenAddress);
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
