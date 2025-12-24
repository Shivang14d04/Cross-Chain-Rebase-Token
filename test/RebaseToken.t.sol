// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/vault.sol";
import {IRebaseToken} from "../src/Interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardsAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardsAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        // Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // 2. Check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("Initial Rebase Token Balance:", startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        // 4. warp the time again by the same amount and check balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // Redeem funds
        vault.redeem(amount);

        uint256 balance = rebaseToken.balanceOf(user);
        console.log("User balance: %d", balance);
        assertEq(balance, 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        // deposit
        vm.deal(user, depositAmount);
        vm.prank(user);

        vault.deposit{value: depositAmount}();

        // warp time
        vm.warp(block.timestamp + time);

        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        vm.deal(owner, balanceAfterSomeTime - depositAmount);

        // add rewards to vault to simulate interest
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositAmount); // add 10% of user's balance as rewards
        // redeem
        vm.prank(user);
        vault.redeem(balanceAfterSomeTime);

        uint256 ethBalance = address(user).balance;

        assertEq(ethBalance, depositAmount);
    }
}
