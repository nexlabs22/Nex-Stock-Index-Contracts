// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import "../../contracts/factory/FunctionsOracle.sol";

contract SetMockOracleData is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory targetChain = "sepolia";
        // string memory targetChain = "arbitrum_mainnet";

        address functionsOracleProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        setMockOracleData(targetChain, functionsOracleProxy);

        vm.stopBroadcast();
    }

    function setMockOracleData(string memory targetChain, address functionOracleProxy) public {
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
            revert("Unsupported target chain");
        }

        // uint256[] memory marketShares = new uint256[](7);
        // marketShares[0] = 19820000000000000000; // 19.82
        // marketShares[1] = 17660000000000000000; // 17.66
        // marketShares[2] = 16510000000000000000; // 16.51
        // marketShares[3] = 14430000000000000000; // 14.43
        // marketShares[4] = 14280000000000000000; // 14.28
        // marketShares[5] = 10170000000000000000; // 10.17
        // marketShares[6] = 7130000000000000000; // 7.13

        uint256[] memory marketShares = new uint256[](7);
        marketShares[0] = 9820000000000000000; // 9.82
        marketShares[1] = 17660000000000000000; // 17.66
        marketShares[2] = 16510000000000000000; // 16.51
        marketShares[3] = 14430000000000000000; // 14.43
        marketShares[4] = 14280000000000000000; // 14.28
        marketShares[5] = 20170000000000000000; // 20.17
        marketShares[6] = 7130000000000000000; // 7.13

        // FunctionsOracle(functionOracleProxy).mockFillAssetsList(dShares, marketShares);
    }
}
// Before
// Apple: 216.98 * 0.4543
// AMD: 100.79 * 1.7691
// Nvidia: 115.74 * 1.4239
// Amzn: 198.89 * 0.7310
// Blck inch: 55.90 * 2.5618
// Meta: 619.56 * 0.3267
// Reddit: 130.68 * 0.5478

// After
// Apple: 216.98 * 0.9145
// AMD: 100.79 * 1.7691
// Nvidia: 115.74 * 1.4239
// Amzn: 198.89 * 0.7310
// Blck inch: 55.90 * 2.5618
// Meta: 619.56 * 0.1647
// Reddit: 130.68 * 0.5478
