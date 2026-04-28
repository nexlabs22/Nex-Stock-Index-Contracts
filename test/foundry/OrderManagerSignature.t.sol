// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../../contracts/factory/OrderManager.sol";

contract OrderManagerSignatureTest is Test {
    using stdStorage for StdStorage;

    OrderManager public orderManager;

    uint256 internal operatorPrivateKey = 0xA11CE; 
    address internal operator;

    // ERC-1271 Standard Magic Values
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant INVALID_SIGNATURE = 0xffffffff;

    function setUp() public {
        operator = vm.addr(operatorPrivateKey);
        orderManager = new OrderManager();

        // Mock the isOperator storage slot to bypass UUPS initialization overhead
        stdstore
            .target(address(orderManager))
            .sig("isOperator(address)")
            .with_key(operator)
            .checked_write(true);
    }

    function test_ValidSignatureReturnsMagicValue() public view {
        // Arrange: Prepare the message and valid signature
        bytes32 messageHash = keccak256(abi.encodePacked("dinari_v2_order_data"));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Act: Validate the signature
        bytes4 result = orderManager.isValidSignature(ethSignedMessageHash, signature);
        
        // Assert
        assertEq(
            bytes32(result), 
            bytes32(MAGIC_VALUE), 
            "ERC1271: Valid signature should return the standard magic value"
        );
    }

    function test_InvalidSignatureReturnsFailure() public view {
        // Arrange: Prepare the message and an unauthorized signature
        bytes32 messageHash = keccak256(abi.encodePacked("dinari_v2_order_data"));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        uint256 unauthorizedPrivateKey = 0xB0B;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorizedPrivateKey, ethSignedMessageHash);
        bytes memory badSignature = abi.encodePacked(r, s, v);

        // Act: Validate the signature
        bytes4 result = orderManager.isValidSignature(ethSignedMessageHash, badSignature);
        
        // Assert
        assertEq(
            bytes32(result), 
            bytes32(INVALID_SIGNATURE), 
            "ERC1271: Invalid signature should return the failure code"
        );
    }
}