// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IndexFactoryStorage} from "../../contracts/factory/IndexFactoryStorage.sol";
import {IndexFactory} from "../../contracts/factory/IndexFactory.sol";
import {IndexFactoryBalancer} from "../../contracts/factory/IndexFactoryBalancer.sol";
import {IndexFactoryProcessor} from "../../contracts/factory/IndexFactoryProcessor.sol";
import {IndexToken} from "../../contracts/token/IndexToken.sol";
import {OrderManager} from "../../contracts/factory/OrderManager.sol";
import {NexVault} from "../../contracts/vault/NexVault.sol";

contract FullDeployment is Script {
    string public targetChain; // e.g. "sepolia" or "arbitrum_mainnet"

    address public issuer;
    address public usdc;
    uint8 public usdcDecimals;
    address public chainlinkToken;
    address public functionsRouter;
    bytes32 public newDonId;
    bool public isMainnet;

    string public tokenName;
    string public tokenSymbol;
    uint256 public feeRatePerDayScaled;
    address public feeReceiver;
    uint256 public supplyCeiling;

    address public nexVaultProxy;
    address public indexTokenProxy;
    address public indexFactoryStorageProxy;
    address public indexFactoryProxy;
    address public indexFactoryBalancerProxy;
    address public indexFactoryProcessorProxy;
    address public orderManagerProxy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        targetChain = "sepolia";
        // targetChain = "arbitrum_mainnet";

        _initChainVariables();

        vm.startBroadcast(deployerPrivateKey);

        //-------------------------------------
        // 1. Deploy NexVault
        //-------------------------------------
        {
            console.log("\n=== Deploying NexVault ===");
            ProxyAdmin vaultProxyAdmin = new ProxyAdmin(msg.sender);
            NexVault nexVaultImplementation = new NexVault();

            bytes memory data = abi.encodeWithSignature("initialize(address)", address(0));

            TransparentUpgradeableProxy vaultProxy =
                new TransparentUpgradeableProxy(address(nexVaultImplementation), address(vaultProxyAdmin), data);
            nexVaultProxy = address(vaultProxy);

            console.log("NexVault implementation:", address(nexVaultImplementation));
            console.log("NexVault proxy:", nexVaultProxy);
            console.log("NexVault proxy admin:", address(vaultProxyAdmin));
        }

        //-------------------------------------
        // 2. Deploy IndexToken
        //-------------------------------------
        {
            console.log("\n=== Deploying IndexToken ===");
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

            TransparentUpgradeableProxy tokenProxy =
                new TransparentUpgradeableProxy(address(indexTokenImplementation), address(indexTokenProxyAdmin), data);
            indexTokenProxy = address(tokenProxy);

            console.log("IndexToken implementation:", address(indexTokenImplementation));
            console.log("IndexToken proxy:", indexTokenProxy);
            console.log("IndexToken proxy admin:", address(indexTokenProxyAdmin));
        }

        //-------------------------------------
        // 3. Deploy IndexFactoryStorage
        //-------------------------------------
        {
            console.log("\n=== Deploying IndexFactoryStorage ===");
            ProxyAdmin storageProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactoryStorage storageImplementation = new IndexFactoryStorage();

            bytes memory data = abi.encodeWithSignature(
                "initialize(address,address,address,address,uint8,address,address,bytes32,bool)",
                issuer,
                indexTokenProxy,
                nexVaultProxy,
                usdc,
                usdcDecimals,
                chainlinkToken,
                functionsRouter,
                newDonId,
                isMainnet
            );

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(storageImplementation), address(storageProxyAdmin), data);
            indexFactoryStorageProxy = address(proxy);

            console.log("IndexFactoryStorage implementation:", address(storageImplementation));
            console.log("IndexFactoryStorage proxy:", indexFactoryStorageProxy);
            console.log("IndexFactoryStorage proxy admin:", address(storageProxyAdmin));
        }

        //-------------------------------------
        // 4. Deploy IndexFactory
        //-------------------------------------
        {
            console.log("\n=== Deploying IndexFactory ===");
            ProxyAdmin factoryProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactory factoryImplementation = new IndexFactory();

            bytes memory data = abi.encodeWithSignature("initialize(address)", indexFactoryStorageProxy);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(factoryImplementation), address(factoryProxyAdmin), data);
            indexFactoryProxy = address(proxy);

            console.log("IndexFactory implementation:", address(factoryImplementation));
            console.log("IndexFactory proxy:", indexFactoryProxy);
            console.log("IndexFactory proxy admin:", address(factoryProxyAdmin));
        }

        //-------------------------------------
        // 5. Deploy IndexFactoryBalancer
        //-------------------------------------
        {
            console.log("\n=== Deploying IndexFactoryBalancer ===");
            ProxyAdmin balancerProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactoryBalancer balancerImplementation = new IndexFactoryBalancer();

            bytes memory data = abi.encodeWithSignature("initialize(address)", indexFactoryStorageProxy);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(balancerImplementation), address(balancerProxyAdmin), data);
            indexFactoryBalancerProxy = address(proxy);

            console.log("IndexFactoryBalancer impl:", address(balancerImplementation));
            console.log("IndexFactoryBalancer proxy:", indexFactoryBalancerProxy);
            console.log("IndexFactoryBalancer proxy admin:", address(balancerProxyAdmin));
        }

        //-------------------------------------
        // 6. Deploy IndexFactoryProcessor
        //-------------------------------------
        {
            console.log("\n=== Deploying IndexFactoryProcessor ===");
            ProxyAdmin processorProxyAdmin = new ProxyAdmin(msg.sender);
            IndexFactoryProcessor processorImplementation = new IndexFactoryProcessor();

            bytes memory data = abi.encodeWithSignature("initialize(address)", indexFactoryStorageProxy);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(processorImplementation), address(processorProxyAdmin), data);
            indexFactoryProcessorProxy = address(proxy);

            console.log("IndexFactoryProcessor impl:", address(processorImplementation));
            console.log("IndexFactoryProcessor proxy:", indexFactoryProcessorProxy);
            console.log("IndexFactoryProcessor proxy admin:", address(processorProxyAdmin));
        }

        //-------------------------------------
        // 7. Deploy OrderManager
        //-------------------------------------
        {
            console.log("\n=== Deploying OrderManager ===");
            ProxyAdmin orderManagerAdmin = new ProxyAdmin(msg.sender);
            OrderManager orderManagerImplementation = new OrderManager();

            bytes memory data = abi.encodeWithSignature("initialize(address,uint8,address)", usdc, usdcDecimals, issuer);

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(orderManagerImplementation), address(orderManagerAdmin), data);
            orderManagerProxy = address(proxy);

            console.log("OrderManager implementation:", address(orderManagerImplementation));
            console.log("OrderManager proxy:", orderManagerProxy);
            console.log("OrderManager proxy admin:", address(orderManagerAdmin));
        }

        //-------------------------------------
        // 8. Post-Deployment Linking
        //-------------------------------------
        console.log("\n=== Post-Deployment Linking ===");

        console.log("Setting IndexFactoryStorage references...");
        IndexFactoryStorage(indexFactoryStorageProxy).setOrderManager(orderManagerProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactory(indexFactoryProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactoryProcessor(indexFactoryProcessorProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactoryBalancer(indexFactoryBalancerProxy);

        _setWrappedDShares(indexFactoryStorageProxy);

        console.log("Setting IndexToken minters...");
        IndexToken(payable(indexTokenProxy)).setMinter(indexFactoryProxy, true);
        IndexToken(payable(indexTokenProxy)).setMinter(indexFactoryProcessorProxy, true);

        console.log("Setting OrderManager operators...");
        OrderManager(orderManagerProxy).setOperator(indexFactoryProxy, true);
        OrderManager(orderManagerProxy).setOperator(indexFactoryBalancerProxy, true);
        OrderManager(orderManagerProxy).setOperator(indexFactoryProcessorProxy, true);

        console.log("Setting NexVault operators...");
        NexVault(nexVaultProxy).setOperator(indexFactoryProxy, true);
        NexVault(nexVaultProxy).setOperator(indexFactoryBalancerProxy, true);
        NexVault(nexVaultProxy).setOperator(indexFactoryProcessorProxy, true);

        vm.stopBroadcast();
    }

    function _initChainVariables() internal {
        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            issuer = vm.envAddress("SEPOLIA_ISSUER_ADDRESS");
            usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            chainlinkToken = vm.envAddress("SEPOLIA_CHAINLINK_TOKEN_ADDRESS");
            functionsRouter = vm.envAddress("SEPOLIA_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("SEPOLIA_NEW_DON_ID");
            isMainnet = false;
            tokenName = "Magnificent 7 Index";
            tokenSymbol = "MAG7";
            feeRatePerDayScaled = vm.envUint("SEPOLIA_FEE_RATE_PER_DAY_SCALED");
            feeReceiver = vm.envAddress("SEPOLIA_FEE_RECEIVER");
            supplyCeiling = vm.envUint("SEPOLIA_SUPPLY_CEILING");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            issuer = vm.envAddress("ARBITRUM_ISSUER_ADDRESS");
            usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            chainlinkToken = vm.envAddress("ARBITRUM_CHAINLINK_TOKEN_ADDRESS");
            functionsRouter = vm.envAddress("ARBITRUM_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("ARBITRUM_NEW_DON_ID");
            isMainnet = true;
            tokenName = "Magnificent 7 Index";
            tokenSymbol = "MAG7";
            feeRatePerDayScaled = vm.envUint("ARBITRUM_FEE_RATE_PER_DAY_SCALED");
            feeReceiver = vm.envAddress("ARBITRUM_FEE_RECEIVER");
            supplyCeiling = vm.envUint("ARBITRUM_SUPPLY_CEILING");
        } else {
            revert("Unsupported target chain");
        }
    }

    function _setWrappedDShares(address factoryStorageProxy) internal {
        address[] memory dShares = new address[](7);
        address[] memory wrappedDShares = new address[](7);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            dShares[0] = vm.envAddress("SEPOLIA_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("SEPOLIA_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("SEPOLIA_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("SEPOLIA_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("SEPOLIA_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("SEPOLIA_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("SEPOLIA_TSLA_DSHARE_ADDRESS");

            wrappedDShares[0] = vm.envAddress("SEPOLIA_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[1] = vm.envAddress("SEPOLIA_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[2] = vm.envAddress("SEPOLIA_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[3] = vm.envAddress("SEPOLIA_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[4] = vm.envAddress("SEPOLIA_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[5] = vm.envAddress("SEPOLIA_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[6] = vm.envAddress("SEPOLIA_TSLA_WRAPPED_DSHARE_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            dShares[0] = vm.envAddress("ARBITRUM_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("ARBITRUM_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("ARBITRUM_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("ARBITRUM_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("ARBITRUM_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("ARBITRUM_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("ARBITRUM_TSLA_DSHARE_ADDRESS");

            wrappedDShares[0] = vm.envAddress("ARBITRUM_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[1] = vm.envAddress("ARBITRUM_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[2] = vm.envAddress("ARBITRUM_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[3] = vm.envAddress("ARBITRUM_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[4] = vm.envAddress("ARBITRUM_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[5] = vm.envAddress("ARBITRUM_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDShares[6] = vm.envAddress("ARBITRUM_TSLA_WRAPPED_DSHARE_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        IndexFactoryStorage(factoryStorageProxy).setWrappedDShareAddresses(dShares, wrappedDShares);

        console.log("Wrapped dShares set successfully");
    }
}
