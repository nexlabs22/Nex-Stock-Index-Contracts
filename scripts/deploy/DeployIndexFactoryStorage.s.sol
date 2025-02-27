// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../contracts/factory/IndexFactoryStorage.sol";

contract DeployIndexFactoryStorage is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";

        address functionsOracleProxy;
        address issuer;
        address indexTokenProxy;
        address nexVaultProxy;
        address usdc;
        uint8 usdcDecimals;

        bool isMainnet;

        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            issuer = vm.envAddress("SEPOLIA_ISSUER_ADDRESS");
            indexTokenProxy = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
            nexVaultProxy = vm.envAddress("SEPOLIA_VAULT_PROXY_ADDRESS");
            usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            isMainnet = false;
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            issuer = vm.envAddress("ARBITRUM_ISSUER_ADDRESS");
            indexTokenProxy = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADDRESS");
            nexVaultProxy = vm.envAddress("ARBITRUM_VAULT_PROXY_ADDRESS");
            usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            isMainnet = true;
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "IndexFactoryStorage.sol",
            owner,
            abi.encodeCall(
                IndexFactoryStorage.initialize,
                (issuer, indexTokenProxy, nexVaultProxy, usdc, usdcDecimals, functionsOracleProxy, isMainnet)
            )
        );

        IndexFactoryStorage indexFactoryStorageImplementation = IndexFactoryStorage(proxy);

        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("IndexFactoryStorage implementation deployed at:", address(indexFactoryStorageImplementation));
        console.log("IndexFactoryStorage proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for IndexFactoryStorage deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}
