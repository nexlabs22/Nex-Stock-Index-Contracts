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
// import "../libraries/Commen.sol" as PrbMath;
import "./IndexFactoryStorage.sol";
import "./OrderManager.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryProcessor is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    
    struct ActionInfo {
        uint actionType;
        uint nonce; 
    }

    
    


    IndexFactoryStorage public factoryStorage;
    

    

    event Issuanced(
        uint indexed nonce,
        address indexed user,
        address inputToken,
        uint inputAmount,
        uint outputAmount,
        uint time
    );

    event IssuanceCancelled(
        uint indexed nonce,
        address indexed user,
        address inputToken,
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

    event RedemptionCancelled(
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
            // IOrderProcessor.PricePoint memory tokenPriceData = issuer.latestFillPrice(tokenAddress, factoryStorage.usdc());
            uint price = factoryStorage.priceInWei(tokenAddress);
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 receivedValue = balance*price/1e18;
            uint256 primaryBalance = factoryStorage.issuanceTokenPrimaryBalance(_issuanceNonce, tokenAddress);
            uint256 primaryValue = primaryBalance*price/1e18;
            uint256 secondaryValue = primaryValue + receivedValue;
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



    function completeCancelIssuance(uint256 _issuanceNonce) public {
        require(factoryStorage.checkCancelIssuanceStatus(_issuanceNonce), "Cancel issuance is not completed");
        require(!factoryStorage.cancelIssuanceComplted(_issuanceNonce), "The process has been completed before");
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        uint totalBalance;
        IOrderProcessor issuer = factoryStorage.issuer();
        for(uint i; i < factoryStorage.totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.currentList(i);
            uint requestId = factoryStorage.issuanceRequestId(_issuanceNonce, tokenAddress);
            uint cancelRequestId = factoryStorage.cancelIssuanceRequestId(_issuanceNonce, tokenAddress);
            uint256 balance;
            if(cancelRequestId > 0){
            uint256 feeTaken = issuer.getFeesTaken(cancelRequestId);
            uint receivedAmount = issuer.getReceivedAmount(cancelRequestId);
            balance += receivedAmount - feeTaken;
            }
            uint unfilledAmount = factoryStorage.cancelIssuanceUnfilledAmount(_issuanceNonce, tokenAddress);
            totalBalance += (balance + unfilledAmount);
        }
        OrderManager orderManager = factoryStorage.orderManager();
        orderManager.withdrawFunds(factoryStorage.usdc(), requester, totalBalance);
        factoryStorage.setCancelIssuanceComplted(_issuanceNonce, true);
        emit IssuanceCancelled(_issuanceNonce, requester, factoryStorage.usdc(), factoryStorage.issuanceInputAmount(_issuanceNonce), 0, block.timestamp);
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
        orderManager.withdrawFunds(factoryStorage.usdc(), factoryStorage.feeReceiver(), fee);
        orderManager.withdrawFunds(factoryStorage.usdc(), requester, totalBalance - fee);
        factoryStorage.setRedemptionIsCompleted(_redemptionNonce, true);
        emit Redemption(_redemptionNonce, requester, factoryStorage.usdc(), factoryStorage.redemptionInputAmount(_redemptionNonce), totalBalance, block.timestamp);
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
        factoryStorage.setCancelRedemptionComplted(_redemptionNonce, true);
        emit RedemptionCancelled(_redemptionNonce, requester, factoryStorage.usdc(), factoryStorage.redemptionInputAmount(_redemptionNonce), 0, block.timestamp);
    }

    

    function checkMultical(uint _reqeustId) public view returns (bool){
        IndexFactoryStorage.ActionInfo memory actionInfo = factoryStorage.getActionInfoById(_reqeustId);
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
        IndexFactoryStorage.ActionInfo memory actionInfo = factoryStorage.getActionInfoById(_requestId);
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
    

    

    
}
