// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/factory/IndexFactoryProcessor.sol";

contract UpgradeIndexFactoryProcessor is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address proxyAdminAddress;
        address indexFactoryProcessorProxyAddress;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAdminAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROCESSOR_PROXY_ADMIN_ADDRESS");
            indexFactoryProcessorProxyAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAdminAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROCESSOR_PROXY_ADMIN_ADDRESS");
            indexFactoryProcessorProxyAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        IndexFactoryProcessor newIndexFactoryProcessorImplementation = new IndexFactoryProcessor();
        console.log(
            "New IndexFactoryProcessor implementation deployed at:", address(newIndexFactoryProcessorImplementation)
        );

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(indexFactoryProcessorProxyAddress)),
            address(newIndexFactoryProcessorImplementation)
        );

        console.log(
            "IndexFactoryProcessor proxy upgraded to new implementation at:",
            address(newIndexFactoryProcessorImplementation)
        );

        vm.stopBroadcast();
    }
}
