// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/factory/OrderManager.sol";

contract UpgradeOrderManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address proxyAdminAddress;
        address orderManagerProxyAddress;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAdminAddress = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADMIN_ADDRESS");
            orderManagerProxyAddress = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAdminAddress = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADMIN_ADDRESS");
            orderManagerProxyAddress = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        OrderManager newOrderManagerImplementation = new OrderManager();
        console.log("New OrderManager implementation deployed at:", address(newOrderManagerImplementation));

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(orderManagerProxyAddress)), address(newOrderManagerImplementation)
        );

        console.log("OrderManager proxy upgraded to new implementation at:", address(newOrderManagerImplementation));

        vm.stopBroadcast();
    }
}
