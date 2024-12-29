// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "../../contracts/factory/IndexFactoryStorage.sol";
import "../../contracts/token/IndexToken.sol";
import "../../contracts/vault/NexVault.sol";
import "../../contracts/dinary/orders/OrderProcessor.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "../../contracts/test/MockApiOracle.sol";
import "../../contracts/test/LinkToken.sol";
import "../../contracts/dinary/orders/IOrderProcessor.sol";

contract IndexFactoryStorageTest is Test {
    bytes32 jobId = "6b88e0402e5d415eb946e528b8e0c7ba";

    IndexFactoryStorage public factoryStorage;

    function setUp() public {
        factoryStorage = new IndexFactoryStorage();
        factoryStorage.initialize(
            address(0), address(0), address(0), address(0), 18, address(0), address(0), jobId, true
        );
    }

    function testSetFeeRateByNonOwner() public {
        // Arrange
        uint8 newFee = 20;
        address nonOwner = address(0x1234);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setFeeRate(newFee);
        vm.stopPrank();
    }

    function testSetFeeReceiverByNonOwner() public {
        // Arrange
        address newFeeReceiver = address(0x1234);
        address nonOwner = address(0x5678);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setFeeReceiver(newFeeReceiver);
        vm.stopPrank();
    }

    function testSetIsMainnetByNonOwner() public {
        // Arrange
        bool isMainnet = false;
        address nonOwner = address(0x9876);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setIsMainnet(isMainnet);
        vm.stopPrank();
    }

    function testSetUsdcAddressByNonOwner() public {
        // Arrange
        address newUsdc = address(0x4567);
        uint8 newDecimals = 6;
        address nonOwner = address(0x9876);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setUsdcAddress(newUsdc, newDecimals);
        vm.stopPrank();
    }

    function testSetLatestPriceDecimalsByNonOwner() public {
        // Arrange
        uint8 newDecimals = 8;
        address nonOwner = address(0x5432);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setLatestPriceDecimals(newDecimals);
        vm.stopPrank();
    }

    function testSetTokenAddressByNonOwner() public {
        // Arrange
        address newToken = address(0x9876);
        address nonOwner = address(0x4567);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setTokenAddress(newToken);
        vm.stopPrank();
    }

    function testSetOrderManagerByNonOwner() public {
        // Arrange
        address newOrderManager = address(0x8765);
        address nonOwner = address(0x5432);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setOrderManager(newOrderManager);
        vm.stopPrank();
    }

    function testSetIssuerByNonOwner() public {
        // Arrange
        address newIssuer = address(0x1234);
        address nonOwner = address(0x5678);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setIssuer(newIssuer);
        vm.stopPrank();
    }

    function testSetWrappedDShareAddressesByNonOwner() public {
        // Arrange
        address[] memory dShares = new address[](1);
        address[] memory wrappedDshares = new address[](1);
        dShares[0] = address(0x1111);
        wrappedDshares[0] = address(0x2222);
        address nonOwner = address(0x3333);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setWrappedDShareAddresses(dShares, wrappedDshares);
        vm.stopPrank();
    }

    function testSetPriceFeedAddressesByNonOwner() public {
        // Arrange
        address[] memory dShares = new address[](1);
        address[] memory priceFeeds = new address[](1);
        dShares[0] = address(0x4444);
        priceFeeds[0] = address(0x5555);
        address nonOwner = address(0x6666);
        vm.startPrank(nonOwner);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setPriceFeedAddresses(dShares, priceFeeds);
        vm.stopPrank();
    }

    function testIncreaseIssuanceNonceByNonFactory() public {
        address nonFactory = address(0x1111);
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.increaseIssuanceNonce();
        vm.stopPrank();
    }

    function testIncreaseRedemptionNonceByNonFactory() public {
        address nonFactory = address(0x2222);
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.increaseRedemptionNonce();
        vm.stopPrank();
    }

    function testSetIssuanceIsCompletedByNonFactory() public {
        address nonFactory = address(0x3333);
        uint256 nonce = 1;
        bool isCompleted = true;
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setIssuanceIsCompleted(nonce, isCompleted);
        vm.stopPrank();
    }

    function testSetRedemptionIsCompletedByNonFactory() public {
        address nonFactory = address(0x4444);
        uint256 nonce = 1;
        bool isCompleted = true;
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setRedemptionIsCompleted(nonce, isCompleted);
        vm.stopPrank();
    }

    function testSetBurnedTokenAmountByNonceByNonFactory() public {
        address nonFactory = address(0x5555);
        uint256 nonce = 1;
        uint256 burnedAmount = 100;
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setBurnedTokenAmountByNonce(nonce, burnedAmount);
        vm.stopPrank();
    }

    function testSetIssuanceRequestIdByNonFactory() public {
        address nonFactory = address(0x6666);
        uint256 nonce = 1;
        address token = address(0x7777);
        uint256 requestId = 123;
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setIssuanceRequestId(nonce, token, requestId);
        vm.stopPrank();
    }

    function testSetRedemptionRequestIdByNonFactory() public {
        address nonFactory = address(0x8888);
        uint256 nonce = 1;
        address token = address(0x9999);
        uint256 requestId = 456;
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setRedemptionRequestId(nonce, token, requestId);
        vm.stopPrank();
    }

    function testSetIssuanceRequesterByNonceByNonFactory() public {
        address nonFactory = address(0xAAAA);
        uint256 nonce = 1;
        address requester = address(0xBBBB);
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setIssuanceRequesterByNonce(nonce, requester);
        vm.stopPrank();
    }

    function testSetRedemptionRequesterByNonceByNonFactory() public {
        address nonFactory = address(0xCCCC);
        uint256 nonce = 1;
        address requester = address(0xDDDD);
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setRedemptionRequesterByNonce(nonce, requester);
        vm.stopPrank();
    }

    function testSetCancelIssuanceRequestIdByNonFactory() public {
        address nonFactory = address(0xEEEE);
        uint256 nonce = 1;
        address token = address(0xFFFF);
        uint256 requestId = 789;
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setCancelIssuanceRequestId(nonce, token, requestId);
        vm.stopPrank();
    }

    function testSetCancelRedemptionRequestIdByNonFactory() public {
        address nonFactory = address(0x1234);
        uint256 nonce = 1;
        address token = address(0x5678);
        uint256 requestId = 101112;
        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setCancelRedemptionRequestId(nonce, token, requestId);
        vm.stopPrank();
    }

    function testSetFactoryByNonOwner() public {
        address factoryAddress = address(0xBBBB);
        address nonOwner = address(0xCCCC);
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setFactory(factoryAddress);
        vm.stopPrank();
    }

    function testSetFactoryBalancerByNonOwner() public {
        address factoryBalancerAddress = address(0xDDDD);
        address nonOwner = address(0xEEEE);
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setFactoryBalancer(factoryBalancerAddress);
        vm.stopPrank();
    }

    function testSetFactoryProcessorByNonOwner() public {
        address factoryProcessorAddress = address(0xFFFF);
        address nonOwner = address(0x1111);
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setFactoryProcessor(factoryProcessorAddress);
        vm.stopPrank();
    }

    function testSetUrlByNonOwner() public {
        string memory beforeAddress = "https://example.com";
        string memory afterAddress = "?query=true";
        address nonOwner = address(0x7777);
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setUrl(beforeAddress, afterAddress);
        vm.stopPrank();
    }

    function testSetOracleInfoByNonOwner() public {
        address oracleAddress = address(0x8888);
        bytes32 externalJobId = "0x9999";
        address nonOwner = address(0xAAAA);
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        factoryStorage.setOracleInfo(oracleAddress, externalJobId);
        vm.stopPrank();
    }

    function testSetBuyRequestPayedAmountByIdByNonFactory() public {
        uint256 requestId = 1;
        uint256 amount = 100;
        address nonFactory = address(0x9999);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setBuyRequestPayedAmountById(requestId, amount);
        vm.stopPrank();
    }

    function testSetSellRequestAssetAmountByIdByNonFactory() public {
        uint256 requestId = 2;
        uint256 amount = 200;
        address nonFactory = address(0x8888);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setSellRequestAssetAmountById(requestId, amount);
        vm.stopPrank();
    }

    function testSetIssuanceTokenPrimaryBalanceByNonFactory() public {
        uint256 issuanceNonce = 3;
        address token = address(0x7777);
        uint256 amount = 300;
        address nonFactory = address(0x6666);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setIssuanceTokenPrimaryBalance(issuanceNonce, token, amount);
        vm.stopPrank();
    }

    function testSetRedemptionTokenPrimaryBalanceByNonFactory() public {
        uint256 redemptionNonce = 4;
        address token = address(0x5555);
        uint256 amount = 400;
        address nonFactory = address(0x4444);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setRedemptionTokenPrimaryBalance(redemptionNonce, token, amount);
        vm.stopPrank();
    }

    function testSetIssuanceIndexTokenPrimaryTotalSupplyByNonFactory() public {
        uint256 issuanceNonce = 5;
        uint256 amount = 500;
        address nonFactory = address(0x3333);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setIssuanceIndexTokenPrimaryTotalSupply(issuanceNonce, amount);
        vm.stopPrank();
    }

    function testSetRedemptionIndexTokenPrimaryTotalSupplyByNonFactory() public {
        uint256 redemptionNonce = 6;
        uint256 amount = 600;
        address nonFactory = address(0x2222);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setRedemptionIndexTokenPrimaryTotalSupply(redemptionNonce, amount);
        vm.stopPrank();
    }

    function testSetIssuanceInputAmountByNonFactory() public {
        uint256 issuanceNonce = 7;
        uint256 amount = 700;
        address nonFactory = address(0x1111);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setIssuanceInputAmount(issuanceNonce, amount);
        vm.stopPrank();
    }

    function testSetRedemptionInputAmountByNonFactory() public {
        uint256 redemptionNonce = 8;
        uint256 amount = 800;
        address nonFactory = address(0x00001);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setRedemptionInputAmount(redemptionNonce, amount);
        vm.stopPrank();
    }

    function testSetCancelIssuanceUnfilledAmountByNonFactory() public {
        uint256 issuanceNonce = 9;
        address token = address(0xAAAA);
        uint256 amount = 900;
        address nonFactory = address(0xBBBB);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setCancelIssuanceUnfilledAmount(issuanceNonce, token, amount);
        vm.stopPrank();
    }

    function testSetCancelRedemptionUnfilledAmountByNonFactory() public {
        uint256 redemptionNonce = 10;
        address token = address(0xCCCC);
        uint256 amount = 1000;
        address nonFactory = address(0xDDDD);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setCancelRedemptionUnfilledAmount(redemptionNonce, token, amount);
        vm.stopPrank();
    }

    function testSetCancelIssuanceCompletedByNonFactory() public {
        uint256 issuanceNonce = 11;
        bool isCompleted = true;
        address nonFactory = address(0xEEEE);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setCancelIssuanceComplted(issuanceNonce, isCompleted);
        vm.stopPrank();
    }

    function testSetCancelRedemptionCompletedByNonFactory() public {
        uint256 redemptionNonce = 12;
        bool isCompleted = true;
        address nonFactory = address(0xFFFF);

        vm.startPrank(nonFactory);
        vm.expectRevert("Caller is not a factory contract");
        factoryStorage.setCancelRedemptionComplted(redemptionNonce, isCompleted);
        vm.stopPrank();
    }

    function testSetUsdcAddressRevertZeroAddress() public {
        vm.expectRevert("invalid token address");
        factoryStorage.setUsdcAddress(address(0), 8);
    }

    function testSetTokenAddressRevertZeroAddress() public {
        vm.expectRevert("invalid token address");
        factoryStorage.setTokenAddress(address(0));
    }

    function testSetIssuerRevertZeroAddress() public {
        vm.expectRevert("invalid issuer address");
        factoryStorage.setIssuer(address(0));
    }
}
