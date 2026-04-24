// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {IndexFactory} from "../contracts/factory/IndexFactory.sol";
import "../contracts/token/IndexToken.sol";
import "../contracts/factory/IndexFactoryProcessor.sol";
import "../contracts/factory/IndexFactoryBalancer.sol";
import "../contracts/factory/IndexFactoryStorage.sol";

contract OnchainTest is Script {
    IndexToken indexToken;

    address user = vm.envAddress("USER");
    address usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
    address indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
    address indexTokenProxy = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
    address factoryProcessor = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
    address indexFactoryBalancerProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
    address indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");

    // address usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
    // address indexFactoryProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
    // address indexTokenProxy = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADDRESS");
    // address factoryProcessor = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
    // address indexFactoryBalancerProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
    // address indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        indexToken = IndexToken(payable(indexTokenProxy));

        // string memory targetChain = "sepolia";

        issuanceIndexTokensWithUSDC();

        // completeIssunace();

        // redemption();

        // firstRebalance();

        // secondRebalance();

        // completeRebalance();

        vm.stopBroadcast();
    }

    function redemption() public {
        IndexFactory(payable(indexFactoryProxy)).redemption(IERC20(indexTokenProxy).balanceOf(user));
    }

    function issuanceIndexTokensWithUSDC() public {
        // Testnet
        uint256 inputAmount = 100e6;
        uint256 feeAmount = IndexFactoryStorage(indexFactoryStorageProxy).calculateIssuanceFee(inputAmount);
        uint256 quantityIn = feeAmount + inputAmount + (inputAmount * 10) / 10000;

        // Mainnet
        // uint256 inputAmount = 25e6;
        // uint256 feeAmount = IndexFactoryStorage(indexFactoryStorageProxy).calculateIssuanceFee(inputAmount);
        // uint256 quantityIn = feeAmount + inputAmount + (inputAmount * 10) / 10000;

        IERC20(usdc).approve(indexFactoryProxy, quantityIn);
        IndexFactory(payable(indexFactoryProxy)).issuanceIndexTokens(inputAmount);
        // IndexFactory(payable(indexFactoryProxy)).issuanceIndexTokens(100e6);
    }

    /**
     * @notice Completes an issuance order by providing actual dShare amounts received from Dinari.
     * @dev Used by the Relayer to settle the index token minting after off-chain execution.
     * @param _nonce Unique intent ID for the issuance request.
     */
    function completeIssunace(uint256 _nonce) public {
        // Mocking received amounts for the 10 assets in the index.
        // In production, these values must match the actual shares bought.
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            amounts[i] = 10e18; 
        }

        IndexFactoryProcessor(factoryProcessor).completeIssuance(_nonce, amounts);
    }

    /**
     * @notice Completes a redemption order by providing total USDC recovered from asset liquidation.
     * @dev Finalizes the exit flow by releasing escrowed USDC to the requester.
     * @param _nonce Unique intent ID for the redemption request.
     * @param _totalUsdcReceived The actual USDC amount returned by the provider.
     */
    function completeRedemption(uint256 _nonce, uint256 _totalUsdcReceived) public {
        IndexFactoryProcessor(factoryProcessor).completeRedemption(_nonce, _totalUsdcReceived);
    }

    /**
     * @notice Reverts a pending issuance and refunds the escrowed USDC back to the user.
     * @dev Triggered if the off-chain execution fails or is rejected by the provider.
     */
    function completeCancelIssuance(uint256 _nonce) public {
        IndexFactoryProcessor(factoryProcessor).completeCancelIssuance(_nonce);
    }

    /**
     * @notice Reverts a pending redemption and restores the user's index token balance.
     * @dev Mints back the previously burned tokens if liquidation fails.
     */
    function completeCancelRedemption(uint256 _nonce) public {
        IndexFactoryProcessor(factoryProcessor).completeCancelRedemption(_nonce);
    }

    // function firstRebalance() public {
    //     IndexFactoryBalancer(indexFactoryBalancerProxy).firstRebalanceAction();
    // }

    // function secondRebalance() public {
    //     IndexFactoryBalancer(indexFactoryBalancerProxy).secondRebalanceAction(1);
    // }

    // function completeRebalance() public {
    //     IndexFactoryBalancer(indexFactoryBalancerProxy).completeRebalanceActions(1);
    // }
}
