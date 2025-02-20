// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/vault/NexVault.sol";

contract DeployNexVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin();
        NexVault nexVaultImplementation = new NexVault();

        bytes memory data = abi.encodeWithSignature("initialize(address)", address(0));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(nexVaultImplementation), address(proxyAdmin), data);

        console.log("NexVault implementation deployed at:", address(nexVaultImplementation));
        console.log("NexVault proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for NexVault deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}
