// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/vault/NexVault.sol";

contract UpgradeVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address proxyAdminAddress;
        address vaultProxyAddress;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAdminAddress = vm.envAddress("SEPOLIA_VAULT_PROXY_ADMIN_ADDRESS");
            vaultProxyAddress = vm.envAddress("SEPOLIA_VAULT_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAdminAddress = vm.envAddress("ARBITRUM_VAULT_PROXY_ADMIN_ADDRESS");
            vaultProxyAddress = vm.envAddress("ARBITRUM_VAULT_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        NexVault newVaultImplementation = new NexVault();
        console.log("New NexVault implementation deployed at:", address(newVaultImplementation));

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(payable(vaultProxyAddress)), address(newVaultImplementation));

        console.log("NexVault proxy upgraded to new implementation at:", address(newVaultImplementation));

        vm.stopBroadcast();
    }
}
