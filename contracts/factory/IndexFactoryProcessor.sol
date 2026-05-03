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
import "./OrderManager.sol";
import "./FunctionsOracle.sol";

/// @title Index Token Factory Processor
/// @author NEX Labs Protocol
/// @notice Handles the completion of asynchronous (Intent-based) issuance and redemption flows.
contract IndexFactoryProcessor is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    
    error InvalidActionState(
        uint256 nonce,
        IndexFactoryStorage.ActionState expected,
        IndexFactoryStorage.ActionState actual
    );

    error ZeroIssuanceMint(uint256 issuanceNonce);

    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    event Issuanced(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 price,
        uint256 time
    );

    event IssuanceCancelled(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event Redemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 price,
        uint256 time
    );

    event RedemptionCancelled(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    /**
     * @dev Restricts access to the authorized Relayer (Operator) or Owner.
     * Crucial for the V2 Async flow since the Relayer passes the settlement amounts.
     */
    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender),
            "Caller is not the owner or operator."
        );
        _;
    }

    function initialize(address _factoryStorage, address _functionsOracle) external initializer {
        require(_factoryStorage != address(0), "invalid factory storage address");
        require(_functionsOracle != address(0), "invalid functions oracle address");
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

    function setFunctionsOracle(address _functionsOracle) external onlyOwner returns (bool) {
        require(_functionsOracle != address(0), "invalid functions oracle address");
        functionsOracle = FunctionsOracle(_functionsOracle);
        return true;
    }

    function setIndexFactoryStorage(address _factoryStorage) external onlyOwner returns (bool) {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        return true;
    }

    function _issuanceConstituentAt(uint256 issuanceNonce, uint256 i, uint256 snapLen) private view returns (address) {
        if (snapLen > 0) {
            return factoryStorage.issuanceSnapshotTokenAt(issuanceNonce, i);
        }
        return functionsOracle.currentList(i);
    }

    function _applyIssuanceReceivedForToken(
        uint256 issuanceNonce,
        address tokenAddress,
        uint256 balance,
        OrderManager orderManager
    ) private returns (uint256 primaryValue, uint256 secondaryValue) {
        uint256 price = factoryStorage.priceInWei(tokenAddress);
        uint256 receivedValue = balance * price / 1e18;
        uint256 primaryBalance = factoryStorage.issuanceTokenPrimaryBalance(issuanceNonce, tokenAddress);
        primaryValue = primaryBalance * price / 1e18;
        secondaryValue = primaryValue + receivedValue;
        if (balance > 0) {
            orderManager.withdrawFunds(tokenAddress, address(this), balance);
            IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), balance);
            WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(
                balance, address(factoryStorage.vault())
            );
        }
    }

    function _completeIssuanceAccumulatePortfolios(
        uint256 issuanceNonce,
        uint256[] calldata _receivedAmounts,
        uint256 snapLen
    ) private returns (uint256 primaryPortfolioValue, uint256 secondaryPortfolioValue) {
        uint256 listLen = snapLen > 0 ? snapLen : functionsOracle.totalCurrentList();
        require(_receivedAmounts.length == listLen, "Amounts array length mismatch");
        OrderManager orderManager = factoryStorage.orderManager();
        for (uint256 i; i < listLen; i++) {
            address tokenAddress = _issuanceConstituentAt(issuanceNonce, i, snapLen);
            (uint256 pv, uint256 sv) =
                _applyIssuanceReceivedForToken(issuanceNonce, tokenAddress, _receivedAmounts[i], orderManager);
            primaryPortfolioValue += pv;
            secondaryPortfolioValue += sv;
        }
    }

    function _finalizeIssuanceMintAndState(
        uint256 issuanceNonce,
        address requester,
        uint256 primaryPortfolioValue,
        uint256 secondaryPortfolioValue
    ) private {
        uint256 primaryTotalSupply = factoryStorage.issuanceIndexTokenPrimaryTotalSupply(issuanceNonce);
        uint256 mintAmount;

        if (primaryTotalSupply == 0 || primaryPortfolioValue == 0) {
            mintAmount = secondaryPortfolioValue / 100;
        } else {
            uint256 secondaryTotalSupply = primaryTotalSupply * secondaryPortfolioValue / primaryPortfolioValue;
            mintAmount = secondaryTotalSupply - primaryTotalSupply;
        }

        if (mintAmount == 0) {
            revert ZeroIssuanceMint(issuanceNonce);
        }

        IndexToken token = factoryStorage.token();
        token.mint(requester, mintAmount);

        emit Issuanced(
            issuanceNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.issuanceInputAmount(issuanceNonce),
            mintAmount,
            factoryStorage.getIndexTokenPrice(),
            block.timestamp
        );

        uint256 issuanceEscrow = factoryStorage.getIssuanceEscrowedUsdc(issuanceNonce);
        if (issuanceEscrow > 0) {
            factoryStorage.decreasePendingIssuanceUsdc(issuanceEscrow);
        }

        factoryStorage.setIssuanceState(issuanceNonce, IndexFactoryStorage.ActionState.COMPLETED);
        if (factoryStorage.tryClearUserPendingIssuanceNonce(requester, issuanceNonce)) {
            factoryStorage.setUserActionPending(requester, false);
        }
        factoryStorage.clearIssuanceSnapshot(issuanceNonce);
    }

    /**
     * @dev Completes the asynchronous issuance flow. Called by the off-chain Relayer.
     */
    function completeIssuance(uint256 _issuanceNonce, uint256[] calldata _receivedAmounts) public nonReentrant whenNotPaused onlyOwnerOrOperator {
        IndexFactoryStorage.ActionState issuanceState = factoryStorage.issuanceState(_issuanceNonce);
        if (issuanceState != IndexFactoryStorage.ActionState.PENDING) {
            revert InvalidActionState(
                _issuanceNonce, IndexFactoryStorage.ActionState.PENDING, issuanceState
            );
        }
        uint256 snapLen = factoryStorage.issuanceSnapshotLength(_issuanceNonce);
        (uint256 primaryPortfolioValue, uint256 secondaryPortfolioValue) =
            _completeIssuanceAccumulatePortfolios(_issuanceNonce, _receivedAmounts, snapLen);
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        _finalizeIssuanceMintAndState(
            _issuanceNonce, requester, primaryPortfolioValue, secondaryPortfolioValue
        );
    }

    /**
     * @notice Processes an issuance cancellation and refunds the user's USDC from escrow.
     * @dev The refund includes the principal and the order processor fee, while the protocol fee remains in the treasury.
     * @param _issuanceNonce The unique identifier of the issuance request to cancel.
     */
    function completeCancelIssuance(uint256 _issuanceNonce) public nonReentrant whenNotPaused onlyOwnerOrOperator {
        IndexFactoryStorage.ActionState issuanceState = factoryStorage.issuanceState(_issuanceNonce);
        if (issuanceState != IndexFactoryStorage.ActionState.CANCEL_REQUESTED) {
            revert InvalidActionState(
                _issuanceNonce, IndexFactoryStorage.ActionState.CANCEL_REQUESTED, issuanceState
            );
        }
        require(!factoryStorage.cancelIssuanceComplted(_issuanceNonce), "Cancellation already processed");
        
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        
        uint256 originalInputAmount = factoryStorage.issuanceInputAmount(_issuanceNonce);
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(originalInputAmount);
        
        // REFUND LOGIC: Returns the principal amount plus the external order processor fee. 
        // The protocol fee is retained in the treasury as it was already collected during initiation.
        uint256 totalRefund = originalInputAmount + orderProcessorFee;

        OrderManager orderManager = factoryStorage.orderManager();
        orderManager.withdrawFunds(factoryStorage.usdc(), requester, totalRefund);

        uint256 issuanceEscrow = factoryStorage.getIssuanceEscrowedUsdc(_issuanceNonce);
        if (issuanceEscrow > 0) {
            factoryStorage.decreasePendingIssuanceUsdc(issuanceEscrow);
        }

        factoryStorage.setCancelIssuanceComplted(_issuanceNonce, true);
        factoryStorage.setIssuanceState(_issuanceNonce, IndexFactoryStorage.ActionState.CANCELLED);
        if (factoryStorage.tryClearUserPendingIssuanceNonce(requester, _issuanceNonce)) {
            factoryStorage.setUserActionPending(requester, false);
        }
        factoryStorage.clearIssuanceSnapshot(_issuanceNonce);
        
        emit IssuanceCancelled(
            _issuanceNonce,
            requester,
            factoryStorage.usdc(),
            originalInputAmount,
            0,
            block.timestamp
        );
    }

    /**
     * @dev Completes the asynchronous redemption flow. Called by the off-chain Relayer.
     * @param _redemptionNonce The intent ID being settled.
     * @param _totalUsdcReceived The total USDC amount obtained from liquidating the dShares.
     */
    function completeRedemption(uint256 _redemptionNonce, uint256 _totalUsdcReceived) public nonReentrant whenNotPaused onlyOwnerOrOperator {
        IndexFactoryStorage.ActionState redemptionState = factoryStorage.redemptionState(_redemptionNonce);
        if (redemptionState != IndexFactoryStorage.ActionState.PENDING) {
            revert InvalidActionState(
                _redemptionNonce, IndexFactoryStorage.ActionState.PENDING, redemptionState
            );
        }
        
        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        
        // Calculate protocol fee from the total USDC liquidated by the Relayer
        uint256 fee = (_totalUsdcReceived * factoryStorage.feeRate()) / 10000;
        OrderManager orderManager = factoryStorage.orderManager();
        
        if (fee > 0) {
            orderManager.withdrawFunds(factoryStorage.usdc(), factoryStorage.feeReceiver(), fee);
        }
        
        // Transfer the remaining USDC to the user
        uint256 netUserAmount = _totalUsdcReceived - fee;
        if (netUserAmount > 0) {
            orderManager.withdrawFunds(factoryStorage.usdc(), requester, netUserAmount);
        }

        factoryStorage.consumeRedemptionEscrowForNonce(_redemptionNonce);

        factoryStorage.setRedemptionState(_redemptionNonce, IndexFactoryStorage.ActionState.COMPLETED);
        
        emit Redemption(
            _redemptionNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.redemptionInputAmount(_redemptionNonce),
            netUserAmount,
            factoryStorage.getIndexTokenPrice(),
            block.timestamp
        );
        if (factoryStorage.tryClearUserPendingRedemptionNonce(requester, _redemptionNonce)) {
            factoryStorage.setUserActionPending(requester, false);
        }
    }

    /**
     * @dev Processes a redemption cancellation, refunding the user by re-minting their burned Index Tokens.
     */
    function completeCancelRedemption(uint256 _redemptionNonce) public nonReentrant whenNotPaused onlyOwnerOrOperator {
        IndexFactoryStorage.ActionState redemptionState = factoryStorage.redemptionState(_redemptionNonce);
        if (redemptionState != IndexFactoryStorage.ActionState.CANCEL_REQUESTED) {
            revert InvalidActionState(
                _redemptionNonce, IndexFactoryStorage.ActionState.CANCEL_REQUESTED, redemptionState
            );
        }
        require(!factoryStorage.cancelRedemptionComplted(_redemptionNonce), "The process has been completed before");

        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);

        factoryStorage.consumeRedemptionEscrowForNonce(_redemptionNonce);

        // Re-mint the exact amount of Index Tokens that were burned in the Escrow phase
        IndexToken token = factoryStorage.token();
        uint256 originalBurnAmount = factoryStorage.burnedTokenAmountByNonce(_redemptionNonce);
        token.mint(requester, originalBurnAmount);
        
        factoryStorage.setCancelRedemptionComplted(_redemptionNonce, true);
        factoryStorage.setRedemptionState(_redemptionNonce, IndexFactoryStorage.ActionState.CANCELLED);
        if (factoryStorage.tryClearUserPendingRedemptionNonce(requester, _redemptionNonce)) {
            factoryStorage.setUserActionPending(requester, false);
        }
        
        emit RedemptionCancelled(
            _redemptionNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.redemptionInputAmount(_redemptionNonce),
            0,
            block.timestamp
        );
    }
}
