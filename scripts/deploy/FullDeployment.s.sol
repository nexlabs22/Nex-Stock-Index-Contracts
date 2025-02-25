// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FunctionsOracle} from "../../contracts/factory/FunctionsOracle.sol";
import {IndexToken} from "../../contracts/token/IndexToken.sol";
import {NexVault} from "../../contracts/vault/NexVault.sol";
import {IndexFactoryStorage} from "../../contracts/factory/IndexFactoryStorage.sol";
import {IndexFactoryProcessor} from "../../contracts/factory/IndexFactoryProcessor.sol";
import {IndexFactoryBalancer} from "../../contracts/factory/IndexFactoryBalancer.sol";
import {IndexFactory} from "../../contracts/factory/IndexFactory.sol";
import {OrderManager} from "../../contracts/factory/OrderManager.sol";

contract FullDeployment is Script {
    // We detect which chain we’re deploying to. E.g. "sepolia", "arbitrum_mainnet", etc.
    string public targetChain;

    // address public constant PRE_DEPLOYED_ORDER_MANAGER = 0x0666056AcFaFf5EDB09F01Da15fe99d3B4eEE5F9;

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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // targetChain = "sepolia";
        targetChain = "arbitrum_mainnet";

        _initChainVariables();

        vm.startBroadcast(deployerPrivateKey);

        // ===============================
        // 1. Deploy FunctionsOracle
        // ===============================
        console.log("\n=== Deploying FunctionsOracle ===");
        {
            ProxyAdmin oracleProxyAdmin = new ProxyAdmin(msg.sender);
            FunctionsOracle oracleImplementation = new FunctionsOracle();

            bytes memory data = abi.encodeWithSignature("initialize(address,bytes32)", functionsRouter, newDonId);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(oracleImplementation), address(oracleProxyAdmin), data);

            functionsOracleProxy = address(proxy);

            console.log("FunctionsOracle implementation:", address(oracleImplementation));
            console.log("FunctionsOracle proxy:", functionsOracleProxy);
            console.log("FunctionsOracle proxy admin:", address(oracleProxyAdmin));
        }

        // ===============================
        // 2. Deploy IndexToken
        // ===============================
        console.log("\n=== Deploying IndexToken ===");
        {
            ProxyAdmin indexTokenProxyAdmin = new ProxyAdmin(msg.sender);
            IndexToken indexTokenImplementation = new IndexToken();

            bytes memory data = abi.encodeWithSignature(
                "initialize(string,string,uint256,address,uint256)",
                tokenName,
                tokenSymbol,
                feeRatePerDayScaled,
                feeReceiver,
                supplyCeiling
            );

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(indexTokenImplementation), address(indexTokenProxyAdmin), data);
            indexTokenProxy = address(proxy);

            console.log("IndexToken implementation:", address(indexTokenImplementation));
            console.log("IndexToken proxy:", indexTokenProxy);
            console.log("IndexToken proxy admin:", address(indexTokenProxyAdmin));
        }

        // ===============================
        // 3. Deploy NexVault
        // ===============================
        console.log("\n=== Deploying NexVault ===");
        {
            ProxyAdmin vaultProxyAdmin = new ProxyAdmin(msg.sender);
            NexVault nexVaultImplementation = new NexVault();

            bytes memory data = abi.encodeWithSignature("initialize(address)", address(0));

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(nexVaultImplementation), address(vaultProxyAdmin), data);
            nexVaultProxy = address(proxy);

            console.log("NexVault implementation:", address(nexVaultImplementation));
            console.log("NexVault proxy:", nexVaultProxy);
            console.log("NexVault proxy admin:", address(vaultProxyAdmin));
        }

        // ===============================
        // 4. Deploy IndexFactoryStorage
        // ===============================
        console.log("\n=== Deploying IndexFactoryStorage ===");
        {
            ProxyAdmin storageProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactoryStorage storageImplementation = new IndexFactoryStorage();

            bytes memory data = abi.encodeWithSignature(
                "initialize(address,address,address,address,uint8,address,bool)",
                issuer,
                indexTokenProxy,
                nexVaultProxy,
                usdc,
                usdcDecimals,
                functionsOracleProxy,
                isMainnet
            );

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(storageImplementation), address(storageProxyAdmin), data);
            indexFactoryStorageProxy = address(proxy);

            console.log("IndexFactoryStorage implementation:", address(storageImplementation));
            console.log("IndexFactoryStorage proxy:", indexFactoryStorageProxy);
            console.log("IndexFactoryStorage proxy admin:", address(storageProxyAdmin));
        }

        // ===============================
        // 5. Deploy IndexFactoryProcessor
        // ===============================
        console.log("\n=== Deploying IndexFactoryProcessor ===");
        {
            ProxyAdmin processorProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactoryProcessor processorImplementation = new IndexFactoryProcessor();

            bytes memory data =
                abi.encodeWithSignature("initialize(address,address)", indexFactoryStorageProxy, functionsOracleProxy);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(processorImplementation), address(processorProxyAdmin), data);
            indexFactoryProcessorProxy = address(proxy);

            console.log("IndexFactoryProcessor impl:", address(processorImplementation));
            console.log("IndexFactoryProcessor proxy:", indexFactoryProcessorProxy);
            console.log("IndexFactoryProcessor proxy admin:", address(processorProxyAdmin));
        }

        // ===============================
        // 6. Deploy IndexFactoryBalancer
        // ===============================
        console.log("\n=== Deploying IndexFactoryBalancer ===");
        {
            ProxyAdmin balancerProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactoryBalancer balancerImplementation = new IndexFactoryBalancer();

            bytes memory data =
                abi.encodeWithSignature("initialize(address,address)", indexFactoryStorageProxy, functionsOracleProxy);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(balancerImplementation), address(balancerProxyAdmin), data);
            indexFactoryBalancerProxy = address(proxy);

            console.log("IndexFactoryBalancer impl:", address(balancerImplementation));
            console.log("IndexFactoryBalancer proxy:", indexFactoryBalancerProxy);
            console.log("IndexFactoryBalancer proxy admin:", address(balancerProxyAdmin));
        }

        // ===============================
        // 7. Deploy IndexFactory
        // ===============================
        console.log("\n=== Deploying IndexFactory ===");
        {
            ProxyAdmin factoryProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactory factoryImplementation = new IndexFactory();

            bytes memory data =
                abi.encodeWithSignature("initialize(address,address)", indexFactoryStorageProxy, functionsOracleProxy);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(factoryImplementation), address(factoryProxyAdmin), data);
            indexFactoryProxy = address(proxy);

            console.log("IndexFactory implementation:", address(factoryImplementation));
            console.log("IndexFactory proxy:", indexFactoryProxy);
            console.log("IndexFactory proxy admin:", address(factoryProxyAdmin));
        }

        console.log("\n=== Using Pre-Deployed OrderManager ===");
        // console.log("OrderManager address:", PRE_DEPLOYED_ORDER_MANAGER);

        console.log("\n=== Post-Deployment Linking ===");

        // ===============================
        // 8. Deploy OrderManager
        // ===============================
        _deployOrderManager();

        vm.stopBroadcast();
    }

    // ====================
    // HELPER: Initialize chain variables
    // ====================
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

    function _deployOrderManager() internal returns (address orderManagerProxy) {
        console.log("\n=== Deploying OrderManager ===");

        ProxyAdmin omProxyAdmin = new ProxyAdmin(msg.sender);
        OrderManager omImplementation = new OrderManager();

        bytes memory data = abi.encodeWithSignature("initialize(address,uint8,address)", usdc, usdcDecimals, issuer);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(omImplementation), address(omProxyAdmin), data);

        orderManagerProxy = address(proxy);

        console.log("OrderManager implementation:", address(omImplementation));
        console.log("OrderManager proxy:", orderManagerProxy);
        console.log("OrderManager proxy admin:", address(omProxyAdmin));
    }
}
