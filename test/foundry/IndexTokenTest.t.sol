// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "../../contracts/token/IndexToken.sol";

contract IndexTokenTest is Test {
    IndexToken indexToken;

    address user = address(1);

    function setUp() public {
        indexToken = new IndexToken();
        indexToken.initialize("TEST", "TST", 10, address(0x123), 1e18);
    }

    function testPauseRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.pause();
        assertFalse(indexToken.paused());
    }

    function testUnPauseRevertNonOwnerCall() public {
        indexToken.pause();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.pause();
        assertTrue(indexToken.paused());
    }

    function testMintToFeeReceiverRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.mintToFeeReceiver();
    }

    function testSetMethodologistRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.setMethodologist(address(0x1111));
    }

    function testSetFeeRateRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.setFeeRate(10);
    }

    function testSetFeeReceiverRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.setFeeReceiver(address(0x1111));
    }

    function testSetMinterRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.setMinter(address(0x1111), true);
    }

    function testSupplyCeilingRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.setSupplyCeiling(10e18);
    }

    function testToggleRestrictionRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexToken.toggleRestriction(address(0x1111));
    }
}
