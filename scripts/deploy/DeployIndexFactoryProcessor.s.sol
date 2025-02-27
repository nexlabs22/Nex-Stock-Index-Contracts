// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../contracts/factory/IndexFactoryProcessor.sol";

contract DeployIndexFactoryProcessor is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory targetChain = "sepolia";
        // string memory targetChain = "arbitrum_mainnet";

        address indexFactoryStorageProxy;
        address functionOracleProxy;

        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            functionOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            functionOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);
        address proxy = Upgrades.deployTransparentProxy(
            "IndexFactoryProcessor.sol",
            owner,
            abi.encodeCall(IndexFactoryProcessor.initialize, (indexFactoryStorageProxy, functionOracleProxy))
        );

        IndexFactoryProcessor indexFactoryProcessorImplementation = IndexFactoryProcessor(proxy);

        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("IndexFactoryProcessor implementation deployed at:", address(indexFactoryProcessorImplementation));
        console.log("IndexFactoryProcessor proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for IndexFactoryProcessor deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}
