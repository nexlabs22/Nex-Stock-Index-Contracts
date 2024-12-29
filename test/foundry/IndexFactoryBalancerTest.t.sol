// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "../../contracts/factory/IndexFactoryBalancer.sol";
import "../../contracts/factory/IndexFactoryStorage.sol";

contract IndexFactoryBalancerTest is Test {
    IndexFactoryBalancer indexFactoryBalancer;
    IndexFactoryStorage factoryStorage;

    address user = address(1);

    function setUp() public {
        factoryStorage = new IndexFactoryStorage();

        indexFactoryBalancer = new IndexFactoryBalancer();
        indexFactoryBalancer.initialize(address(factoryStorage));
    }

    function testSetIndexFactoryStorageRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexFactoryBalancer.setIndexFactoryStorage(address(0x1111));
    }

    function testPauseRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexFactoryBalancer.pause();
        assertFalse(indexFactoryBalancer.paused());
    }

    function testUnPauseRevertNonOwnerCall() public {
        indexFactoryBalancer.pause();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexFactoryBalancer.pause();
        assertTrue(indexFactoryBalancer.paused());
    }

    function testFirstRebalanceActionRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexFactoryBalancer.firstRebalanceAction();
    }

    function testSecondRebalanceActionRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexFactoryBalancer.secondRebalanceAction(1);
    }

    function testCompleteRebalanceActionRevertNonOwnerCall() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        indexFactoryBalancer.completeRebalanceActions(1);
    }
}
