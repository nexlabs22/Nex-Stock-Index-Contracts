// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IndexFactory} from "../../../../contracts/factory/IndexFactory.sol";

contract UpgradeIndexFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address proxyAdminAddress;
        address indexFactoryProxyAddress;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAdminAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADMIN_ADDRESS");
            indexFactoryProxyAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAdminAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADMIN_ADDRESS");
            indexFactoryProxyAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        IndexFactory newIndexFactoryImplementation = new IndexFactory();
        console.log("New IndexFactory implementation deployed at:", address(newIndexFactoryImplementation));

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(indexFactoryProxyAddress)), address(newIndexFactoryImplementation)
        );

        console.log("IndexFactory proxy upgraded to new implementation at:", address(newIndexFactoryImplementation));

        vm.stopBroadcast();
    }
}
