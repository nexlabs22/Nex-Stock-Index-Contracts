// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../vault/NexVault.sol";
import "../dinary/WrappedDShare.sol";
import "./IndexFactoryStorage.sol";
import "./IndexFactoryProcessor.sol";
import "./OrderManager.sol";
import "./FunctionsOracle.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
/// @custom:oz-upgrades-from IndexFactory
// IndexFactoryV2
contract IndexFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    
    error InvalidActionState(
        uint256 nonce,
        IndexFactoryStorage.ActionState expected,
        IndexFactoryStorage.ActionState actual
    );

    error NoMatchingPendingIntent(uint256 intentId);

    error EmergencyUnlockWithPendingIntent(address user);

    /// @dev Mirrors IndexFactoryProcessor.IssuanceCancelled for indexer compatibility.
    event IssuanceCancelled(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    /// @dev Mirrors IndexFactoryProcessor.RedemptionCancelled for indexer compatibility.
    event RedemptionCancelled(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    uint256 public constant ORDER_INTENT_TIMEOUT = 24 hours;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    event OrderIntentIssuance(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event OrderIntentCancelIssuance(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event OrderIntentRedemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event OrderIntentCancelRedemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    
    modifier onlyOwnerOrOperatorOrBalancer() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender) || msg.sender == factoryStorage.factoryBalancerAddress(),
            "Caller is not the owner or operator or balancer."
        );
        _;
    }
    /**
     * @dev Initializes the contract with the given factory storage address.
     * @param _factoryStorage The address of the factory storage contract.
     */
    function initialize(address _factoryStorage, address _functionsOracle) external initializer {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Sets the functions oracle address.
     * @param _functionsOracle The address of the new functions oracle contract.
     */
    function setFunctionsOracle(address _functionsOracle) external onlyOwner {
        require(_functionsOracle != address(0), "invalid functions oracle address");
        functionsOracle = FunctionsOracle(_functionsOracle);
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
     * @dev Asynchronous Issuance Request (Dinari V2)
     * @param _inputAmount The amount of input tokens (USDC).
     * @return uint256 The issuance nonce (Intent ID).
     */
    function issuanceIndexTokens(uint256 _inputAmount) public nonReentrant whenNotPaused returns (uint256) {
        require(_inputAmount > 0, "Invalid input amount");
        require(!factoryStorage.isUserActionPending(msg.sender), "User has pending action");
        
        // 1. Calculate Fees & Required Input
        uint256 feeAmount = (_inputAmount * factoryStorage.feeRate()) / 10000;
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(_inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        
        // 2. Escrow Logic: Transfer USDC from User to OrderManager (Safe Vault) & FeeReceiver
        IERC20(factoryStorage.usdc()).safeTransferFrom(msg.sender, address(factoryStorage.orderManager()), quantityIn);
        IERC20(factoryStorage.usdc()).safeTransferFrom(msg.sender, factoryStorage.feeReceiver(), feeAmount);

        // 3. Register the Intent (Pending State)
        factoryStorage.increaseIssuanceNonce();
        uint256 issuanceNonce = factoryStorage.issuanceNonce();
        IndexFactoryStorage.ActionState currentIssuanceState = factoryStorage.issuanceState(issuanceNonce);
        if (currentIssuanceState != IndexFactoryStorage.ActionState.NONE) {
            revert InvalidActionState(
                issuanceNonce, IndexFactoryStorage.ActionState.NONE, currentIssuanceState
            );
        }
        factoryStorage.setIssuanceInputAmount(issuanceNonce, _inputAmount);
        factoryStorage.setIssuanceRequesterByNonce(issuanceNonce, msg.sender);
        factoryStorage.setUserActionPending(msg.sender, true);
        factoryStorage.setUserPendingIssuanceNonce(msg.sender, issuanceNonce);
        factoryStorage.increasePendingIssuanceUsdc(quantityIn);
        factoryStorage.setIssuanceIntentTimestamp(issuanceNonce, block.timestamp);

        // 4. Record Pre-Issuance Balances for NAV calculation (Required for completion phase)
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            factoryStorage.pushIssuanceSnapshotToken(issuanceNonce, tokenAddress);
            
            // NOTE: Synchronous requestBuyOrder() removed for V2 Asynchronous flow.
            // The Relayer will calculate the distribution and request EIP-712 permits off-chain.

            uint256 wrappedDsharesBalance =
                IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint256 dShareBalance =
                WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            
            factoryStorage.setIssuanceTokenPrimaryBalance(issuanceNonce, tokenAddress, dShareBalance);
            uint256 amountIn = _inputAmount * functionsOracle.tokenCurrentMarketShare(tokenAddress) / 100e18;
            if (amountIn > 0) {
                factoryStorage.emitOrderIntentCreated(
                    msg.sender,
                    tokenAddress,
                    amountIn,
                    IndexFactoryStorage.OrderType.BUY,
                    issuanceNonce
                );
            }
        }

        // Snapshot total supply
        factoryStorage.setIssuanceIndexTokenPrimaryTotalSupply(
            issuanceNonce, IERC20(factoryStorage.token()).totalSupply()
        );

        // 5. Emit the Async Event for the Backend Relayer
        emit OrderIntentIssuance(issuanceNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        factoryStorage.setIssuanceState(issuanceNonce, IndexFactoryStorage.ActionState.PENDING);
        
        return issuanceNonce;
    }

    /**
     * @dev Requests the cancellation of a pending issuance (Dinari V2 Async Flow).
     * @notice This registers a cancellation intent. Funds are NOT immediately refunded here 
     * to prevent race conditions with the off-chain Relayer. The Relayer will intercept this event,
     * halt API operations, and trigger the actual refund via `completeCancelIssuance`.
     * @param _issuanceNonce The nonce of the issuance to cancel.
     */
    function cancelIssuance(uint256 _issuanceNonce) public whenNotPaused nonReentrant {
        IndexFactoryStorage.ActionState issuanceState = factoryStorage.issuanceState(_issuanceNonce);
        if (issuanceState != IndexFactoryStorage.ActionState.PENDING) {
            revert InvalidActionState(
                _issuanceNonce, IndexFactoryStorage.ActionState.PENDING, issuanceState
            );
        }
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        require(msg.sender == requester, "Only requester can cancel the issuance");
        _handleIssuanceCancellation(_issuanceNonce, requester);
    }

    /**
     * @notice Initiates an asynchronous redemption request by burning Index Tokens.
     * @dev Part of the Dinari V2 Intent-based flow. The actual asset liquidation 
     * is handled off-chain by the Relayer.
     * @param _inputAmount The amount of Index Tokens to redeem.
     * @return redemptionNonce The unique identifier (Intent ID) for this request.
     */
    function redemption(uint256 _inputAmount) public nonReentrant whenNotPaused returns (uint256) {
        require(_inputAmount > 0, "Invalid input amount");
        require(!factoryStorage.isUserActionPending(msg.sender), "User has pending action");
        
        // 1. Intent Registration
        factoryStorage.increaseRedemptionNonce();
        uint256 redemptionNonce = factoryStorage.redemptionNonce();
        IndexFactoryStorage.ActionState currentRedemptionState = factoryStorage.redemptionState(redemptionNonce);
        if (currentRedemptionState != IndexFactoryStorage.ActionState.NONE) {
            revert InvalidActionState(
                redemptionNonce, IndexFactoryStorage.ActionState.NONE, currentRedemptionState
            );
        }
        factoryStorage.setRedemptionInputAmount(redemptionNonce, _inputAmount);
        factoryStorage.setRedemptionRequesterByNonce(redemptionNonce, msg.sender);
        factoryStorage.setUserActionPending(msg.sender, true);
        factoryStorage.setUserPendingRedemptionNonce(msg.sender, redemptionNonce);

        // 2. Proportional Share Calculation
        // Determine the percentage of the total supply being burned to calculate asset distribution
        IndexToken token = factoryStorage.token();
        uint256 tokenBurnPercent = (_inputAmount * 1e18) / token.totalSupply();

        // 3. Asset Escrow (Burning)
        // Index Tokens are burned immediately to lock the user's position
        token.burn(msg.sender, _inputAmount);
        factoryStorage.setBurnedTokenAmountByNonce(redemptionNonce, _inputAmount);

        // 4. Intent Tracking & Off-chain Preparation
        

        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 wrappedBal = IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint256 amountToSell = (tokenBurnPercent * wrappedBal) / 1e18;
            if (amountToSell > 0) {
                factoryStorage.recordRedemptionEscrowSlice(redemptionNonce, tokenAddress, amountToSell);
                factoryStorage.emitOrderIntentCreated(
                    msg.sender,
                    tokenAddress,
                    amountToSell,
                    IndexFactoryStorage.OrderType.SELL,
                    redemptionNonce
                );
            }
        }

        factoryStorage.setRedemptionIntentTimestamp(redemptionNonce, block.timestamp);

        // 5. Emit Intent Event
        // Triggers the Backend Relayer to begin the asynchronous settlement process
        emit OrderIntentRedemption(
            redemptionNonce, 
            msg.sender, 
            factoryStorage.usdc(), 
            _inputAmount, 
            0, 
            block.timestamp
        );
        factoryStorage.setRedemptionState(redemptionNonce, IndexFactoryStorage.ActionState.PENDING);
        
        return redemptionNonce;
    }

    /**
     * @dev Requests the cancellation of a pending redemption (Dinari V2 Async Flow).
     * @notice Emits a cancellation intent. The Relayer will intercept this, stop any 
     * pending off-chain liquidations, and call `completeCancelRedemption` to refund the user.
     * @param _redemptionNonce The nonce of the redemption to cancel.
     */
    function cancelRedemption(uint256 _redemptionNonce) public nonReentrant whenNotPaused {
        IndexFactoryStorage.ActionState redemptionState = factoryStorage.redemptionState(_redemptionNonce);
        if (redemptionState != IndexFactoryStorage.ActionState.PENDING) {
            revert InvalidActionState(
                _redemptionNonce, IndexFactoryStorage.ActionState.PENDING, redemptionState
            );
        }
        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        require(msg.sender == requester, "Only requester can cancel the redemption");
        _handleRedemptionCancellation(_redemptionNonce, requester);
    }

    /**
     * @notice Cancels a pending issuance or redemption intent for msg.sender.
     * @dev Disambiguates by matching requester on issuance vs redemption for the same numeric nonce.
     *      Before ORDER_INTENT_TIMEOUT: sets CANCEL_REQUESTED for relayer-driven completion.
     *      After timeout with PENDING: atomically refunds escrow (USDC) or index tokens without the relayer.
     */
    function cancelOrder(uint256 intentId) external whenNotPaused nonReentrant {
        if (
            factoryStorage.issuanceState(intentId) == IndexFactoryStorage.ActionState.PENDING
                && factoryStorage.issuanceRequesterByNonce(intentId) == msg.sender
        ) {
            _handleIssuanceCancellation(intentId, msg.sender);
            return;
        }
        if (
            factoryStorage.redemptionState(intentId) == IndexFactoryStorage.ActionState.PENDING
                && factoryStorage.redemptionRequesterByNonce(intentId) == msg.sender
        ) {
            _handleRedemptionCancellation(intentId, msg.sender);
            return;
        }
        revert NoMatchingPendingIntent(intentId);
    }

    function _handleIssuanceCancellation(uint256 issuanceNonce, address requester) internal {
        if (block.timestamp > factoryStorage.issuanceIntentTimestamp(issuanceNonce) + ORDER_INTENT_TIMEOUT) {
            _atomicCancelIssuance(issuanceNonce, requester);
        } else {
            factoryStorage.setIssuanceState(issuanceNonce, IndexFactoryStorage.ActionState.CANCEL_REQUESTED);
            emit OrderIntentCancelIssuance(
                issuanceNonce,
                requester,
                factoryStorage.usdc(),
                factoryStorage.issuanceInputAmount(issuanceNonce),
                0,
                block.timestamp
            );
        }
    }

    function _handleRedemptionCancellation(uint256 redemptionNonce, address requester) internal {
        if (block.timestamp > factoryStorage.redemptionIntentTimestamp(redemptionNonce) + ORDER_INTENT_TIMEOUT) {
            _atomicCancelRedemption(redemptionNonce, requester);
        } else {
            factoryStorage.setRedemptionState(redemptionNonce, IndexFactoryStorage.ActionState.CANCEL_REQUESTED);
            emit OrderIntentCancelRedemption(
                redemptionNonce,
                requester,
                factoryStorage.usdc(),
                factoryStorage.redemptionInputAmount(redemptionNonce),
                0,
                block.timestamp
            );
        }
    }

    function _atomicCancelIssuance(uint256 issuanceNonce, address requester) internal {
        require(!factoryStorage.cancelIssuanceComplted(issuanceNonce), "Cancellation already processed");

        uint256 originalInputAmount = factoryStorage.issuanceInputAmount(issuanceNonce);
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(originalInputAmount);
        uint256 totalRefund = originalInputAmount + orderProcessorFee;
        uint256 escrow = factoryStorage.getIssuanceEscrowedUsdc(issuanceNonce);
        require(escrow > 0, "Invalid escrow");

        factoryStorage.decreasePendingIssuanceUsdc(escrow);
        factoryStorage.orderManager().releaseEscrow(factoryStorage.usdc(), requester, totalRefund);

        factoryStorage.setCancelIssuanceComplted(issuanceNonce, true);
        factoryStorage.setIssuanceState(issuanceNonce, IndexFactoryStorage.ActionState.CANCELLED);
        if (factoryStorage.tryClearUserPendingIssuanceNonce(requester, issuanceNonce)) {
            factoryStorage.setUserActionPending(requester, false);
        }
        factoryStorage.clearIssuanceSnapshot(issuanceNonce);

        emit IssuanceCancelled(
            issuanceNonce,
            requester,
            factoryStorage.usdc(),
            originalInputAmount,
            0,
            block.timestamp
        );
    }

    function _atomicCancelRedemption(uint256 redemptionNonce, address requester) internal {
        require(!factoryStorage.cancelRedemptionComplted(redemptionNonce), "The process has been completed before");

        factoryStorage.consumeRedemptionEscrowForNonce(redemptionNonce);

        IndexToken token = factoryStorage.token();
        uint256 originalBurnAmount = factoryStorage.burnedTokenAmountByNonce(redemptionNonce);
        token.mint(requester, originalBurnAmount);

        factoryStorage.setCancelRedemptionComplted(redemptionNonce, true);
        factoryStorage.setRedemptionState(redemptionNonce, IndexFactoryStorage.ActionState.CANCELLED);
        if (factoryStorage.tryClearUserPendingRedemptionNonce(requester, redemptionNonce)) {
            factoryStorage.setUserActionPending(requester, false);
        }

        emit RedemptionCancelled(
            redemptionNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.redemptionInputAmount(redemptionNonce),
            0,
            block.timestamp
        );
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOwnerOrOperatorOrBalancer {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwnerOrOperatorOrBalancer {
        _unpause();
    }

    /**
     * @notice Clears the user's pending-action lock if the relayer never completes settlement (liveness).
     * @dev Does not settle funds or change action state — only unlocks `isUserActionPending` for emergencies.
     *      Blocked while the user has an issuance or redemption in `PENDING` so escrow/NAV counters stay consistent
     *      (use `cancelOrder` after ORDER_INTENT_TIMEOUT for atomic settlement instead).
     *      Uses per-user intent pointers for O(1) gas; falls back to full scans only for legacy state where the
     *      user lock is set but pointers were never written (pre-upgrade in-flight intents).
     */
    function emergencyUnlock(address user) external onlyOwner {
        require(user != address(0), "invalid user");
        uint256 iN = factoryStorage.userPendingIssuanceNonce(user);
        uint256 rN = factoryStorage.userPendingRedemptionNonce(user);
        bool legacyLock = factoryStorage.isUserActionPending(user) && iN == 0 && rN == 0;

        if (legacyLock) {
            uint256 maxIssuance = factoryStorage.issuanceNonce();
            for (uint256 n = 1; n <= maxIssuance; n++) {
                if (
                    factoryStorage.issuanceRequesterByNonce(n) == user
                        && factoryStorage.issuanceState(n) == IndexFactoryStorage.ActionState.PENDING
                ) {
                    revert EmergencyUnlockWithPendingIntent(user);
                }
            }
            uint256 maxRedemption = factoryStorage.redemptionNonce();
            for (uint256 n = 1; n <= maxRedemption; n++) {
                if (
                    factoryStorage.redemptionRequesterByNonce(n) == user
                        && factoryStorage.redemptionState(n) == IndexFactoryStorage.ActionState.PENDING
                ) {
                    revert EmergencyUnlockWithPendingIntent(user);
                }
            }
        } else {
            if (iN != 0 && factoryStorage.issuanceState(iN) == IndexFactoryStorage.ActionState.PENDING) {
                revert EmergencyUnlockWithPendingIntent(user);
            }
            if (rN != 0 && factoryStorage.redemptionState(rN) == IndexFactoryStorage.ActionState.PENDING) {
                revert EmergencyUnlockWithPendingIntent(user);
            }
        }

        factoryStorage.clearUserPendingIntentNonces(user);
        factoryStorage.setUserActionPending(user, false);
    }
}
