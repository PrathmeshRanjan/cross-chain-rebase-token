// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Test, console} from "forge-std/Test.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() external {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(rebaseToken);
        rebaseToken.grantMintAndBurnRole(address(vault));
        // Give owner enough ETH to fund the vault
        vm.deal(owner, 1000e18);
        // Fund vault with extra ETH to cover interest payments for testing
        // In reality, this would come from yield-generating strategies
        (bool success, ) = payable(address(vault)).call{value: 1000e18}("");
        require(success, "Vault funding failed");
        vm.stopPrank();
    }

    uint256 public depositedAmount; // State variable to store bounded amount

    modifier deposit(uint256 amount) {
        depositedAmount = bound(amount, 1e5, 100e18); // Use smaller max for testing (100 ETH)
        vm.startPrank(user);
        vm.deal(user, depositedAmount);
        vault.deposit{value: depositedAmount}();
        assertEq(depositedAmount, rebaseToken.balanceOf(user));
        _;
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, 100e18); // Use same bounds as modifier
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("Start balance: ", startBalance);
        assertEq(amount, startBalance);
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("Middle balance: ", middleBalance);
        assert(middleBalance > startBalance);
        vm.warp(block.timestamp + 1 hours);
        uint256 endingBalance = rebaseToken.balanceOf(user);
        console.log("Ending balance: ", endingBalance);
        assert(endingBalance > middleBalance);
    }

    function testRedeem(uint256 amount) external deposit(amount) {
        uint256 ethBalanceBeforeRedeem = user.balance;
        vault.redeem(depositedAmount);
        assertEq(0, rebaseToken.balanceOf(user));
        assertEq(ethBalanceBeforeRedeem + depositedAmount, user.balance);
    }

    function testRedeemAfterTimePassed(
        uint256 amount
    ) external deposit(amount) {
        // Wait for interest to accrue
        vm.warp(block.timestamp + 1 days);

        // Get the current balance (includes accrued interest)
        uint256 balanceWithInterest = rebaseToken.balanceOf(user);
        uint256 ethBalanceBeforeRedeem = user.balance;

        // The balance should be greater than the original deposit due to interest
        assertGt(balanceWithInterest, depositedAmount);

        // Redeem the full balance (including interest)
        vault.redeem(balanceWithInterest);

        // User should have no tokens left
        assertEq(0, rebaseToken.balanceOf(user));

        // User should receive more ETH than originally deposited
        assertGt(user.balance, ethBalanceBeforeRedeem + depositedAmount);

        // User's total ETH should equal their token balance with interest
        assertEq(user.balance, ethBalanceBeforeRedeem + balanceWithInterest);
    }

    function testTransfer(uint256 amount) external {
        address user1 = makeAddr("user1");
        depositedAmount = bound(amount, 1e5, 100e18);

        // Step 1: User deposits
        vm.startPrank(user);
        vm.deal(user, depositedAmount);
        vault.deposit{value: depositedAmount}();
        uint256 senderInterestRate = rebaseToken.getUserInterestRate(user);
        vm.stopPrank(); // ✅ Stop pranking as user BEFORE switching

        // Step 2: Owner changes interest rate
        vm.startPrank(owner);
        rebaseToken.setInterestRate(4e10);
        vm.stopPrank(); // ✅ Stop pranking as owner

        // Step 3: User transfers tokens
        vm.startPrank(user); // ✅ Start pranking as user again
        bool success = rebaseToken.transfer(user1, depositedAmount);
        vm.stopPrank(); // ✅ Stop pranking as user

        // Step 4: Assertions (no prank needed for view calls)
        uint256 receiverInterestRate = rebaseToken.getUserInterestRate(user1);
        assert(success);
        assertEq(rebaseToken.balanceOf(user1), depositedAmount);
        assertEq(receiverInterestRate, senderInterestRate);
    }

    function testCannotCallMint() public {
        // Deposit funds
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.mint(user, 1e5);
        vm.stopPrank();
    }

    function testCannotCallBurn() public {
        // Deposit funds
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.burn(user, 1e5);
        vm.stopPrank();
    }

    function testGetPrincipleAmount() public {
        uint256 amount = 1e5;
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleAmount = rebaseToken.getPrincipalBalanceOfUser(user);
        assertEq(principleAmount, amount);

        // check that the principle amount is the same after some time has passed
        vm.warp(block.timestamp + 1 days);
        uint256 principleAmountAfterWarp = rebaseToken
            .getPrincipalBalanceOfUser(user);
        assertEq(principleAmountAfterWarp, amount);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        // Update the interest rate
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getCurrentInterestRate();
        newInterestRate = bound(
            newInterestRate,
            initialInterestRate + 1,
            type(uint96).max
        );
        vm.prank(owner);
        vm.expectPartialRevert(
            bytes4(
                RebaseToken
                    .RebaseToken__NewInterestRateCannotBeEqualOrHigher
                    .selector
            )
        );
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getCurrentInterestRate(), initialInterestRate);
    }
}
