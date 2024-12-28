// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.25;

// import "forge-std/Test.sol";
// import "../../contracts/dinary/orders/Vault.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// contract TestERC20 is ERC20 {
//     constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
//         _mint(msg.sender, initialSupply);
//     }
// }

// contract VaultTest is Test {
//     Vault vault;
//     TestERC20 token;

//     address admin = address(0x1234); // Admin address
//     address operator = address(0x5678); // Operator address
//     address user = address(0x9ABC); // User address
//     address recipient = address(0xDEF0); // Recipient for rescue

//     uint256 initialSupply = 1_000_000 ether;
//     uint256 withdrawAmount = 1_000 ether;
//     uint256 rescueAmount = 500 ether;

//     event FundsWithdrawn(IERC20 token, address user, uint256 amount);

//     function setUp() public {
//         // Deploy test ERC20 token
//         token = new TestERC20("TestToken", "TT", initialSupply);

//         // Deploy Vault contract with admin set to the test contract
//         vault = new Vault(admin);

//         // Assign OPERATOR_ROLE to the operator
//         // vm.prank(admin); // Simulate admin executing the next transaction
//         // vault.grantRole(vault.OPERATOR_ROLE(), operator);

//         // Fund the Vault with tokens
//         token.transfer(address(vault), initialSupply);
//     }

//     function testInitialSetup() public view {
//         // Verify initial balances
//         assertEq(token.balanceOf(address(vault)), initialSupply);

//         // Verify roles
//         assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
//         assertTrue(vault.hasRole(vault.OPERATOR_ROLE(), operator));
//         assertFalse(vault.hasRole(vault.OPERATOR_ROLE(), user));
//     }

//     function testRescueERC20() public {
//         // Rescue tokens as admin
//         vm.prank(admin);
//         vault.rescueERC20(token, recipient, rescueAmount);

//         // Verify balances
//         assertEq(token.balanceOf(recipient), rescueAmount);
//         assertEq(token.balanceOf(address(vault)), initialSupply - rescueAmount);
//     }

//     function testRescueERC20RevertsIfNotAdmin() public {
//         // Attempt to rescue tokens as a non-admin
//         vm.prank(user);
//         vm.expectRevert("AccessControl: account is missing role");
//         vault.rescueERC20(token, recipient, rescueAmount);
//     }

//     function testWithdrawFunds() public {
//         // Withdraw tokens as operator
//         vm.prank(operator);
//         vault.withdrawFunds(token, user, withdrawAmount);

//         // Verify balances
//         assertEq(token.balanceOf(user), withdrawAmount);
//         assertEq(token.balanceOf(address(vault)), initialSupply - withdrawAmount);
//     }

//     function testWithdrawFundsRevertsIfNotOperator() public {
//         // Attempt to withdraw tokens as a non-operator
//         vm.prank(user);
//         vm.expectRevert("AccessControl: account is missing role");
//         vault.withdrawFunds(token, user, withdrawAmount);
//     }

//     function testEmitFundsWithdrawnEvent() public {
//         // Expect event during withdrawal
//         vm.expectEmit(true, true, true, true);
//         emit FundsWithdrawn(token, user, withdrawAmount);

//         // Perform withdrawal
//         vm.prank(operator);
//         vault.withdrawFunds(token, user, withdrawAmount);
//     }

//     function testEmitRescueERC20Event() public {
//         // This function would require an event in `rescueERC20` for testing.
//         // You can add it if desired and implement the corresponding test.
//     }
// }
