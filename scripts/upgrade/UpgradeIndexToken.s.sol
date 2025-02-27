// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IndexToken} from "../../../../contracts/token/IndexToken.sol";

contract UpgradeIndexToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address proxyAdminAddress;
        address indexTokenProxyAddress;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAdminAddress = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADMIN_ADDRESS");
            indexTokenProxyAddress = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAdminAddress = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADMIN_ADDRESS");
            indexTokenProxyAddress = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        IndexToken newIndexTokenImplementation = new IndexToken();
        console.log("New IndexToken implementation deployed at:", address(newIndexTokenImplementation));

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(indexTokenProxyAddress)), address(newIndexTokenImplementation), ""
        );

        console.log("IndexToken proxy upgraded to new implementation at:", address(newIndexTokenImplementation));

        vm.stopBroadcast();
    }
}
