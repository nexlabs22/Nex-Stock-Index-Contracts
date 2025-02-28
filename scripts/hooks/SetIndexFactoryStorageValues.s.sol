// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import "../../../../contracts/factory/IndexFactoryStorage.sol";

contract SetIndexFactoryStorageValues is Script {
    address indexFactoryStorageProxy;
    address indexFactoryProxy;
    address vaultProxy;
    address indexFactoryBalancerProxy;
    address orderManagerProxy;
    address factoryProcessorProxy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory targetChain = "sepolia";
        // string memory targetChain = "arbitrum_mainnet";

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
            vaultProxy = vm.envAddress("SEPOLIA_VAULT_PROXY_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            orderManagerProxy = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
            factoryProcessorProxy = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            indexFactoryProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
            vaultProxy = vm.envAddress("ARBITRUM_VAULT_PROXY_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            orderManagerProxy = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
            factoryProcessorProxy = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        IndexFactoryStorage(indexFactoryStorageProxy).setOrderManager(orderManagerProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactory(indexFactoryProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactoryProcessor(factoryProcessorProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactoryBalancer(indexFactoryBalancerProxy);

        setWrappedDShares(targetChain);

        vm.stopBroadcast();
    }

    function setWrappedDShares(string memory targetChain) public {
        address[] memory dShares = new address[](7);
        address[] memory wrappedDshares = new address[](7);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            dShares[0] = vm.envAddress("SEPOLIA_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("SEPOLIA_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("SEPOLIA_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("SEPOLIA_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("SEPOLIA_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("SEPOLIA_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("SEPOLIA_TSLA_DSHARE_ADDRESS");
            wrappedDshares[0] = vm.envAddress("SEPOLIA_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[1] = vm.envAddress("SEPOLIA_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[2] = vm.envAddress("SEPOLIA_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[3] = vm.envAddress("SEPOLIA_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[4] = vm.envAddress("SEPOLIA_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[5] = vm.envAddress("SEPOLIA_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[6] = vm.envAddress("SEPOLIA_TSLA_WRAPPED_DSHARE_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            dShares[0] = vm.envAddress("ARBITRUM_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("ARBITRUM_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("ARBITRUM_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("ARBITRUM_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("ARBITRUM_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("ARBITRUM_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("ARBITRUM_TSLA_DSHARE_ADDRESS");
            wrappedDshares[0] = vm.envAddress("ARBITRUM_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[1] = vm.envAddress("ARBITRUM_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[2] = vm.envAddress("ARBITRUM_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[3] = vm.envAddress("ARBITRUM_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[4] = vm.envAddress("ARBITRUM_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[5] = vm.envAddress("ARBITRUM_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[6] = vm.envAddress("ARBITRUM_TSLA_WRAPPED_DSHARE_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        IndexFactoryStorage(indexFactoryStorageProxy).setWrappedDShareAddresses(dShares, wrappedDshares);
    }
}
