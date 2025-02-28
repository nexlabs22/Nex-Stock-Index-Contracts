// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../contracts/factory/IndexFactoryStorage.sol";

contract DeployIndexFactoryStorage is Script {
    struct ChainVars {
        address functionsOracleProxy;
        address issuer;
        address indexTokenProxy;
        address nexVaultProxy;
        address usdc;
        uint8 usdcDecimals;
        bool isMainnet;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";

        ChainVars memory vars = _getChainVars(targetChain);

        address owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "IndexFactoryStorage.sol",
            owner,
            abi.encodeCall(
                IndexFactoryStorage.initialize,
                (
                    vars.issuer,
                    vars.indexTokenProxy,
                    vars.nexVaultProxy,
                    vars.usdc,
                    vars.usdcDecimals,
                    vars.functionsOracleProxy,
                    vars.isMainnet
                )
            )
        );

        IndexFactoryStorage indexFactoryStorageImplementation = IndexFactoryStorage(proxy);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("IndexFactoryStorage implementation deployed at:", address(indexFactoryStorageImplementation));
        console.log("IndexFactoryStorage proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for IndexFactoryStorage deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }

    function _getChainVars(string memory targetChain) internal view returns (ChainVars memory) {
        ChainVars memory vars;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            vars.functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            vars.issuer = vm.envAddress("SEPOLIA_ISSUER_ADDRESS");
            vars.indexTokenProxy = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
            vars.nexVaultProxy = vm.envAddress("SEPOLIA_VAULT_PROXY_ADDRESS");
            vars.usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            vars.usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            vars.isMainnet = false;
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            vars.functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            vars.issuer = vm.envAddress("ARBITRUM_ISSUER_ADDRESS");
            vars.indexTokenProxy = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADDRESS");
            vars.nexVaultProxy = vm.envAddress("ARBITRUM_VAULT_PROXY_ADDRESS");
            vars.usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            vars.usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            vars.isMainnet = true;
        } else {
            revert("Unsupported target chain");
        }

        return vars;
    }
}
