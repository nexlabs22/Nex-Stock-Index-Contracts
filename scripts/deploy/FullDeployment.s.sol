// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {FunctionsOracle} from "../../contracts/factory/FunctionsOracle.sol";
import {IndexToken} from "../../contracts/token/IndexToken.sol";
import {NexVault} from "../../contracts/vault/NexVault.sol";
import {IndexFactoryStorage} from "../../contracts/factory/IndexFactoryStorage.sol";
import {IndexFactoryProcessor} from "../../contracts/factory/IndexFactoryProcessor.sol";
import {IndexFactoryBalancer} from "../../contracts/factory/IndexFactoryBalancer.sol";
import {IndexFactory} from "../../contracts/factory/IndexFactory.sol";
import {OrderManager} from "../../contracts/factory/OrderManager.sol";

contract FullDeployment is Script {
    string public targetChain; // e.g. "sepolia" or "arbitrum_mainnet"

    address public constant PRE_DEPLOYED_ORDER_MANAGER = 0x0666056AcFaFf5EDB09F01Da15fe99d3B4eEE5F9;

    address public functionsRouter;
    bytes32 public newDonId;

    string public tokenName;
    string public tokenSymbol;
    uint256 public feeRatePerDayScaled;
    address public feeReceiver;
    uint256 public supplyCeiling;

    address public issuer;
    address public usdc;
    uint8 public usdcDecimals;
    bool public isMainnet;

    address public functionsOracleProxy;
    address public indexTokenProxy;
    address public nexVaultProxy;
    address public indexFactoryStorageProxy;
    address public indexFactoryProcessorProxy;
    address public indexFactoryBalancerProxy;
    address public indexFactoryProxy;

    // address public orderManagerProxy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);

        targetChain = "sepolia";
        // targetChain = "arbitrum_mainnet";

        _initChainVariables();

        console.log("=== Full Deployment Start ===");
        console.log("Deploying as owner:", owner);
        console.log("Target chain:", targetChain);

        vm.startBroadcast(deployerPrivateKey);

        // ===============================
        // STEP 1: Deploy FunctionsOracle
        // ===============================
        {
            console.log("\n=== Deploying FunctionsOracle ===");

            address proxy = Upgrades.deployTransparentProxy(
                "FunctionsOracle.sol", owner, abi.encodeCall(FunctionsOracle.initialize, (functionsRouter, newDonId))
            );

            functionsOracleProxy = proxy;

            address proxyAdmin = Upgrades.getAdminAddress(proxy);
            console.log("FunctionsOracle proxy:", functionsOracleProxy);
            console.log("ProxyAdmin for FunctionsOracle:", proxyAdmin);
        }

        // ===============================
        // STEP 2: Deploy IndexToken
        // ===============================
        {
            console.log("\n=== Deploying IndexToken ===");

            address proxy = Upgrades.deployTransparentProxy(
                "IndexToken.sol",
                owner,
                abi.encodeCall(
                    IndexToken.initialize, (tokenName, tokenSymbol, feeRatePerDayScaled, feeReceiver, supplyCeiling)
                )
            );

            indexTokenProxy = proxy;

            address proxyAdmin = Upgrades.getAdminAddress(proxy);
            console.log("IndexToken proxy:", indexTokenProxy);
            console.log("ProxyAdmin for IndexToken:", proxyAdmin);
        }

        // ===============================
        // STEP 3: Deploy NexVault
        // ===============================
        {
            console.log("\n=== Deploying NexVault ===");

            address proxy = Upgrades.deployTransparentProxy(
                "NexVault.sol", owner, abi.encodeCall(NexVault.initialize, (address(0)))
            );

            nexVaultProxy = proxy;

            address proxyAdmin = Upgrades.getAdminAddress(proxy);
            console.log("NexVault proxy:", nexVaultProxy);
            console.log("ProxyAdmin for NexVault:", proxyAdmin);
        }

        // ===============================
        // STEP 4: Deploy IndexFactoryStorage
        // ===============================
        {
            console.log("\n=== Deploying IndexFactoryStorage ===");

            address proxy = Upgrades.deployTransparentProxy(
                "IndexFactoryStorage.sol",
                owner,
                abi.encodeCall(
                    IndexFactoryStorage.initialize,
                    (issuer, indexTokenProxy, nexVaultProxy, usdc, usdcDecimals, functionsOracleProxy, isMainnet)
                )
            );

            indexFactoryStorageProxy = proxy;

            address proxyAdmin = Upgrades.getAdminAddress(proxy);
            console.log("IndexFactoryStorage proxy:", indexFactoryStorageProxy);
            console.log("ProxyAdmin for IndexFactoryStorage:", proxyAdmin);
        }

        // ===============================
        // STEP 5: Deploy IndexFactoryProcessor
        // ===============================
        {
            console.log("\n=== Deploying IndexFactoryProcessor ===");

            address proxy = Upgrades.deployTransparentProxy(
                "IndexFactoryProcessor.sol",
                owner,
                abi.encodeCall(IndexFactoryProcessor.initialize, (indexFactoryStorageProxy, functionsOracleProxy))
            );

            indexFactoryProcessorProxy = proxy;

            address proxyAdmin = Upgrades.getAdminAddress(proxy);
            console.log("IndexFactoryProcessor proxy:", indexFactoryProcessorProxy);
            console.log("ProxyAdmin for IndexFactoryProcessor:", proxyAdmin);
        }

        // ===============================
        // STEP 6: Deploy IndexFactoryBalancer
        // ===============================
        {
            console.log("\n=== Deploying IndexFactoryBalancer ===");

            address proxy = Upgrades.deployTransparentProxy(
                "IndexFactoryBalancer.sol",
                owner,
                abi.encodeCall(IndexFactoryBalancer.initialize, (indexFactoryStorageProxy, functionsOracleProxy))
            );

            indexFactoryBalancerProxy = proxy;

            address proxyAdmin = Upgrades.getAdminAddress(proxy);
            console.log("IndexFactoryBalancer proxy:", indexFactoryBalancerProxy);
            console.log("ProxyAdmin for IndexFactoryBalancer:", proxyAdmin);
        }

        // ===============================
        // STEP 7: Deploy IndexFactory
        // ===============================
        {
            console.log("\n=== Deploying IndexFactory ===");

            address proxy = Upgrades.deployTransparentProxy(
                "IndexFactory.sol",
                owner,
                abi.encodeCall(IndexFactory.initialize, (indexFactoryStorageProxy, functionsOracleProxy))
            );

            indexFactoryProxy = proxy;

            address proxyAdmin = Upgrades.getAdminAddress(proxy);
            console.log("IndexFactory proxy:", indexFactoryProxy);
            console.log("ProxyAdmin for IndexFactory:", proxyAdmin);
        }

        console.log("\n=== Using Pre-Deployed OrderManager ===");
        console.log("OrderManager address:", PRE_DEPLOYED_ORDER_MANAGER);

        console.log("\n=== Post-Deployment Linking (Optional) ===");
        console.log("Deployment finished successfully.");

        vm.stopBroadcast();
    }

    function _deployOrderManager(address owner) internal returns (address) {
        console.log("\n=== Deploying OrderManager ===");

        address proxy = Upgrades.deployTransparentProxy(
            "OrderManager.sol", owner, abi.encodeCall(OrderManager.initialize, (usdc, usdcDecimals, issuer))
        );
        console.log("OrderManager proxy:", proxy);
        console.log("ProxyAdmin for OrderManager:", Upgrades.getAdminAddress(proxy));
        return proxy;
    }

    // =========================
    // _initChainVariables
    // =========================
    function _initChainVariables() internal {
        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            functionsRouter = vm.envAddress("SEPOLIA_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("SEPOLIA_NEW_DON_ID");

            tokenName = "Magnificent 7 Index";
            tokenSymbol = "MAG7";
            feeRatePerDayScaled = vm.envUint("SEPOLIA_FEE_RATE_PER_DAY_SCALED");
            feeReceiver = vm.envAddress("SEPOLIA_FEE_RECEIVER");
            supplyCeiling = vm.envUint("SEPOLIA_SUPPLY_CEILING");

            issuer = vm.envAddress("SEPOLIA_ISSUER_ADDRESS");
            usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            isMainnet = false;
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            functionsRouter = vm.envAddress("ARBITRUM_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("ARBITRUM_NEW_DON_ID");

            tokenName = "Magnificent 7 Index";
            tokenSymbol = "MAG7";
            feeRatePerDayScaled = vm.envUint("ARBITRUM_FEE_RATE_PER_DAY_SCALED");
            feeReceiver = vm.envAddress("ARBITRUM_FEE_RECEIVER");
            supplyCeiling = vm.envUint("ARBITRUM_SUPPLY_CEILING");

            issuer = vm.envAddress("ARBITRUM_ISSUER_ADDRESS");
            usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            isMainnet = true;
        } else {
            revert("Unsupported target chain");
        }
    }
}
