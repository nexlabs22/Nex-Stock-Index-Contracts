// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IndexFactoryBalancer} from "../../../../contracts/factory/IndexFactoryBalancer.sol";

contract UpgradeIndexFactoryBalancer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address deployer = vm.addr(deployerPrivateKey);

        address indexFactoryStorageProxy;
        address functionsOracleProxy;

        address proxyAdminAddress;
        address indexFactoryBalancerProxyAddress;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAdminAddress = 0x274F17Ad5b14F4e69b9e383b83904D09775252aE;
            indexFactoryBalancerProxyAddress = 0x64426341EFe86044666b6F3FA49f17896bA3b910;
            // proxyAdminAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADMIN_ADDRESS");
            // indexFactoryBalancerProxyAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAdminAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADMIN_ADDRESS");
            indexFactoryBalancerProxyAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        IndexFactoryBalancer newIndexFactoryBalanacerImplementation = new IndexFactoryBalancer();
        console.log(
            "New IndexFactoryBalancer implementation deployed at:", address(newIndexFactoryBalanacerImplementation)
        );

        bytes memory data =
            abi.encodeWithSignature("initialize(address,address)", indexFactoryStorageProxy, functionsOracleProxy);

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(indexFactoryBalancerProxyAddress),
            address(newIndexFactoryBalanacerImplementation),
            // deployer,
            data
        );
        // bytes("")
        // bytes("")

        console.log(
            "IndexFactoryBalancer proxy upgraded to new implementation at:",
            address(newIndexFactoryBalanacerImplementation)
        );

        vm.stopBroadcast();
    }
}
