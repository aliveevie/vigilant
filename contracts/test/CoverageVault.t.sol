// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Base.t.sol";
import {Errors} from "../src/libraries/Errors.sol";

contract CoverageVaultTest is Base {
    function test_DepositMintsShares1To1OnBootstrap() public {
        uint256 shares = _deposit(underwriterA, 1, 10 ether);
        assertEq(shares, 10 ether);
        (uint256 ta,, uint256 ts,) = vault.trancheTotals(1);
        assertEq(ta, 10 ether);
        assertEq(ts, 10 ether);
    }

    function test_WithdrawProportional() public {
        _deposit(underwriterA, 0, 4 ether);
        _deposit(underwriterB, 0, 6 ether);

        uint256 balBefore = underwriterA.balance;
        vm.prank(underwriterA);
        uint256 got = vault.withdraw(0, 2 ether);
        assertEq(got, 2 ether);
        assertEq(underwriterA.balance, balBefore + 2 ether);
    }

    function test_LockRevertsIfInsufficient() public {
        _deposit(underwriterA, 2, 1 ether);
        vm.prank(address(policyManager));
        vm.expectRevert(Errors.InsufficientCapital.selector);
        vault.lock(2, 2 ether);
    }

    function test_WithdrawRevertsWhenTrancheLocked() public {
        _deposit(underwriterA, 2, 10 ether);
        vm.prank(address(policyManager));
        vault.lock(2, 8 ether);
        vm.prank(underwriterA);
        vm.expectRevert(Errors.TrancheLocked.selector);
        vault.withdraw(2, 5 ether); // 5e shares ~= 5e assets, > 2e free
    }

    function test_AbsorbDrainsCFirst() public {
        _deposit(underwriterA, 0, 10 ether);
        _deposit(underwriterB, 1, 10 ether);
        _deposit(underwriterC, 2, 10 ether);

        uint256 balBefore = policyholder.balance;
        vm.prank(address(resolver));
        vault.absorb(15 ether, policyholder);
        assertEq(policyholder.balance, balBefore + 15 ether);

        (uint256 a,,, ) = vault.trancheTotals(0);
        (uint256 b,,, ) = vault.trancheTotals(1);
        (uint256 c,,, ) = vault.trancheTotals(2);
        assertEq(c, 0);
        assertEq(b, 5 ether);
        assertEq(a, 10 ether);
    }

    function test_ReceivePremiumDistributesByMultiplierWeight() public {
        _deposit(underwriterA, 0, 10 ether);
        _deposit(underwriterB, 1, 10 ether);
        _deposit(underwriterC, 2, 10 ether);

        vault.receivePremium{value: 1 ether}();
        (uint256 a,,, ) = vault.trancheTotals(0);
        (uint256 b,,, ) = vault.trancheTotals(1);
        (uint256 c,,, ) = vault.trancheTotals(2);
        // Reserve = 10% of 1e = 0.1e. Remaining 0.9e split by weights 6/10/14.
        // Multipliers: 6000, 10000, 14000. Capital equal at 10e. Weighted: 60_000, 100_000, 140_000. Sum 300_000.
        // toA = 0.9 * 60/300 = 0.18; toB = 0.9 * 100/300 = 0.3; toC = 0.9 - 0.18 - 0.3 = 0.42
        assertEq(a, 10 ether + 0.18 ether);
        assertEq(b, 10 ether + 0.30 ether);
        assertEq(c, 10 ether + 0.42 ether);
        assertEq(vault.reserve(), 0.1 ether);
    }

    function test_OnlyPolicyManagerCanLock() public {
        _deposit(underwriterA, 1, 10 ether);
        vm.expectRevert(Errors.NotPolicyManager.selector);
        vault.lock(1, 1 ether);
    }

    function test_OnlyResolverCanAbsorb() public {
        _deposit(underwriterA, 1, 10 ether);
        vm.expectRevert(Errors.NotIncidentResolver.selector);
        vault.absorb(1 ether, policyholder);
    }
}
