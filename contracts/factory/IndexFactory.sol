// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../dinary/orders/IOrderProcessor.sol";
import {FeeLib} from "../dinary/common/FeeLib.sol";
import "../vault/NexVault.sol";
import "../dinary/WrappedDShare.sol";
import "./IndexFactoryStorage.sol";
import "./IndexFactoryProcessor.sol";
import "./OrderManager.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactory is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
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

    event RequestCancelIssuance(
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

    event RequestCancelRedemption(
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

    /**
     * @dev Initializes the contract with the given factory storage address.
     * @param _factoryStorage The address of the factory storage contract.
     */
    function initialize(
        address _factoryStorage
    ) external initializer {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
       
        __Ownable_init(msg.sender);
        __Pausable_init();
    }

    




    /**
     * @dev Sets the factory storage address.
     * @param _factoryStorage The address of the new factory storage contract.
     * @return bool indicating success.
     */
    function setIndexFactoryStorage(address _factoryStorage) external onlyOwner returns (bool) {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        return true;
    }
    

    

    /**
     * @dev Requests a buy order.
     * @param _token The address of the token to buy.
     * @param _orderAmount The amount of the token to buy.
     * @param _receiver The address to receive the bought tokens.
     * @return uint The ID of the buy order.
     */
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

    


    /**
     * @dev Requests a sell order.
     * @param _token The address of the token to sell.
     * @param _amount The amount of the token to sell.
     * @param _receiver The address to receive the sold tokens.
     * @return (uint, uint) The ID of the sell order and the order amount.
     */
    function requestSellOrder(address _token, uint256 _amount, address _receiver) internal returns(uint, uint) {
        address wrappedDshare = factoryStorage.wrappedDshareAddress(_token);
        NexVault(factoryStorage.vault()).withdrawFunds(wrappedDshare, address(this), _amount);
        uint orderAmount0 = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        //rounding order
        IOrderProcessor issuer = factoryStorage.issuer();
        uint8 decimalReduction = issuer.orderDecimalReduction(_token);
        uint256 orderAmount = orderAmount0 - (orderAmount0 % 10 ** (decimalReduction - 1));
        uint extraAmount = orderAmount0 - orderAmount;

        if(extraAmount > 0){
            IERC20(_token).approve(wrappedDshare, extraAmount);
            WrappedDShare(wrappedDshare).deposit(extraAmount, address(factoryStorage.vault()));
        }

        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;
        
        IERC20(_token).transfer(address(factoryStorage.orderManager()), orderAmount);
        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return (id, orderAmount);
        
    }

    /**
     * @dev Requests a sell order from the order manager's balance.
     * @param _token The address of the token to sell.
     * @param _amount The amount of the token to sell.
     * @param _receiver The address to receive the sold tokens.
     * @return (uint, uint) The ID of the sell order and the order amount.
     */
    function requestSellOrderFromOrderManagerBalance(address _token, uint256 _amount, address _receiver) internal returns(uint, uint) {
       

        //rounding order
        IOrderProcessor issuer = factoryStorage.issuer();
        uint8 decimalReduction = issuer.orderDecimalReduction(_token);
        uint256 orderAmount = _amount - (_amount % 10 ** (decimalReduction - 1));
        uint extraAmount = _amount - orderAmount;


        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;
        
        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return (id, orderAmount);
    }
    


    /**
     * @dev Issues index tokens.
     * @param _inputAmount The amount of input tokens.
     * @return uint256 The issuance nonce.
     */
    function issuanceIndexTokens(uint _inputAmount) public nonReentrant returns(uint256) {
        require(_inputAmount > 0, "Invalid input amount");
        uint feeAmount = (_inputAmount * factoryStorage.feeRate()) / 10000;
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(_inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        require(IERC20(factoryStorage.usdc()).transferFrom(msg.sender, address(factoryStorage.orderManager()), quantityIn), "Transfer failed");
        require(IERC20(factoryStorage.usdc()).transferFrom(msg.sender, factoryStorage.feeReceiver(), feeAmount), "Transfer failed");
        
        
        factoryStorage.increaseIssuanceNonce();
        uint issuanceNonce = factoryStorage.issuanceNonce();
        factoryStorage.setIssuanceInputAmount(issuanceNonce, _inputAmount);
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 amount = _inputAmount * factoryStorage.tokenCurrentMarketShare(tokenAddress) / 100e18;
            uint requestId = requestBuyOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.setActionInfoById(requestId, IndexFactoryStorage.ActionInfo(1, issuanceNonce));
            factoryStorage.setBuyRequestPayedAmountById(requestId, amount);
            factoryStorage.setIssuanceRequestId(issuanceNonce, tokenAddress, requestId);
            factoryStorage.setIssuanceRequesterByNonce(issuanceNonce, msg.sender);
            uint wrappedDsharesBalance = IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint dShareBalance = WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            factoryStorage.setIssuanceTokenPrimaryBalance(issuanceNonce, tokenAddress, dShareBalance);
            factoryStorage.setIssuanceIndexTokenPrimaryTotalSupply(issuanceNonce, IERC20(factoryStorage.token()).totalSupply());
        }
        emit RequestIssuance(issuanceNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        return issuanceNonce;
    }

    

    /**
     * @dev Cancels an issuance.
     * @param _issuanceNonce The nonce of the issuance to cancel.
     */
    function cancelIssuance(uint256 _issuanceNonce) public {
        require(!factoryStorage.issuanceIsCompleted(_issuanceNonce), "Issuance is completed");
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        require(msg.sender == requester, "Only requester can cancel the issuance");
        IOrderProcessor issuer = factoryStorage.issuer();
        uint latestCancelIssuanceReqeustId;
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = factoryStorage.issuanceRequestId(_issuanceNonce, tokenAddress);
            IOrderProcessor.Order memory order = factoryStorage.getOrderInstanceById(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE) && issuer.getReceivedAmount(requestId) == 0){
                OrderManager orderManager = factoryStorage.orderManager();
                factoryStorage.setCancelIssuanceUnfilledAmount(_issuanceNonce, tokenAddress, issuer.getUnfilledAmount(requestId));
                orderManager.cancelOrder(requestId);
            } else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || issuer.getReceivedAmount(requestId) > 0){
                uint256 balance = issuer.getReceivedAmount(requestId);
                (uint cancelRequestId, uint assetAmount) = requestSellOrderFromOrderManagerBalance(tokenAddress, balance, address(factoryStorage.orderManager()));
                factoryStorage.setActionInfoById(cancelRequestId, IndexFactoryStorage.ActionInfo(3, _issuanceNonce));
                factoryStorage.setCancelIssuanceRequestId(_issuanceNonce, tokenAddress, cancelRequestId);
                factoryStorage.setSellRequestAssetAmountById(cancelRequestId, assetAmount);
                latestCancelIssuanceReqeustId = cancelRequestId;
                if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
                factoryStorage.setCancelIssuanceUnfilledAmount(_issuanceNonce, tokenAddress, issuer.getUnfilledAmount(requestId));
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.cancelOrder(requestId);
                }
            }
        }
        emit RequestCancelIssuance(_issuanceNonce, requester, factoryStorage.usdc(), factoryStorage.issuanceInputAmount(_issuanceNonce), 0, block.timestamp);
    }

    
    


    /**
     * @dev Redeems index tokens.
     * @param _inputAmount The amount of input tokens.
     * @return uint The redemption nonce.
     */
    function redemption(uint _inputAmount) public nonReentrant returns(uint) {
        require(_inputAmount > 0, "Invalid input amount");
        factoryStorage.increaseRedemptionNonce();
        uint redemptionNonce = factoryStorage.redemptionNonce();
        factoryStorage.setRedemptionInputAmount(redemptionNonce, _inputAmount);
        IndexToken token = factoryStorage.token();
        uint tokenBurnPercent = _inputAmount*1e18/token.totalSupply(); 
        token.burn(msg.sender, _inputAmount);
        factoryStorage.setBurnedTokenAmountByNonce(redemptionNonce, _inputAmount);
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint256 amount = tokenBurnPercent * IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault())) / 1e18;
            (uint requestId, uint assetAmount) = requestSellOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.setActionInfoById(requestId, IndexFactoryStorage.ActionInfo(2, redemptionNonce));
            factoryStorage.setSellRequestAssetAmountById(requestId, assetAmount);
            factoryStorage.setRedemptionRequestId(redemptionNonce, tokenAddress, requestId);
            factoryStorage.setRedemptionRequesterByNonce(redemptionNonce, msg.sender);
        }
        emit RequestRedemption(redemptionNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        return redemptionNonce;
    }

    

    /**
     * @dev Cancels an executed redemption.
     * @param _tokenAddress The address of the token.
     * @param _redemptionNonce The nonce of the redemption.
     * @param _requestId The ID of the request.
     * @param _filledAmount The filled amount.
     * @param _unFilledAmount The unfilled amount.
     */
    function _cancelExecutedRedemption(
      address _tokenAddress,
        uint _redemptionNonce,
        uint _requestId,
        uint _filledAmount,
        uint _unFilledAmount
    ) internal {
        IOrderProcessor issuer = factoryStorage.issuer();
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(factoryStorage.usdc()));
        uint amountAfterFee = factoryStorage.getAmountAfterFee(percentageFeeRate, _filledAmount) - flatFee;
        uint cancelRequestId = requestBuyOrder(_tokenAddress, amountAfterFee, address(factoryStorage.orderManager()));
        factoryStorage.setActionInfoById(cancelRequestId, IndexFactoryStorage.ActionInfo(4, _redemptionNonce));
        factoryStorage.setCancelRedemptionRequestId(_redemptionNonce, _tokenAddress, cancelRequestId);
        if(uint8(issuer.getOrderStatus(_requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)){
            factoryStorage.setCancelRedemptionUnfilledAmount(_redemptionNonce, _tokenAddress, _unFilledAmount);
            OrderManager orderManager = factoryStorage.orderManager();
            orderManager.cancelOrder(_requestId);
        }
    }

    /**
     * @dev Cancels a redemption.
     * @param _redemptionNonce The nonce of the redemption to cancel.
     */
    function cancelRedemption(uint _redemptionNonce) public {
        require(!factoryStorage.redemptionIsCompleted(_redemptionNonce), "Redemption is completed");
        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        require(msg.sender == requester, "Only requester can cancel the redemption");
        IOrderProcessor issuer = factoryStorage.issuer();
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = factoryStorage.redemptionRequestId(_redemptionNonce, tokenAddress);
            IOrderProcessor.Order memory order = factoryStorage.getOrderInstanceById(requestId);
            uint filledAmount = issuer.getReceivedAmount(requestId) - issuer.getFeesTaken(requestId);
            uint unFilledAmount = issuer.getUnfilledAmount(requestId);
            if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE) && filledAmount == 0){
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.cancelOrder(requestId);
                factoryStorage.setActionInfoById(requestId, IndexFactoryStorage.ActionInfo(4, _redemptionNonce));
                factoryStorage.setCancelRedemptionUnfilledAmount(_redemptionNonce, tokenAddress, unFilledAmount);
            }else if(uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED) || filledAmount > 0){
                _cancelExecutedRedemption(
                    tokenAddress,
                    _redemptionNonce,
                    requestId,
                    filledAmount,
                    unFilledAmount
                );
            }
        }
        emit RequestCancelRedemption(_redemptionNonce, requester, factoryStorage.usdc(), factoryStorage.redemptionInputAmount(_redemptionNonce), 0, block.timestamp);
    }

    

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    

    
}
