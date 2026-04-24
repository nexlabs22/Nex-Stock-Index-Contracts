// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {FeeLib} from "../dinary/common/FeeLib.sol";
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

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    event RequestIssuance(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestCancelIssuance(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestRedemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestCancelRedemption(
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
        factoryStorage.setIssuanceInputAmount(issuanceNonce, _inputAmount);
        factoryStorage.setIssuanceRequesterByNonce(issuanceNonce, msg.sender);

        // 4. Record Pre-Issuance Balances for NAV calculation (Required for completion phase)
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            
            // NOTE: Synchronous requestBuyOrder() removed for V2 Asynchronous flow.
            // The Relayer will calculate the distribution and request EIP-712 permits off-chain.

            uint256 wrappedDsharesBalance =
                IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint256 dShareBalance =
                WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            
            factoryStorage.setIssuanceTokenPrimaryBalance(issuanceNonce, tokenAddress, dShareBalance);
        }

        // Snapshot total supply
        factoryStorage.setIssuanceIndexTokenPrimaryTotalSupply(
            issuanceNonce, IERC20(factoryStorage.token()).totalSupply()
        );

        // 5. Emit the Async Event for the Backend Relayer
        emit RequestIssuance(issuanceNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        
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
        require(!factoryStorage.issuanceIsCompleted(_issuanceNonce), "Issuance is completed");
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        require(msg.sender == requester, "Only requester can cancel the issuance");

        // Completely remove the synchronous loop checking IOrderProcessor.OrderStatus.
        // In V2, requestIds are handled off-chain. Just emit the intent to cancel.

        emit RequestCancelIssuance(
            _issuanceNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.issuanceInputAmount(_issuanceNonce),
            0,
            block.timestamp
        );
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
        
        // 1. Intent Registration
        factoryStorage.increaseRedemptionNonce();
        uint256 redemptionNonce = factoryStorage.redemptionNonce();
        factoryStorage.setRedemptionInputAmount(redemptionNonce, _inputAmount);
        factoryStorage.setRedemptionRequesterByNonce(redemptionNonce, msg.sender);

        // 2. Proportional Share Calculation
        // Determine the percentage of the total supply being burned to calculate asset distribution
        IndexToken token = factoryStorage.token();
        // uint256 tokenBurnPercent = (_inputAmount * 1e18) / token.totalSupply();

        // 3. Asset Escrow (Burning)
        // Index Tokens are burned immediately to lock the user's position
        token.burn(msg.sender, _inputAmount);
        factoryStorage.setBurnedTokenAmountByNonce(redemptionNonce, _inputAmount);

        // 4. Intent Tracking & Off-chain Preparation
        

        /* * OFF-CHAIN SETTLEMENT REFERENCE (DEPRECATED ON-CHAIN)
         * -----------------------------------------------------------
         * The following logic is kept as a reference for Relayer development.
         * To optimize gas, this loop is not executed on-chain.
         * * FUTURE RELAYER IMPLEMENTATION PATHS:
         * Path A: The Relayer independently calculates asset liquidation amounts off-chain.
         * Path B: If on-chain verification is required, this loop should be re-activated 
         * and the 'amountToSell' must be persisted via Events or Storage.
         *
         * for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
         * address tokenAddress = functionsOracle.currentList(i);
         * uint256 amountToSell = (tokenBurnPercent * IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()))) / 1e18;
         * }
         */

        // 5. Emit Intent Event
        // Triggers the Backend Relayer to begin the asynchronous settlement process
        emit RequestRedemption(
            redemptionNonce, 
            msg.sender, 
            factoryStorage.usdc(), 
            _inputAmount, 
            0, 
            block.timestamp
        );
        
        return redemptionNonce;
    }

    /**
     * @dev Requests the cancellation of a pending redemption (Dinari V2 Async Flow).
     * @notice Emits a cancellation intent. The Relayer will intercept this, stop any 
     * pending off-chain liquidations, and call `completeCancelRedemption` to refund the user.
     * @param _redemptionNonce The nonce of the redemption to cancel.
     */
    function cancelRedemption(uint256 _redemptionNonce) public nonReentrant whenNotPaused {
        require(!factoryStorage.redemptionIsCompleted(_redemptionNonce), "Redemption is completed");
        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        require(msg.sender == requester, "Only requester can cancel the redemption");

        // Synchronous order status checks and _cancelExecutedRedemption calls are removed.
        // The Relayer evaluates the exact state off-chain and reconciles the balances.

        emit RequestCancelRedemption(
            _redemptionNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.redemptionInputAmount(_redemptionNonce),
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
}
