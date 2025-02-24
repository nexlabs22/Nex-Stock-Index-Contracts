// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/factory/FunctionsOracle.sol";

contract DeployFunctionsOracle is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory targetChain = "sepolia";
        // string memory targetChain = "arbitrum_mainnet";

        address functionsRouterAddress;
        bytes32 newDonId;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            functionsRouterAddress = vm.envAddress("SEPOLIA_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("SEPOLIA_NEW_DON_ID");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            functionsRouterAddress = vm.envAddress("ARBITRUM_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("ARBITRUM_NEW_DON_ID");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);
        FunctionsOracle functionsOracleImplementation = new FunctionsOracle();

        bytes memory data = abi.encodeWithSignature("initialize(address,bytes32)", functionsRouterAddress, newDonId);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(functionsOracleImplementation), address(proxyAdmin), data);

        console.log("FunctionsOracle implementation deployed at:", address(functionsOracleImplementation));
        console.log("FunctionsOracle proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for FunctionsOracle deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}
