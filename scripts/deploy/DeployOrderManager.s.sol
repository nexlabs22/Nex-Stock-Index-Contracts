// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/factory/OrderManager.sol";

contract DeployOrderManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory targetChain = "sepolia";

        address usdc;
        uint8 usdcDecimals;
        address issuer;

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

        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);
        OrderManager orderManagerImplementation = new OrderManager();

        bytes memory data = abi.encodeWithSignature("initialize(address,uint8,address)", usdc, usdcDecimals, issuer);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(orderManagerImplementation), address(proxyAdmin), data);

        console.log("OrderManager implementation deployed at:", address(orderManagerImplementation));
        console.log("OrderManager proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for OrderManager deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}
