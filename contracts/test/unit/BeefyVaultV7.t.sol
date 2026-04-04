// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin-4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {BaseTest} from "../base/BaseTest.sol";
import {BaseAllToNativeFactoryStrat} from "../../src/BaseAllToNativeFactoryStrat.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {StrategyMorphoMerkl} from "../../src/StrategyMorphoMerkl.sol";
import {IStrategyV7} from "../../src/interfaces/IStrategyV7.sol";

contract BeefyVaultV7Test is BaseTest {
    // ── Initialization ────────────────────────────────────────────────────────

    function test_initialization() public view {
        assertEq(vault.name(), "Harvest Morpho USDC");
        assertEq(vault.symbol(), "harvestMorphoUSDC");
        assertEq(address(vault.strategy()), address(strategy));
        assertEq(vault.owner(), owner);
    }

    function test_want_matches_strategy() public view {
        assertEq(address(vault.want()), address(want));
    }

    // ── Deposit ───────────────────────────────────────────────────────────────

    function test_deposit_mints_shares() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        assertGt(vault.balanceOf(user), 0);
        assertEq(vault.totalSupply(), vault.balanceOf(user));
    }

    function test_first_deposit_shares_equal_amount() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        // First depositor: shares == amount (no rounding effects yet)
        assertEq(vault.balanceOf(user), amount);
    }

    function test_deposit_funds_flow_to_strategy() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        // Vault calls earn() after deposit, which transfers to strategy
        assertEq(want.balanceOf(address(vault)), 0);
        assertGt(strategy.balanceOf(), 0);
    }

    function test_deposit_all() public {
        uint256 amount = 500e6;
        deal(address(want), user, amount);
        vm.startPrank(user);
        want.approve(PERMIT2_ADDR, amount);
        // casting to 'uint160' is safe because test deposit amounts are bounded by real token supplies (< 2^160)
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.approve(address(want), address(vault), uint160(amount), uint48(block.timestamp + 1 days));
        vault.depositAll();
        vm.stopPrank();

        assertGt(vault.balanceOf(user), 0);
    }

    // ── Withdraw ──────────────────────────────────────────────────────────────

    function test_withdraw_returns_want() public {
        uint256 depositAmount = 1000e6;
        _depositAs(user, depositAmount);

        uint256 shares = vault.balanceOf(user);
        vm.prank(user);
        vault.withdraw(shares);

        assertEq(vault.balanceOf(user), 0);
        assertApproxEqAbs(want.balanceOf(user), depositAmount, 2); // allow 2 wei rounding
    }

    function test_withdraw_all() public {
        uint256 amount = 1000e6;
        _depositAs(user, amount);

        vm.prank(user);
        vault.withdrawAll();

        assertEq(vault.balanceOf(user), 0);
    }

    function test_second_depositor_proportional_shares() public {
        address user2 = makeAddr("user2");

        _depositAs(user, 1000e6);
        _depositAs(user2, 500e6);

        // user2 should have ~half the shares of user1
        assertApproxEqAbs(vault.balanceOf(user2), vault.balanceOf(user) / 2, 1);
    }

    // ── Share price ───────────────────────────────────────────────────────────

    function test_getPricePerFullShare_empty_vault() public view {
        assertEq(vault.getPricePerFullShare(), 1e18);
    }

    function test_getPricePerFullShare_after_deposit() public {
        _depositAs(user, 1000e6);
        assertGt(vault.getPricePerFullShare(), 0);
    }

    function test_share_price_increases_with_yield() public {
        _depositAs(user, 1000e6);
        uint256 priceBefore = vault.getPricePerFullShare();

        _simulateYield(1.1e18); // 10% yield in Morpho vault

        vm.prank(owner);
        strategy.harvest();

        // Skip past the 1-day lock duration so profit is fully released
        skip(1 days + 1);

        uint256 priceAfter = vault.getPricePerFullShare();
        assertGt(priceAfter, priceBefore);
    }

    // ── earn() ────────────────────────────────────────────────────────────────

    function test_earn_sends_funds_to_strategy() public {
        // Manually send want to vault (bypassing Permit2 for simplicity)
        deal(address(want), address(vault), 500e6);

        vault.earn();

        assertEq(want.balanceOf(address(vault)), 0);
        assertGt(strategy.balanceOf(), 0);
    }

    // ── Strategy management ───────────────────────────────────────────────────

    function test_setStrategy_owner_can_swap() public {
        _depositAs(user, 1000e6);

        address[] memory noRewards = new address[](0);
        BaseAllToNativeFactoryStrat.Addresses memory addrs = BaseAllToNativeFactoryStrat.Addresses({
            want: address(want),
            depositToken: address(0),
            vault: address(vault),
            swapper: address(swapper),
            strategist: strategist,
            feeRecipient: feeRecipient
        });
        bytes memory initData = abi.encodeCall(
            StrategyMorphoMerkl.initialize, (address(morphoVault), address(claimer), false, noRewards, addrs)
        );
        vm.startPrank(owner);
        StrategyMorphoMerkl newStrat = StrategyMorphoMerkl(
            payable(new TransparentUpgradeableProxy(address(new StrategyMorphoMerkl()), makeAddr("pa2"), initData))
        );
        vault.setStrategy(IStrategyV7(address(newStrat)));
        vm.stopPrank();

        assertEq(address(vault.strategy()), address(newStrat));
    }

    function test_setStrategy_reverts_for_non_owner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setStrategy(IStrategyV7(address(strategy)));
    }

    // ── Token rescue ──────────────────────────────────────────────────────────

    function test_inCaseTokensGetStuck_rescues_random_token() public {
        MockERC20 stuckToken = new MockERC20("Stuck", "STUCK", 18);
        deal(address(stuckToken), address(vault), 1 ether);

        vm.prank(owner);
        vault.inCaseTokensGetStuck(address(stuckToken));

        assertEq(stuckToken.balanceOf(owner), 1 ether);
        assertEq(stuckToken.balanceOf(address(vault)), 0);
    }

    function test_inCaseTokensGetStuck_reverts_for_want() public {
        vm.prank(owner);
        vm.expectRevert("!token");
        vault.inCaseTokensGetStuck(address(want));
    }

    // ── balance() view ────────────────────────────────────────────────────────

    function test_balance_includes_strategy_holdings() public {
        _depositAs(user, 1000e6);

        assertApproxEqAbs(vault.balance(), 1000e6, 2);
    }
}
