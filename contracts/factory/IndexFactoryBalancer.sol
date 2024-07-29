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
    PausableUpgradeable
{
    
    struct ActionInfo {
        uint actionType;
        uint nonce; 
    }

    

    

    IndexToken public token;

    IndexFactoryStorage public factoryStorage;

    NexVault public vault;

    IOrderProcessor public issuer;
    OrderManager public orderManager;

    address public usdc;
    uint8 public usdcDecimals;

    uint8 public feeRate; // 10/10000 = 0.1%


   
    uint public rebalanceNonce;

    bool public isMainnet;

    

    mapping(uint => mapping(address => uint)) public rebalanceRequestId;

    mapping(uint => uint) public buyRequestPayedAmountById;
    mapping(uint => uint) public sellRequestAssetAmountById;

    mapping(uint => uint) public rebalanceBuyPayedAmountById;
    mapping(uint => uint) public rebalanceSellAssetAmountById;

    

    mapping(uint =>  IOrderProcessor.Order) public orderInstanceById;


    mapping(uint => uint) public portfolioValueByNonce;
    mapping(uint => mapping(address => uint)) public tokenValueByNonce;
    mapping(uint => mapping(address => uint)) public tokenShortagePercentByNonce;
    mapping(uint => uint) public totalShortagePercentByNonce;


    mapping(uint => ActionInfo) public actionInfoById; 
    // RequestNFT public nft;
    uint256 public latestFeeUpdate;

    

    function initialize(
        address _factoryStorage,
        address _orderManager,
        address _issuer,
        address _token,
        address _vault,
        address _usdc,
        uint8 _usdcDecimals,
        bool _isMainnet
    ) external initializer {
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        orderManager = OrderManager(_orderManager);
        issuer = IOrderProcessor(_issuer);
        token = IndexToken(_token);
        vault = NexVault(_vault);
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        __Ownable_init(msg.sender);
        __Pausable_init();
        feeRate = 10;
        //set oracle data
        isMainnet = _isMainnet;
    }

    
    function setOrderManager(address _orderManager) public onlyOwner returns (bool) {
        orderManager = OrderManager(_orderManager);
        return true;
    }

    function setIndexFactoryStorage(address _indexFactoryStorage) public onlyOwner returns (bool) {
        factoryStorage = IndexFactoryStorage(_indexFactoryStorage);
        return true;
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

    

    /// @notice Allows the owner of the contract to set the issuer
    /// @param _issuer address
    /// @return bool
    function setIssuer(address _issuer) external onlyOwner returns (bool) {
        require(_issuer != address(0), "invalid issuer address");
        issuer = IOrderProcessor(_issuer);

        return true;
    }


    

    function getOrderInstanceById(uint256 id) external view returns(IOrderProcessor.Order memory){
        return orderInstanceById[id];
    }

    function getVaultDshareBalance(address _token) public view returns(uint){
        address wrappedDshareAddress = factoryStorage.wrappedDshareAddress(_token);
        uint wrappedDshareBalance = IERC20(wrappedDshareAddress).balanceOf(address(vault));
        return WrappedDShare(wrappedDshareAddress).previewRedeem(wrappedDshareBalance);
    }

    function getAmountAfterFee(uint24 percentageFeeRate, uint256 orderValue) internal pure returns (uint256) {
        return percentageFeeRate != 0 ? PrbMath2.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate)) : 0;
    }
    
    function getVaultDshareValue(address _token) public view returns(uint){
        uint tokenPrice = priceInWei(_token);
        uint dshareBalance = getVaultDshareBalance(_token);
        return (dshareBalance * tokenPrice)/1e18;
    }

    function getPortfolioValue() public view returns(uint){
        uint portfolioValue;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            uint tokenValue = getVaultDshareValue(factoryStorage.currentList(i));
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
        address feedAddress = factoryStorage.priceFeedByTokenAddress(_tokenAddress);
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
    
    

    function requestBuyOrder(address _token, uint256 _orderAmount, address _receiver) internal returns(uint) {
       
        
        IOrderProcessor.Order memory order = getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;
       
        /**
        IERC20(usdc).transferFrom(msg.sender, address(this), quantityIn);
        IERC20(usdc).approve(address(issuer), quantityIn);
        */
        // uint256 id = issuer.createOrderStandardFees(order);
        uint256 id = orderManager.requestBuyOrder(_token, _orderAmount, _receiver);
        orderInstanceById[id] = order;
        return id;
    }

    


    function requestSellOrder(address _token, uint256 _amount, address _receiver) internal returns(uint) {
        address wrappedDshare = factoryStorage.wrappedDshareAddress(_token);
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
        
        IERC20(_token).approve(address(orderManager), orderAmount);
        // balances before
        // uint256 id = issuer.createOrderStandardFees(order);
        uint256 id = orderManager.requestSellOrder(_token, orderAmount, _receiver);
        orderInstanceById[id] = order;
        return id;
    }
    


    

    function firstRebalanceAction() public onlyOwner returns(uint) {
        rebalanceNonce += 1;
        uint portfolioValue;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenValue = getVaultDshareValue(tokenAddress);
            tokenValueByNonce[rebalanceNonce][tokenAddress] = tokenValue;
            portfolioValue += tokenValue;
        }
        portfolioValueByNonce[rebalanceNonce] = portfolioValue;
        for(uint i; i< factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenValue = tokenValueByNonce[rebalanceNonce][tokenAddress];
            uint tokenBalance = getVaultDshareBalance(tokenAddress);
            uint tokenValuePercent = (tokenValue * 100e18) / portfolioValue;
            if(tokenValuePercent > factoryStorage.tokenOracleMarketShare(tokenAddress)){
            uint amount = tokenBalance - (tokenBalance * factoryStorage.tokenOracleMarketShare(tokenAddress) / tokenValuePercent);
            uint requestId = requestSellOrder(tokenAddress, amount, address(this));
            actionInfoById[requestId] = ActionInfo(5, rebalanceNonce);
            rebalanceRequestId[rebalanceNonce][tokenAddress] = requestId;
            rebalanceSellAssetAmountById[requestId] = amount;
            }else{
            uint shortagePercent = factoryStorage.tokenOracleMarketShare(tokenAddress) - tokenValuePercent;
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
        for(uint i; i< factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenShortagePercent = tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress];
            if(tokenShortagePercent > 0){
            uint paymentAmount = (tokenShortagePercent * usdcBalance) / totalShortagePercent;
            (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
            uint amountAfterFee = getAmountAfterFee(percentageFeeRate, paymentAmount) - flatFee;
            uint256 esFee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, amountAfterFee);
            IERC20(usdc).approve(address(orderManager), paymentAmount);
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
        for(uint i; i< factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
            if(tokenBalance > 0){
            IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), tokenBalance);
            WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(tokenBalance, address(vault));
            }
        }
        factoryStorage.updateCurrentList();
    }


    function checkFirstRebalanceOrdersStatus(uint256 _rebalanceNonce) public view returns(bool) {
        uint completedOrdersCount;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
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
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
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
        if(actionInfo.actionType == 5){
            return checkFirstRebalanceOrdersStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 6){
            return checkSecondRebalanceOrdersStatus(actionInfo.nonce);
        }
        return false;
    }

    function multical(uint _requestId) public {
        ActionInfo memory actionInfo = actionInfoById[_requestId];
        if(actionInfo.actionType == 5){
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
