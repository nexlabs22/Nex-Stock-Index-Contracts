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
import "./IndexFactoryStorage.sol";
import "./OrderManager.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactory is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    
    struct ActionInfo {
        uint actionType;
        uint nonce; 
    }

    

    mapping(uint => bool) public issuanceIsCompleted;
    mapping(uint => bool) public redemptionIsCompleted;

    mapping(uint => uint) public burnedTokenAmountByNonce;



    IndexToken public token;

    IndexFactoryStorage public factoryStorage;

    NexVault public vault;
    OrderManager public orderManager;
    IOrderProcessor public issuer;

    address public usdc;
    uint8 public usdcDecimals;

    uint8 public feeRate; // 10/10000 = 0.1%


    // mapping between a mint request hash and the corresponding request nonce.
    uint public issuanceNonce;

    // mapping between a burn request hash and the corresponding request nonce.
    uint public redemptionNonce;


    bool public isMainnet;

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

    mapping(uint => address) public coaByIssuanceNonce;
    mapping(uint => address) public coaByRedemptionNonce;

    mapping(uint => bool) public cancelIssuanceComplted;
    mapping(uint => bool) public cancelRedemptionComplted;

    mapping(uint =>  IOrderProcessor.Order) public orderInstanceById;


    mapping(uint => uint) public portfolioValueByNonce;
    mapping(uint => mapping(address => uint)) public tokenValueByNonce;
    mapping(uint => mapping(address => uint)) public tokenShortagePercentByNonce;
    mapping(uint => uint) public totalShortagePercentByNonce;

    mapping(uint => uint) public issuanceInputAmount;
    mapping(uint => uint) public redemptionInputAmount;

    mapping(uint => ActionInfo) public actionInfoById; 
    // RequestNFT public nft;
    uint256 public latestFeeUpdate;

    mapping(uint => mapping(address => uint)) public cancelIssuanceUnfilledAmount;
    mapping(uint => mapping(address => uint)) public cancelRedemptionUnfilledAmount;

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

    

