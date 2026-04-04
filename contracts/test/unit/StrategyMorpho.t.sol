// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "../base/BaseTest.sol";
import {BaseAllToNativeFactoryStrat} from "../../src/BaseAllToNativeFactoryStrat.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockMerklClaimer} from "../mocks/MockMerklClaimer.sol";

contract StrategyMorphoMerklTest is BaseTest {
    // ── Initialization ────────────────────────────────────────────────────────

    function test_initialization() public view {
        assertEq(address(strategy.morphoVault()), address(morphoVault));
        assertEq(address(strategy.claimer()), address(claimer));
        assertEq(strategy.vault(), address(vault));
        assertEq(strategy.want(), address(want));
        assertEq(strategy.NATIVE(), NATIVE_ADDR);
        assertEq(strategy.swapper(), address(swapper));
        assertEq(strategy.strategist(), strategist);
        assertEq(strategy.feeRecipient(), feeRecipient);
        assertFalse(strategy.paused());
        assertFalse(strategy.harvestOnDeposit());
    }

    function test_rewards_initialized() public view {
        assertEq(strategy.rewardsLength(), 1);
        assertEq(strategy.rewards(0), address(rewardToken));
    }

    // ── Deposit flow ──────────────────────────────────────────────────────────

    function test_deposit_sends_want_to_morpho() public {
        _depositAs(user, 1000e6);

        assertGt(strategy.balanceOfPool(), 0);
        assertEq(want.balanceOf(address(strategy)), 0);
    }

    function test_balance_of_matches_morpho_holdings() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        assertApproxEqAbs(strategy.balanceOf(), amount, 2);
    }

    // ── Withdraw flow ─────────────────────────────────────────────────────────

    function test_withdraw_pulls_from_morpho() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        uint256 withdrawAmount = 500e6;
        vm.prank(address(vault));
        strategy.withdraw(withdrawAmount);

        assertApproxEqAbs(want.balanceOf(address(vault)), withdrawAmount, 2);
    }

    function test_withdraw_reverts_for_non_vault() public {
        _depositAs(user, 1000e6);

        vm.prank(user);
        vm.expectRevert("!vault");
        strategy.withdraw(100e6);
    }

    function test_full_withdraw_then_deposit() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        vm.prank(user);
        vault.withdrawAll();

        assertEq(vault.totalSupply(), 0);
        assertApproxEqAbs(want.balanceOf(user), amount, 2);
    }

    // ── Harvest ───────────────────────────────────────────────────────────────

    function test_harvest_charges_fees_to_fee_recipient() public {
        _depositAs(user, 1000e6);
        deal(address(rewardToken), address(strategy), 100 ether);

        vm.prank(owner);
        strategy.harvest();

        assertGt(strategy.lastHarvest(), 0);
        // 0% fee for hackathon — no WETH sent to feeRecipient
        assertEq(native.balanceOf(feeRecipient), 0);
    }

    function test_harvest_sets_last_harvest_timestamp() public {
        _depositAs(user, 1000e6);
        deal(address(rewardToken), address(strategy), 1 ether);

        skip(1 days);
        vm.prank(owner);
        strategy.harvest();

        assertEq(strategy.lastHarvest(), block.timestamp);
    }

    function test_harvest_with_zero_rewards_does_nothing() public {
        _depositAs(user, 1000e6);

        // No rewards — harvest should not revert, just skip
        vm.prank(owner);
        strategy.harvest();

        // lastHarvest stays 0 since nativeBal <= minAmounts[NATIVE]
        assertEq(strategy.lastHarvest(), 0);
    }

    function test_harvest_with_yield_increases_tvl() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        uint256 tvlBefore = vault.balance();

        _simulateYield(1.05e18);

        skip(1 days);
        vm.prank(owner);
        strategy.harvest();

        // After harvest, lockDuration applies — wait for profit to unlock
        skip(1 days + 1);
        uint256 tvlAfter = vault.balance();
        assertGe(tvlAfter, tvlBefore);
    }

    // ── Locked profit ─────────────────────────────────────────────────────────

    function test_locked_profit_decays_over_time() public {
        _depositAs(user, 1000e6);
        deal(address(rewardToken), address(strategy), 10 ether);

        vm.prank(owner);
        strategy.harvest();

        uint256 lockedImmediately = strategy.lockedProfit();
        assertGt(lockedImmediately, 0);

        skip(12 hours);
        uint256 lockedHalfway = strategy.lockedProfit();
        assertLt(lockedHalfway, lockedImmediately);

        skip(12 hours);
        uint256 lockedAfterFullDay = strategy.lockedProfit();
        assertEq(lockedAfterFullDay, 0);
    }

    // ── Pause / panic ─────────────────────────────────────────────────────────

    function test_panic_withdraws_all_and_pauses() public {
        _depositAs(user, 1000e6);
        assertGt(strategy.balanceOfPool(), 0);

        vm.prank(owner);
        strategy.panic();

        assertTrue(strategy.paused());
        assertEq(strategy.balanceOfPool(), 0);
        assertGt(want.balanceOf(address(strategy)), 0);
    }

    function test_unpause_redeposits_funds() public {
        _depositAs(user, 1000e6);

        vm.prank(owner);
        strategy.panic();
        assertTrue(strategy.paused());

        vm.prank(owner);
        strategy.unpause();
        assertFalse(strategy.paused());
        assertGt(strategy.balanceOfPool(), 0);
    }

    function test_deposit_reverts_when_paused() public {
        vm.prank(owner);
        strategy.pause();

        deal(address(want), address(strategy), 100e6);
        vm.expectRevert(BaseAllToNativeFactoryStrat.StrategyPaused.selector);
        strategy.deposit();
    }

    // ── Merkl claim ───────────────────────────────────────────────────────────

    function test_claim_calls_merkl_claimer() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(owner);
        strategy.claim(tokens, amounts, proofs);

        assertEq(claimer.claimCallCount(), 1);
    }

    // ── Access control ────────────────────────────────────────────────────────

    function test_harvest_reverts_for_non_manager() public {
        _depositAs(user, 1000e6);
        deal(address(rewardToken), address(strategy), 1 ether);

        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        vm.expectRevert(BaseAllToNativeFactoryStrat.NotManager.selector);
        strategy.harvest();
    }

    function test_onlyManager_owner_can_pause() public {
        vm.prank(owner);
        strategy.pause();
        assertTrue(strategy.paused());
    }

    function test_onlyManager_reverts_for_stranger() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(BaseAllToNativeFactoryStrat.NotManager.selector);
        strategy.pause();
    }

    function test_retire_strat_only_vault() public {
        _depositAs(user, 1000e6);

        vm.prank(address(vault));
        strategy.retireStrat();

        assertEq(strategy.balanceOfPool(), 0);
        assertGt(want.balanceOf(address(vault)), 0);
    }

    function test_retire_strat_reverts_for_non_vault() public {
        vm.prank(owner);
        vm.expectRevert("!vault");
        strategy.retireStrat();
    }

    // ── Reward management ─────────────────────────────────────────────────────

    function test_add_reward_token() public {
        MockERC20 newReward = new MockERC20("New Reward", "NR", 18);

        vm.prank(owner);
        strategy.addReward(address(newReward));

        assertEq(strategy.rewardsLength(), 2);
        assertEq(strategy.rewards(1), address(newReward));
    }

    function test_remove_reward_token() public {
        vm.prank(owner);
        strategy.removeReward(0);

        assertEq(strategy.rewardsLength(), 0);
    }

    function test_set_claimer() public {
        MockMerklClaimer newClaimer = new MockMerklClaimer();

        vm.prank(owner);
        strategy.setClaimer(address(newClaimer));

        assertEq(address(strategy.claimer()), address(newClaimer));
    }
}
