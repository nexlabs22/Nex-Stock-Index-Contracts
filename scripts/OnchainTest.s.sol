// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {IndexFactory} from "../../contracts/factory/IndexFactory.sol";
import "../../contracts/token/IndexToken.sol";
import "../../contracts/factory/IndexFactoryProcessor.sol";
import "../contracts/factory/IndexFactoryBalancer.sol";

contract OnchainTest is Script {
    IndexToken indexToken;

    address user = vm.envAddress("USER");
    // address weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
    address usdt = vm.envAddress("SEPOLIA_USDC_ADDRESS");
    address indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
    address indexTokenProxy = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
    address factoryProcessor = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROCESSOR_PROXY_ADDRESS");
    address indexFactoryBalancerProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        indexToken = IndexToken(payable(indexTokenProxy));

        // string memory targetChain = "sepolia";

        // issuanceIndexTokensWithUSDC();

        // completeIssunace();

        redemption();

        // secondRebalance();

        vm.stopBroadcast();
    }

    function redemption() public {
        IndexFactory(payable(indexFactoryProxy)).redemption(IERC20(indexTokenProxy).balanceOf(user));
    }

    function issuanceIndexTokensWithUSDC() public {
        IERC20(usdt).approve(indexFactoryProxy, type(uint256).max);
        IndexFactory(payable(indexFactoryProxy)).issuanceIndexTokens(100e6);
    }

    function completeIssunace() public {
        IndexFactoryProcessor(factoryProcessor).completeIssuance(2);
    }

    function secondRebalance() public {
        IndexFactoryBalancer(indexFactoryBalancerProxy).secondRebalanceAction(1);
    }
}
