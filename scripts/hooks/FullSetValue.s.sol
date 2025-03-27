// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {IndexFactoryStorage} from "../../../../contracts/factory/IndexFactoryStorage.sol";
import {IndexToken} from "../../contracts/token/IndexToken.sol";
import {FunctionsOracle} from "../../contracts/factory/FunctionsOracle.sol";
import {OrderManager} from "../../contracts/factory/OrderManager.sol";
import {NexVault} from "../../contracts/vault/NexVault.sol";

contract SetAllValues is Script {
    address public indexFactoryStorageProxy;
    address public indexFactoryProxy;
    address public vaultProxy;
    address public indexFactoryBalancerProxy;
    address public orderManagerProxy;
    address public factoryProcessorProxy;

    address public indexTokenProxy;

    address public functionsOracleProxy;

    // string public targetChain = "sepolia";
    string public targetChain = "arbitrum_mainnet";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        _initAddressesForChain();

        vm.startBroadcast(deployerPrivateKey);

        // 1. Update IndexFactoryStorage references & set wrapped dShares
        _setIndexFactoryStorageValues();

        // 2. Set IndexToken minters
        _setIndexTokenValues();

        // 3. Set mock oracle data
        _setMockOracleData();

        // 4. Set OrderManager operators
        _setOrderManagerValues();

        // 5. Set NexVault operators
        _setVaultValues();

        // 5. Set FunctionsOracle operators
        _setFunctionsOracleValues();

        vm.stopBroadcast();
    }

    // ---------------------------------------------------------------------
    // Step 1: set references in IndexFactoryStorage
    // ---------------------------------------------------------------------
    function _setIndexFactoryStorageValues() internal {
        console.log("== Setting IndexFactoryStorage Values ==");

        IndexFactoryStorage(indexFactoryStorageProxy).setOrderManager(orderManagerProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactory(indexFactoryProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactoryProcessor(factoryProcessorProxy);
        IndexFactoryStorage(indexFactoryStorageProxy).setFactoryBalancer(indexFactoryBalancerProxy);

        _setPriceFeedAddresses();
        // _setWrappedDShares();
    }

    function _setFunctionsOracleValues() internal {
        console.log("== Setting FunctionsOracle Values ==");
        FunctionsOracle(functionsOracleProxy).setFactoryBalancer(indexFactoryBalancerProxy);
    }

    function _setWrappedDShares() internal {
        console.log("== Setting wrapped dShares on IndexFactoryStorage ==");

        address[] memory dShares = new address[](7);
        address[] memory wrappedDshares = new address[](7);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            dShares[0] = vm.envAddress("SEPOLIA_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("SEPOLIA_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("SEPOLIA_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("SEPOLIA_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("SEPOLIA_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("SEPOLIA_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("SEPOLIA_TSLA_DSHARE_ADDRESS");

            wrappedDshares[0] = vm.envAddress("SEPOLIA_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[1] = vm.envAddress("SEPOLIA_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[2] = vm.envAddress("SEPOLIA_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[3] = vm.envAddress("SEPOLIA_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[4] = vm.envAddress("SEPOLIA_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[5] = vm.envAddress("SEPOLIA_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[6] = vm.envAddress("SEPOLIA_TSLA_WRAPPED_DSHARE_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            dShares[0] = vm.envAddress("ARBITRUM_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("ARBITRUM_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("ARBITRUM_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("ARBITRUM_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("ARBITRUM_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("ARBITRUM_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("ARBITRUM_TSLA_DSHARE_ADDRESS");

            wrappedDshares[0] = vm.envAddress("ARBITRUM_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[1] = vm.envAddress("ARBITRUM_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[2] = vm.envAddress("ARBITRUM_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[3] = vm.envAddress("ARBITRUM_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[4] = vm.envAddress("ARBITRUM_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[5] = vm.envAddress("ARBITRUM_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[6] = vm.envAddress("ARBITRUM_TSLA_WRAPPED_DSHARE_ADDRESS");
        } else {
            revert("Unsupported target chain (wrapped dShares)");
        }

        IndexFactoryStorage(indexFactoryStorageProxy).setWrappedDShareAddresses(dShares, wrappedDshares);
    }

    // ---------------------------------------------------------------------
    // Step 2: set minters in IndexToken
    // ---------------------------------------------------------------------
    function _setIndexTokenValues() internal {
        console.log("== Setting IndexToken Values ==");
        IndexToken(payable(indexTokenProxy)).setMinter(indexFactoryProxy, true);
        IndexToken(payable(indexTokenProxy)).setMinter(factoryProcessorProxy, true);
    }

    // ---------------------------------------------------------------------
    // Step 3: set mock oracle data in FunctionsOracle
    // ---------------------------------------------------------------------
    function _setMockOracleData() internal {
        console.log("== Setting Mock Oracle Data ==");

        address[] memory dShares = new address[](7);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            dShares[0] = vm.envAddress("SEPOLIA_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("SEPOLIA_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("SEPOLIA_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("SEPOLIA_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("SEPOLIA_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("SEPOLIA_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("SEPOLIA_TSLA_DSHARE_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            dShares[0] = vm.envAddress("ARBITRUM_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("ARBITRUM_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("ARBITRUM_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("ARBITRUM_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("ARBITRUM_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("ARBITRUM_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("ARBITRUM_TSLA_DSHARE_ADDRESS");
        } else {
            revert("Unsupported target chain (mock oracle data)");
        }

        uint256[] memory marketShares = new uint256[](7);
        marketShares[0] = 19820000000000000000;
        marketShares[1] = 17660000000000000000;
        marketShares[2] = 16510000000000000000;
        marketShares[3] = 14430000000000000000;
        marketShares[4] = 14280000000000000000;
        marketShares[5] = 10170000000000000000;
        marketShares[6] = 7130000000000000000;

        FunctionsOracle(functionsOracleProxy).mockFillAssetsList(dShares, marketShares);
    }

    // ---------------------------------------------------------------------
    // Step 4: set operators in OrderManager
    // ---------------------------------------------------------------------
    function _setOrderManagerValues() internal {
        console.log("== Setting OrderManager Values ==");
        OrderManager(orderManagerProxy).setOperator(indexFactoryProxy, true);
        OrderManager(orderManagerProxy).setOperator(indexFactoryBalancerProxy, true);
        OrderManager(orderManagerProxy).setOperator(factoryProcessorProxy, true);
    }

    // ---------------------------------------------------------------------
    // Step 5: set operators in NexVault
    // ---------------------------------------------------------------------
    function _setVaultValues() internal {
        console.log("== Setting NexVault Values ==");
        NexVault(vaultProxy).setOperator(indexFactoryProxy, true);
        NexVault(vaultProxy).setOperator(indexFactoryBalancerProxy, true);
        NexVault(vaultProxy).setOperator(factoryProcessorProxy, true);
    }

    function _initAddressesForChain() internal {
        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
            vaultProxy = vm.envAddress("SEPOLIA_VAULT_PROXY_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            orderManagerProxy = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
            factoryProcessorProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
            indexTokenProxy = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            indexFactoryProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
            vaultProxy = vm.envAddress("ARBITRUM_VAULT_PROXY_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            orderManagerProxy = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
            factoryProcessorProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
            indexTokenProxy = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }
    }

    function _setPriceFeedAddresses() public {
        console.log("== Setting Price feed dShares on IndexFactoryStorage ==");

        address[] memory dShares = new address[](7);
        address[] memory wrappedDshares = new address[](7);
        address[] memory priceFeedAddresses = new address[](7);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            dShares[0] = vm.envAddress("SEPOLIA_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("SEPOLIA_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("SEPOLIA_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("SEPOLIA_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("SEPOLIA_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("SEPOLIA_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("SEPOLIA_TSLA_DSHARE_ADDRESS");

            wrappedDshares[0] = vm.envAddress("SEPOLIA_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[1] = vm.envAddress("SEPOLIA_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[2] = vm.envAddress("SEPOLIA_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[3] = vm.envAddress("SEPOLIA_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[4] = vm.envAddress("SEPOLIA_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[5] = vm.envAddress("SEPOLIA_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[6] = vm.envAddress("SEPOLIA_TSLA_WRAPPED_DSHARE_ADDRESS");

            priceFeedAddresses[0] = vm.envAddress("SEPOLIA_APPLE_PRICE_FEED_ADDRESS");
            priceFeedAddresses[1] = vm.envAddress("SEPOLIA_MSFT_PRICE_FEED_ADDRESS");
            priceFeedAddresses[2] = vm.envAddress("SEPOLIA_NVDA_PRICE_FEED_ADDRESS");
            priceFeedAddresses[3] = vm.envAddress("SEPOLIA_AMZN_PRICE_FEED_ADDRESS");
            priceFeedAddresses[4] = vm.envAddress("SEPOLIA_GOOG_PRICE_FEED_ADDRESS");
            priceFeedAddresses[5] = vm.envAddress("SEPOLIA_META_PRICE_FEED_ADDRESS");
            priceFeedAddresses[6] = vm.envAddress("SEPOLIA_TSLA_PRICE_FEED_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            dShares[0] = vm.envAddress("ARBITRUM_APPLE_DSHARE_ADDRESS");
            dShares[1] = vm.envAddress("ARBITRUM_MSFT_DSHARE_ADDRESS");
            dShares[2] = vm.envAddress("ARBITRUM_NVDA_DSHARE_ADDRESS");
            dShares[3] = vm.envAddress("ARBITRUM_AMZN_DSHARE_ADDRESS");
            dShares[4] = vm.envAddress("ARBITRUM_GOOG_DSHARE_ADDRESS");
            dShares[5] = vm.envAddress("ARBITRUM_META_DSHARE_ADDRESS");
            dShares[6] = vm.envAddress("ARBITRUM_TSLA_DSHARE_ADDRESS");

            wrappedDshares[0] = vm.envAddress("ARBITRUM_APPLE_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[1] = vm.envAddress("ARBITRUM_MSFT_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[2] = vm.envAddress("ARBITRUM_NVDA_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[3] = vm.envAddress("ARBITRUM_AMZN_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[4] = vm.envAddress("ARBITRUM_GOOG_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[5] = vm.envAddress("ARBITRUM_META_WRAPPED_DSHARE_ADDRESS");
            wrappedDshares[6] = vm.envAddress("ARBITRUM_TSLA_WRAPPED_DSHARE_ADDRESS");

            priceFeedAddresses[0] = vm.envAddress("ARBITRUM_APPLE_PRICE_FEED_ADDRESS");
            priceFeedAddresses[1] = vm.envAddress("ARBITRUM_MSFT_PRICE_FEED_ADDRESS");
            priceFeedAddresses[2] = vm.envAddress("ARBITRUM_NVDA_PRICE_FEED_ADDRESS");
            priceFeedAddresses[3] = vm.envAddress("ARBITRUM_AMZN_PRICE_FEED_ADDRESS");
            priceFeedAddresses[4] = vm.envAddress("ARBITRUM_GOOG_PRICE_FEED_ADDRESS");
            priceFeedAddresses[5] = vm.envAddress("ARBITRUM_META_PRICE_FEED_ADDRESS");
            priceFeedAddresses[6] = vm.envAddress("ARBITRUM_TSLA_PRICE_FEED_ADDRESS");
        } else {
            revert("Unsupported target chain (wrapped dShares)");
        }

        IndexFactoryStorage(indexFactoryStorageProxy).setWrappedDshareAndPriceFeedAddresses(
            dShares, wrappedDshares, priceFeedAddresses
        );
    }
}
