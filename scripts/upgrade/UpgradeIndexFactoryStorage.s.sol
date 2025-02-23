// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IndexFactoryStorage} from "../../../../contracts/factory/IndexFactoryStorage.sol";

contract UpgradeIndexFactoryStorage is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address proxyAdminAddress;
        address indexFactoryStorageProxyAddress;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAdminAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADMIN_ADDRESS");
            indexFactoryStorageProxyAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAdminAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADMIN_ADDRESS");
            indexFactoryStorageProxyAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        IndexFactoryStorage newIndexFactoryStorageImplementation = new IndexFactoryStorage();
        console.log(
            "New IndexFactoryStorage implementation deployed at:", address(newIndexFactoryStorageImplementation)
        );

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(indexFactoryStorageProxyAddress)),
            address(newIndexFactoryStorageImplementation),
            ""
        );

        console.log(
            "IndexFactoryStorage proxy upgraded to new implementation at:",
            address(newIndexFactoryStorageImplementation)
        );

        vm.stopBroadcast();
    }
}
