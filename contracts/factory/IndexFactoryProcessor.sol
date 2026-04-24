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
import "./OrderManager.sol";
import "./FunctionsOracle.sol";

/// @title Index Token Factory Processor
/// @author NEX Labs Protocol
/// @notice Handles the completion of asynchronous (Intent-based) issuance and redemption flows.
contract IndexFactoryProcessor is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
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

    /**
     * @dev Completes the asynchronous issuance flow. Called by the off-chain Relayer.
     */
    function completeIssuance(uint256 _issuanceNonce, uint256[] calldata _receivedAmounts) public nonReentrant whenNotPaused onlyOwnerOrOperator {
        require(!factoryStorage.issuanceIsCompleted(_issuanceNonce), "Issuance is completed");
        require(_receivedAmounts.length == functionsOracle.totalCurrentList(), "Amounts array length mismatch");
        
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        uint256 primaryPortfolioValue;
        uint256 secondaryPortfolioValue;

        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 price = factoryStorage.priceInWei(tokenAddress);
            
            uint256 balance = _receivedAmounts[i];
            uint256 receivedValue = balance * price / 1e18;
            
            uint256 primaryBalance = factoryStorage.issuanceTokenPrimaryBalance(_issuanceNonce, tokenAddress);
            uint256 primaryValue = primaryBalance * price / 1e18;
            uint256 secondaryValue = primaryValue + receivedValue;
            
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;

            if (balance > 0) {
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.withdrawFunds(tokenAddress, address(this), balance);
                IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), balance);
                WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(
                    balance, address(factoryStorage.vault())
                );
            }
        }

        uint256 primaryTotalSupply = factoryStorage.issuanceIndexTokenPrimaryTotalSupply(_issuanceNonce);
        uint256 mintAmount;

        if (primaryTotalSupply == 0 || primaryPortfolioValue == 0) {
            mintAmount = secondaryPortfolioValue / 100;
        } else {
            uint256 secondaryTotalSupply = primaryTotalSupply * secondaryPortfolioValue / primaryPortfolioValue;
            mintAmount = secondaryTotalSupply - primaryTotalSupply;
        }

        // Ensure mintAmount is non-zero to prevent redundant execution or reverts during settlement
        if (mintAmount > 0) {
            IndexToken token = factoryStorage.token();
            token.mint(requester, mintAmount);
        }
        
        emit Issuanced(
            _issuanceNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.issuanceInputAmount(_issuanceNonce),
            mintAmount,
            factoryStorage.getIndexTokenPrice(),
            block.timestamp
        );
        
        factoryStorage.setIssuanceIsCompleted(_issuanceNonce, true);
    }

    /**
     * @notice Processes an issuance cancellation and refunds the user's USDC from escrow.
     * @dev The refund includes the principal and the order processor fee, while the protocol fee remains in the treasury.
     * @param _issuanceNonce The unique identifier of the issuance request to cancel.
     */
    function completeCancelIssuance(uint256 _issuanceNonce) public nonReentrant whenNotPaused onlyOwnerOrOperator {
        require(!factoryStorage.cancelIssuanceComplted(_issuanceNonce), "Cancellation already processed");
        
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        
        uint256 originalInputAmount = factoryStorage.issuanceInputAmount(_issuanceNonce);
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(originalInputAmount);
        
        // REFUND LOGIC: Returns the principal amount plus the external order processor fee. 
        // The protocol fee is retained in the treasury as it was already collected during initiation.
        uint256 totalRefund = originalInputAmount + orderProcessorFee;

        OrderManager orderManager = factoryStorage.orderManager();
        orderManager.withdrawFunds(factoryStorage.usdc(), requester, totalRefund);
        
        factoryStorage.setCancelIssuanceComplted(_issuanceNonce, true);
        
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
        require(!factoryStorage.redemptionIsCompleted(_redemptionNonce), "Redemption is completed");
        
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
        
        factoryStorage.setRedemptionIsCompleted(_redemptionNonce, true);
        
        emit Redemption(
            _redemptionNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.redemptionInputAmount(_redemptionNonce),
            netUserAmount,
            factoryStorage.getIndexTokenPrice(),
            block.timestamp
        );
    }

    /**
     * @dev Processes a redemption cancellation, refunding the user by re-minting their burned Index Tokens.
     */
    function completeCancelRedemption(uint256 _redemptionNonce) public nonReentrant whenNotPaused onlyOwnerOrOperator {
        require(!factoryStorage.cancelRedemptionComplted(_redemptionNonce), "The process has been completed before");

        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        
        // Re-mint the exact amount of Index Tokens that were burned in the Escrow phase
        IndexToken token = factoryStorage.token();
        uint256 originalBurnAmount = factoryStorage.burnedTokenAmountByNonce(_redemptionNonce);
        token.mint(requester, originalBurnAmount);
        
        factoryStorage.setCancelRedemptionComplted(_redemptionNonce, true);
        
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
