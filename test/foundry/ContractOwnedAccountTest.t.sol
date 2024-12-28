// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../../contracts/coa/ContractOwnedAccount.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

contract ContractOwnedAccountTest is Test {
    ContractOwnedAccount contractOwnedAccount;
    TestERC20 token;

    address owner = address(this); // The test contract is the owner
    address newOwner = address(0x5678); // New owner address
    address recipient = address(0x1234); // Recipient address
    uint256 initialSupply = 1_000_000 ether;
    uint256 transferAmount = 1_000 ether;

    function setUp() public {
        // Deploy test ERC20 token
        token = new TestERC20("TestToken", "TT", initialSupply);

        // Deploy ContractOwnedAccount contract with the test contract as the owner
        contractOwnedAccount = new ContractOwnedAccount(owner);

        // Fund the ContractOwnedAccount contract with tokens
        token.transfer(address(contractOwnedAccount), initialSupply);
    }

    function testInitialSetup() public {
        // Verify initial owner
        assertEq(contractOwnedAccount.owner(), owner);

        // Verify contract token balance
        assertEq(token.balanceOf(address(contractOwnedAccount)), initialSupply);
    }

    function testSendToken() public {
        // Send tokens from the contract to the recipient
        vm.prank(owner); // Simulate call from the owner
        contractOwnedAccount.sendToken(address(token), recipient, transferAmount);

        // Verify recipient's balance
        assertEq(token.balanceOf(recipient), transferAmount);

        // Verify contract's remaining balance
        assertEq(token.balanceOf(address(contractOwnedAccount)), initialSupply - transferAmount);
    }

    function testSendTokenRevertsIfNotOwner() public {
        // Attempt to send tokens as a non-owner
        vm.prank(recipient); // Simulate call from a non-owner
        vm.expectRevert("Not authorized");
        contractOwnedAccount.sendToken(address(token), recipient, transferAmount);
    }

    function testSetOwner() public {
        // Change ownership to a new owner
        vm.prank(owner); // Simulate call from the current owner
        contractOwnedAccount.setOwner(newOwner);

        // Verify the new owner
        assertEq(contractOwnedAccount.owner(), newOwner);
    }

    function testSetOwnerRevertsIfNotOwner() public {
        // Attempt to set a new owner as a non-owner
        vm.prank(recipient); // Simulate call from a non-owner
        vm.expectRevert("Not authorized");
        contractOwnedAccount.setOwner(newOwner);
    }
}
