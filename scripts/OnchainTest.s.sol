// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {IndexFactory} from "../../contracts/factory/IndexFactory.sol";
import "../../contracts/token/IndexToken.sol";
import "../../contracts/factory/IndexFactoryProcessor.sol";
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

    function completeIssunace() public {
        IndexFactoryProcessor(factoryProcessor).completeIssuance(2);
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
