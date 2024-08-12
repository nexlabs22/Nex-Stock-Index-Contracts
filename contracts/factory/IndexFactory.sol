// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../dinary/orders/IOrderProcessor.sol";
import {FeeLib} from "../dinary/common/FeeLib.sol";
import "../vault/NexVault.sol";
import "../dinary/WrappedDShare.sol";
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

    
    


    IndexFactoryStorage public factoryStorage;
    

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
        address _factoryStorage
    ) external initializer {
        factoryStorage = IndexFactoryStorage(_factoryStorage);
       
        __Ownable_init(msg.sender);
        __Pausable_init();
    }

    




    function setIndexFactoryStorage(address _factoryStorage) external onlyOwner returns (bool) {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        return true;
    }
    

    function getOrderInstanceById(uint256 id) external view returns(IOrderProcessor.Order memory){
        return factoryStorage.orderInstanceById(id);
    }

    

    function requestBuyOrder(address _token, uint256 _orderAmount, address _receiver) internal returns(uint) {
       
        
        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;
       
        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestBuyOrderFromCurrentBalance(_token, _orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return id;
    }

    


    function requestSellOrder(address _token, uint256 _amount, address _receiver) internal returns(uint) {
        address wrappedDshare = factoryStorage.wrappedDshareAddress(_token);
        NexVault(factoryStorage.vault()).withdrawFunds(wrappedDshare, address(this), _amount);
        uint orderAmount = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;
        
        IERC20(_token).transfer(address(factoryStorage.orderManager()), orderAmount);
        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return id;
    }
    


    function issuanceIndexTokens(uint _inputAmount) public returns(uint256) {
        uint feeAmount = (_inputAmount * factoryStorage.feeRate()) / 10000;
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(_inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        IERC20(factoryStorage.usdc()).transferFrom(msg.sender, address(factoryStorage.orderManager()), quantityIn);
        IERC20(factoryStorage.usdc()).transferFrom(msg.sender, owner(), feeAmount);
        
        
        factoryStorage.increaseIssuanceNonce();
        uint issuanceNonce = factoryStorage.issuanceNonce();
        factoryStorage.issuanceInputAmount(issuanceNonce) = _inputAmount;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 amount = _inputAmount * factoryStorage.tokenCurrentMarketShare(tokenAddress) / 100e18;
            uint requestId = requestBuyOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.actionInfoById(requestId) = ActionInfo(1, issuanceNonce);
            factoryStorage.buyRequestPayedAmountById(requestId) = amount;
            factoryStorage.issuanceRequestId(issuanceNonce, tokenAddress) = requestId;
            factoryStorage.issuanceRequesterByNonce(issuanceNonce) = msg.sender;
            uint wrappedDsharesBalance = IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint dShareBalance = WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            factoryStorage.issuanceTokenPrimaryBalance(issuanceNonce, tokenAddress) = dShareBalance;
            factoryStorage.issuanceIndexTokenPrimaryTotalSupply(issuanceNonce) = IERC20(factoryStorage.token()).totalSupply();
        }
        emit RequestIssuance(issuanceNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        return issuanceNonce;
    }

    function completeIssuance(uint _issuanceNonce) public {
        require(factoryStorage.checkIssuanceOrdersStatus(_issuanceNonce), "Orders are not completed");
        require(!factoryStorage.issuanceIsCompleted(_issuanceNonce), "Issuance is completed");
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        IOrderProcessor issuer = factoryStorage.issuer();
        uint primaryPortfolioValue;
        uint secondaryPortfolioValue;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 tokenRequestId = factoryStorage.issuanceRequestId(_issuanceNonce, tokenAddress);
            IOrderProcessor.PricePoint memory tokenPriceData = issuer.latestFillPrice(tokenAddress, factoryStorage.usdc());
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 primaryBalance = factoryStorage.issuanceTokenPrimaryBalance(_issuanceNonce, tokenAddress);
            uint256 primaryValue = primaryBalance*tokenPriceData.price;
            uint256 secondaryValue = primaryValue + factoryStorage.buyRequestPayedAmountById(tokenRequestId);
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;
            OrderManager orderManager = factoryStorage.orderManager();
            orderManager.withdrawFunds(tokenAddress, address(this), balance);
            IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), balance);
            WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(balance, address(factoryStorage.vault()));
        }
            uint256 primaryTotalSupply = factoryStorage.issuanceIndexTokenPrimaryTotalSupply(_issuanceNonce);
            if(primaryTotalSupply == 0 || primaryPortfolioValue == 0){
                uint256 mintAmount = secondaryPortfolioValue*100;
                IndexToken token = factoryStorage.token();
                token.mint(requester, mintAmount);
                emit Issuanced(_issuanceNonce, requester, factoryStorage.usdc(), factoryStorage.issuanceInputAmount(_issuanceNonce), mintAmount, block.timestamp);
            }else{
                uint256 secondaryTotalSupply = primaryTotalSupply * secondaryPortfolioValue / primaryPortfolioValue;
                uint256 mintAmount = secondaryTotalSupply - primaryTotalSupply;
                IndexToken token = factoryStorage.token();
                token.mint(requester, mintAmount);
                emit Issuanced(_issuanceNonce, requester, factoryStorage.usdc(), factoryStorage.issuanceInputAmount(_issuanceNonce), mintAmount, block.timestamp);
            }
            factoryStorage.setIssuanceIsCompleted(_issuanceNonce, true);
    }

    function cancelIssuance(uint256 _issuanceNonce) public {
        require(!factoryStorage.issuanceIsCompleted(_issuanceNonce), "Issuance is completed");
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        require(msg.sender == requester, "Only requester can cancel the issuance");
        IOrderProcessor issuer = factoryStorage.issuer();
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = factoryStorage.issuanceRequestId(_issuanceNonce, tokenAddress);
            IOrderProcessor.Order memory order = factoryStorage.orderInstanceById(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE) && issuer.getReceivedAmount(requestId) == 0){
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.cancelOrder(requestId);
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || issuer.getReceivedAmount(requestId) > 0){
                uint256 balance = issuer.getReceivedAmount(requestId);
                uint cancelRequestId = requestSellOrder(tokenAddress, balance, address(factoryStorage.orderManager()));
                factoryStorage.actionInfoById(cancelRequestId) = ActionInfo(3, _issuanceNonce);
                factoryStorage.cancelIssuanceRequestId(_issuanceNonce, tokenAddress) = cancelRequestId;
                if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                factoryStorage.cancelIssuanceUnfilledAmount(_issuanceNonce, tokenAddress) = issuer.getUnfilledAmount(requestId);
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.cancelOrder(requestId);
                }
            }
        }
    }

    function completeCancelIssuance(uint256 _issuanceNonce) public {
        require(factoryStorage.checkCancelIssuanceStatus(_issuanceNonce), "Cancel issuance is not completed");
        require(!factoryStorage.cancelIssuanceComplted(_issuanceNonce), "The process has been completed before");
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        uint totalBalance;
        IOrderProcessor issuer = factoryStorage.issuer();
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = factoryStorage.issuanceRequestId(_issuanceNonce, tokenAddress);
            uint256 balance = issuer.getReceivedAmount(requestId);
            uint unfilledAmount = factoryStorage.cancelIssuanceUnfilledAmount(_issuanceNonce, tokenAddress);
            totalBalance += (balance + unfilledAmount);
        }
        OrderManager orderManager = factoryStorage.orderManager();
        orderManager.withdrawFunds(factoryStorage.usdc(), requester, totalBalance);
        factoryStorage.setCancelIssuanceComplted(_issuanceNonce, true);
    }

    


    function redemption(uint _inputAmount) public returns(uint) {
        factoryStorage.increaseRedemptionNonce();
        uint redemptionNonce = factoryStorage.redemptionNonce();
        factoryStorage.redemptionInputAmount(redemptionNonce) = _inputAmount;
        IndexToken token = factoryStorage.token();
        uint tokenBurnPercent = _inputAmount*1e18/token.totalSupply(); 
        token.burn(msg.sender, _inputAmount);
        factoryStorage.burnedTokenAmountByNonce(redemptionNonce) = _inputAmount;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 amount = tokenBurnPercent * IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault())) / 1e18;
            uint requestId = requestSellOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.actionInfoById(requestId) = ActionInfo(2, redemptionNonce);
            factoryStorage.sellRequestAssetAmountById(requestId) = amount;
            factoryStorage.redemptionRequestId(redemptionNonce, tokenAddress) = requestId;
            factoryStorage.redemptionRequesterByNonce(redemptionNonce) = msg.sender;
            uint wrappedDsharesBalance = IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint dShareBalance = WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            factoryStorage.redemptionTokenPrimaryBalance(redemptionNonce, tokenAddress) = dShareBalance;
            factoryStorage.redemptionIndexTokenPrimaryTotalSupply(redemptionNonce) = IERC20(factoryStorage.token()).totalSupply();
        }
        emit RequestRedemption(redemptionNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        return redemptionNonce;
    }

    

    function completeRedemption(uint _redemptionNonce) public {
        require(factoryStorage.checkRedemptionOrdersStatus(_redemptionNonce), "Redemption orders are not completed");
        require(!factoryStorage.redemptionIsCompleted(_redemptionNonce), "Redemption is completed");
        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        IOrderProcessor issuer = factoryStorage.issuer();
        uint totalBalance;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 tokenRequestId = factoryStorage.redemptionRequestId(_redemptionNonce, tokenAddress);
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 feeTaken = issuer.getFeesTaken(tokenRequestId);
            totalBalance += balance - feeTaken;
        }
        uint fee = (totalBalance * factoryStorage.feeRate()) / 10000;
        OrderManager orderManager = factoryStorage.orderManager();
        orderManager.withdrawFunds(factoryStorage.usdc(), owner(), fee);
        orderManager.withdrawFunds(factoryStorage.usdc(), requester, totalBalance - fee);
        factoryStorage.setRedemptionIsCompleted(_redemptionNonce, true);
        emit Redemption(_redemptionNonce, requester, factoryStorage.usdc(), factoryStorage.redemptionInputAmount(_redemptionNonce), totalBalance, block.timestamp);
    }

    function cancelRedemption(uint _redemptionNonce) public {
        require(!factoryStorage.redemptionIsCompleted(_redemptionNonce), "Redemption is completed");
        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        require(msg.sender == requester, "Only requester can cancel the redemption");
        IOrderProcessor issuer = factoryStorage.issuer();
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = factoryStorage.redemptionRequestId(_redemptionNonce, tokenAddress);
            IOrderProcessor.Order memory order = factoryStorage.orderInstanceById(requestId);
            uint filledAmount = issuer.getReceivedAmount(requestId) - issuer.getFeesTaken(requestId);
            uint unFilledAmount = issuer.getUnfilledAmount(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE) && filledAmount == 0){
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.cancelOrder(requestId);
                factoryStorage.cancelRedemptionUnfilledAmount(_redemptionNonce, tokenAddress) = unFilledAmount;
            }else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || filledAmount > 0){
                uint cancelRequestId = requestBuyOrder(tokenAddress, filledAmount, address(factoryStorage.orderManager()));
                factoryStorage.actionInfoById(cancelRequestId) = ActionInfo(4, _redemptionNonce);
                factoryStorage.cancelRedemptionRequestId(_redemptionNonce, tokenAddress) = requestId;
                if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                    factoryStorage.cancelRedemptionUnfilledAmount(_redemptionNonce, tokenAddress) = unFilledAmount;
                    OrderManager orderManager = factoryStorage.orderManager();
                    orderManager.cancelOrder(requestId);
                }
            }
        }
    }

    function completeCancelRedemption(uint256 _redemptionNonce) public {
        require(factoryStorage.checkCancelRedemptionStatus(_redemptionNonce), "Cancel redemption is not completed");
        require(!factoryStorage.cancelRedemptionComplted(_redemptionNonce), "The process has been completed before");

        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        IOrderProcessor issuer = factoryStorage.issuer();
        for(uint i; i < factoryStorage.totalCurrentList(); i++){
            address tokenAddress = factoryStorage.currentList(i);
            uint tokenRequestId = factoryStorage.cancelRedemptionRequestId(_redemptionNonce, tokenAddress);
            uint filledAmount = issuer.getReceivedAmount(tokenRequestId) - issuer.getFeesTaken(tokenRequestId);
            uint unFilledAmount = factoryStorage.cancelRedemptionUnfilledAmount(_redemptionNonce, tokenAddress);
            uint totalBalance = filledAmount + unFilledAmount;
            if(totalBalance > 0){
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.withdrawFunds(tokenAddress, address(this), totalBalance);
                IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), totalBalance);
                WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(totalBalance, address(factoryStorage.vault()));
            }
        }
        IndexToken token = factoryStorage.token();
        token.mint(requester, factoryStorage.burnedTokenAmountByNonce(_redemptionNonce));
        factoryStorage.cancelRedemptionComplted(_redemptionNonce) = true;
    }

    

    
    // function getActionType(uint _requestId) public view returns(uint){
    //     return actionInfoById[_requestId].actionType;
    // }

    function checkMultical(uint _reqeustId) public view returns (bool){
        ActionInfo memory actionInfo = factoryStorage.actionInfoById(_reqeustId);
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
        ActionInfo memory actionInfo = factoryStorage.actionInfoById(_requestId);
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

    

    
}
