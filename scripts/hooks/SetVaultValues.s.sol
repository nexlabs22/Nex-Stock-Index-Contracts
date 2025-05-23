// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import "../../contracts/vault/NexVault.sol";

contract SetVaultValues is Script {
    address indexFactoryProxy;
    address vaultProxy;
    address factoryProcessor;
    address indexFactoryBalancerProxy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory targetChain = "sepolia";
        // string memory targetChain = "arbitrum_mainnet";

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
            vaultProxy = vm.envAddress("SEPOLIA_VAULT_PROXY_ADDRESS");
            factoryProcessor = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROCESSOR_PROXY_ADMIN_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
            vaultProxy = vm.envAddress("ARBITRUM_VAULT_PROXY_ADDRESS");
            factoryProcessor = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        NexVault(vaultProxy).setOperator(indexFactoryProxy, true);
        NexVault(vaultProxy).setOperator(indexFactoryBalancerProxy, true);
        NexVault(vaultProxy).setOperator(factoryProcessor, true);

        vm.stopBroadcast();
    }
}
