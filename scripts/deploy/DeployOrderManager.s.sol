// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../contracts/factory/OrderManager.sol";

contract DeployOrderManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory targetChain = "sepolia";

        address usdc;
        uint8 usdcDecimals;
        address issuer;

        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            issuer = vm.envAddress("SEPOLIA_ISSUER_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            issuer = vm.envAddress("ARBITRUM_ISSUER_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "OrderManager.sol", owner, abi.encodeCall(OrderManager.initialize, (usdc, usdcDecimals, issuer))
        );

        OrderManager orderManagerImplementation = OrderManager(proxy);

        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("OrderManager implementation deployed at:", address(orderManagerImplementation));
        console.log("OrderManager proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for OrderManager deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}