//Notice: newFee should be between 1 to 100 (0.01% - 1%)
  function setFeeRate(uint8 _newFee) public onlyOwner {
    uint256 distance = block.timestamp - latestFeeUpdate;
    require(distance / 60 / 60 > 12, "You should wait at least 12 hours after the latest update");
    require(_newFee <= 10000 && _newFee >= 1, "The newFee should be between 1 and 100 (0.01% - 1%)");
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

    

    /// @notice Allows the owner of the contract to set the issuer
    /// @param _issuer address
    /// @return bool
    function setIssuer(address _issuer) external onlyOwner returns (bool) {
        require(_issuer != address(0), "invalid issuer address");
        issuer = IOrderProcessor(_issuer);

        return true;
    }


    function setIndexFactoryStorage(address _factoryStorage) external onlyOwner returns (bool) {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        return true;
    }
    

    // function getOrderInstanceById(uint256 id) external view returns(IOrderProcessor.Order memory){
    //     return orderInstanceById[id];
    // }

    function getVaultDshareBalance(address _token) public view returns(uint){
        address wrappedDshareAddress = factoryStorage.wrappedDshareAddress(_token);
        uint wrappedDshareBalance = IERC20(wrappedDshareAddress).balanceOf(address(vault));
        return WrappedDShare(wrappedDshareAddress).previewRedeem(wrappedDshareBalance);
    }

    // function getAmountAfterFee(uint24 percentageFeeRate, uint256 orderValue) internal pure returns (uint256) {
    //     return percentageFeeRate != 0 ? PrbMath.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate)) : 0;
    // }
    
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
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
        address tokenAddress = factoryStorage.currentList(i);
        uint256 amount = _inputAmount * factoryStorage.tokenCurrentMarketShare(tokenAddress) / 100e18;
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint256 fee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, amount);
        fees += fee;
        // fees += amount;
        }
        return fees;
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
        uint256 id = orderManager.requestBuyOrderFromCurrentBalance(_token, _orderAmount, _receiver);
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
        IERC20(_token).transfer(address(orderManager), orderAmount);
        // IERC20(_token).approve(address(orderManager), orderAmount);
        // balances before
        // uint256 id = issuer.createOrderStandardFees(order);
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        orderInstanceById[id] = order;
        return id;
    }
    


    function issuanceIndexTokens(uint _inputAmount) public returns(uint256) {
        uint feeAmount = (_inputAmount * feeRate) / 10000;
        uint256 orderProcessorFee = calculateIssuanceFee(_inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        IERC20(usdc).transferFrom(msg.sender, address(orderManager), quantityIn);
        IERC20(usdc).transferFrom(msg.sender, owner(), feeAmount);
        // IERC20(usdc).approve(address(orderManager), quantityIn);
        
        
        issuanceNonce += 1;
        // ContractOwnedAccount coa = new ContractOwnedAccount(address(this));
        // coaByIssuanceNonce[issuanceNonce] = address(coa);
        issuanceInputAmount[issuanceNonce] = _inputAmount;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 amount = _inputAmount * factoryStorage.tokenCurrentMarketShare(tokenAddress) / 100e18;
            // uint requestId = requestBuyOrder((tokenAddress, amount, address(coa));
            uint requestId = requestBuyOrder(tokenAddress, amount, address(orderManager));
            actionInfoById[requestId] = ActionInfo(1, issuanceNonce);
            buyRequestPayedAmountById[requestId] = amount;
            issuanceRequestId[issuanceNonce][tokenAddress] = requestId;
            issuanceRequesterByNonce[issuanceNonce] = msg.sender;
            uint wrappedDsharesBalance = IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(vault));
            uint dShareBalance = WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            issuanceTokenPrimaryBalance[issuanceNonce][tokenAddress] = dShareBalance;
            issuanceIndexTokenPrimaryTotalSupply[issuanceNonce] = IERC20(token).totalSupply();
        }
        emit RequestIssuance(issuanceNonce, msg.sender, usdc, _inputAmount, 0, block.timestamp);
        return issuanceNonce;
    }

    function completeIssuance(uint _issuanceNonce) public {
        require(factoryStorage.checkIssuanceOrdersStatus(_issuanceNonce), "Orders are not completed");
        require(!issuanceIsCompleted[_issuanceNonce], "Issuance is completed");
        address requester = issuanceRequesterByNonce[_issuanceNonce];
        uint primaryPortfolioValue;
        uint secondaryPortfolioValue;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 tokenRequestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            IOrderProcessor.PricePoint memory tokenPriceData = issuer.latestFillPrice(tokenAddress, address(usdc));
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 primaryBalance = issuanceTokenPrimaryBalance[_issuanceNonce][tokenAddress];
            uint256 primaryValue = primaryBalance*tokenPriceData.price;
            uint256 secondaryValue = primaryValue + buyRequestPayedAmountById[tokenRequestId];
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;
            orderManager.withdrawFunds(tokenAddress, address(this), balance);
            IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), balance);
            WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(balance, address(vault));
        }
            uint256 primaryTotalSupply = issuanceIndexTokenPrimaryTotalSupply[_issuanceNonce];
            if(primaryTotalSupply == 0 || primaryPortfolioValue == 0){
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
        // address coaAddress = coaByIssuanceNonce[_issuanceNonce];
        require(msg.sender == requester, "Only requester can cancel the issuance");
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            IOrderProcessor.Order memory order = orderInstanceById[requestId];
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE) && issuer.getReceivedAmount(requestId) == 0){
                // issuer.requestCancel(requestId);
                orderManager.cancelOrder(requestId);
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || issuer.getReceivedAmount(requestId) > 0){
                uint256 balance = issuer.getReceivedAmount(requestId);
                uint cancelRequestId = requestSellOrder(tokenAddress, balance, address(orderManager));
                actionInfoById[cancelRequestId] = ActionInfo(3, _issuanceNonce);
                cancelIssuanceRequestId[_issuanceNonce][tokenAddress] = cancelRequestId;
                if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                cancelIssuanceUnfilledAmount[_issuanceNonce][tokenAddress] = issuer.getUnfilledAmount(requestId);
                orderManager.cancelOrder(requestId);
                }
            }
        }
    }

    function completeCancelIssuance(uint256 _issuanceNonce) public {
        require(factoryStorage.checkCancelIssuanceStatus(_issuanceNonce), "Cancel issuance is not completed");
        require(!cancelIssuanceComplted[_issuanceNonce], "The process has been completed before");
        address requester = issuanceRequesterByNonce[_issuanceNonce];
        uint totalBalance;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = issuanceRequestId[_issuanceNonce][tokenAddress];
            uint256 balance = issuer.getReceivedAmount(requestId);
            uint unfilledAmount = cancelIssuanceUnfilledAmount[_issuanceNonce][tokenAddress];
            totalBalance += (balance + unfilledAmount);
        }
        orderManager.withdrawFunds(usdc, requester, totalBalance);
        cancelIssuanceComplted[_issuanceNonce] = true;
    }

    


    function redemption(uint _inputAmount) public returns(uint) {
        redemptionNonce += 1;
        redemptionInputAmount[redemptionNonce] = _inputAmount;
        uint tokenBurnPercent = _inputAmount*1e18/token.totalSupply(); 
        token.burn(msg.sender, _inputAmount);
        burnedTokenAmountByNonce[redemptionNonce] = _inputAmount;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 amount = tokenBurnPercent * IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(vault)) / 1e18;
            uint requestId = requestSellOrder(tokenAddress, amount, address(orderManager));
            actionInfoById[requestId] = ActionInfo(2, redemptionNonce);
            sellRequestAssetAmountById[requestId] = amount;
            redemptionRequestId[redemptionNonce][tokenAddress] = requestId;
            redemptionRequesterByNonce[redemptionNonce] = msg.sender;
            uint wrappedDsharesBalance = IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(vault));
            uint dShareBalance = WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            redemptionTokenPrimaryBalance[redemptionNonce][tokenAddress] = dShareBalance;
            redemptionIndexTokenPrimaryTotalSupply[redemptionNonce] = IERC20(token).totalSupply();
        }
        emit RequestRedemption(redemptionNonce, msg.sender, usdc, _inputAmount, 0, block.timestamp);
        return redemptionNonce;
    }

    

    function completeRedemption(uint _redemptionNonce) public {
        require(factoryStorage.checkRedemptionOrdersStatus(_redemptionNonce), "Redemption orders are not completed");
        require(!redemptionIsCompleted[_redemptionNonce], "Redemption is completed");
        address requester = redemptionRequesterByNonce[_redemptionNonce];
        uint totalBalance;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 tokenRequestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 feeTaken = issuer.getFeesTaken(tokenRequestId);
            totalBalance += balance - feeTaken;
        }
        uint fee = (totalBalance * feeRate) / 10000;
        orderManager.withdrawFunds(usdc, owner(), fee);
        orderManager.withdrawFunds(usdc, requester, totalBalance - fee);
        redemptionIsCompleted[_redemptionNonce] = true;
        emit Redemption(_redemptionNonce, requester, usdc, redemptionInputAmount[_redemptionNonce], totalBalance, block.timestamp);
    }

    function cancelRedemption(uint _redemptionNonce) public {
        require(!redemptionIsCompleted[_redemptionNonce], "Redemption is completed");
        address requester = redemptionRequesterByNonce[_redemptionNonce];
        address coaAddress = coaByRedemptionNonce[_redemptionNonce];
        require(msg.sender == requester, "Only requester can cancel the redemption");
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = redemptionRequestId[_redemptionNonce][tokenAddress];
            IOrderProcessor.Order memory order = orderInstanceById[requestId];
            uint filledAmount = issuer.getReceivedAmount(requestId) - issuer.getFeesTaken(requestId);
            uint unFilledAmount = issuer.getUnfilledAmount(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE) && filledAmount == 0){
                orderManager.cancelOrder(requestId);
                cancelRedemptionUnfilledAmount[_redemptionNonce][tokenAddress] = unFilledAmount;
            }else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || filledAmount > 0){
                uint cancelRequestId = requestBuyOrder(tokenAddress, filledAmount, address(coaAddress));
                actionInfoById[cancelRequestId] = ActionInfo(4, _redemptionNonce);
                cancelRedemptionRequestId[_redemptionNonce][tokenAddress] = requestId;
                if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                    cancelRedemptionUnfilledAmount[_redemptionNonce][tokenAddress] = unFilledAmount;
                    orderManager.cancelOrder(requestId);
                }
            }
        }
    }

    function completeCancelRedemption(uint256 _redemptionNonce) public {
        require(factoryStorage.checkCancelRedemptionStatus(_redemptionNonce), "Cancel redemption is not completed");
        require(!cancelRedemptionComplted[_redemptionNonce], "The process has been completed before");

        address requester = redemptionRequesterByNonce[_redemptionNonce];
        address coaAddress = coaByRedemptionNonce[_redemptionNonce];
        uint256 balance = IERC20(usdc).balanceOf(coaAddress);
        for(uint i; i < factoryStorage.totalCurrentList(); i++){
            address tokenAddress = factoryStorage.currentList(i);
            // uint tokenBalance = IERC20(tokenAddress).balanceOf(coaAddress);
            uint tokenRequestId = cancelRedemptionRequestId[_redemptionNonce][tokenAddress];
            uint filledAmount = issuer.getReceivedAmount(tokenRequestId) - issuer.getFeesTaken(tokenRequestId);
            uint unFilledAmount = cancelRedemptionUnfilledAmount[_redemptionNonce][tokenAddress];
            uint totalBalance = filledAmount + unFilledAmount;
            if(totalBalance > 0){
                orderManager.withdrawFunds(tokenAddress, address(this), totalBalance);
                IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), totalBalance);
                WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(totalBalance, address(vault));
            }
        }
        token.mint(requester, burnedTokenAmountByNonce[_redemptionNonce]);
        cancelRedemptionComplted[_redemptionNonce] = true;
    }

    

    
    // function getActionType(uint _requestId) public view returns(uint){
    //     return actionInfoById[_requestId].actionType;
    // }

    function checkMultical(uint _reqeustId) public view returns (bool){
        ActionInfo memory actionInfo = actionInfoById[_reqeustId];
        if(actionInfo.actionType == 1){
            return factoryStorage.checkIssuanceOrdersStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 2){
            return factoryStorage.checkRedemptionOrdersStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 3){
            return factoryStorage.checkCancelIssuanceStatus(actionInfo.nonce);
        }else if(actionInfo.actionType == 4){
            return factoryStorage.checkCancelRedemptionStatus(actionInfo.nonce);
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
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    

    // function getTimestamp() internal view returns (uint256) {
    //     // timestamp is only used for data maintaining purpose, it is not relied on for critical logic.
    //     return block.timestamp; // solhint-disable-line not-rely-on-time
    // }

    

    // function compareStrings(
    //     string memory a,
    //     string memory b
    // ) internal pure returns (bool) {
    //     return (keccak256(abi.encodePacked(a)) ==
    //         keccak256(abi.encodePacked(b)));
    // }

    // function isEmptyString(string memory a) internal pure returns (bool) {
    //     return (compareStrings(a, ""));
    // }

    
}
