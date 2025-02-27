// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../contracts/factory/OrderManager.sol";

contract UpgradeOrderManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = "sepolia";

        address orderManagerProxyAddress;

        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            orderManagerProxyAddress = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            orderManagerProxyAddress = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        Upgrades.upgradeProxy(orderManagerProxyAddress, "OrderManager.sol", "", owner);

        address implAddrV2 = Upgrades.getImplementationAddress(orderManagerProxyAddress);

        console.log("OrderManager proxy upgraded to new implementation at: ", address(implAddrV2));

        vm.stopBroadcast();
    }
}
