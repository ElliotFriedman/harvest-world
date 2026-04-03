// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin-4/contracts/interfaces/IERC4626.sol";
import {IAllowanceTransfer} from "@permit2/interfaces/IAllowanceTransfer.sol";

import {HarvestDeployer} from "../../script/deployers/HarvestDeployer.sol";
import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorphoMerkl} from "../../src/StrategyMorphoMerkl.sol";
import {BeefySwapper} from "../../src/BeefySwapper.sol";
import {BaseAllToNativeFactoryStrat} from "../../src/BaseAllToNativeFactoryStrat.sol";

/// @notice Fork tests that exercise the REAL BeefySwapper + Uniswap V3 on World Chain.
///         Proves the swap routing configured in Deploy.s.sol actually works end-to-end.
///
///         Run with:
///         WORLD_CHAIN_RPC_URL=<url> forge test --match-contract HarvestSwapForkTest -vvv
contract HarvestSwapForkTest is Test {
    // ── World Chain mainnet addresses ─────────────────────────────────────────
    address internal constant USDC = 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant WLD = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    address internal constant MORPHO_RE7_USDC_VAULT = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address internal constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address internal constant UNISWAP_V3_ROUTER = 0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6;
    IAllowanceTransfer internal constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /// @dev SwapRouter02 exactInputSingle selector — must match Deploy.s.sol
    bytes4 internal constant EXACT_INPUT_SINGLE = 0x04e45aaf;

    // ── Deployed system ───────────────────────────────────────────────────────
    BeefyVaultV7 internal vault;
    StrategyMorphoMerkl internal strategy;
    BeefySwapper internal swapper;

    // ── Actors ────────────────────────────────────────────────────────────────
    address internal owner;
    address internal user;

    uint256 internal worldChainFork;

    function setUp() public {
        string memory rpcUrl = vm.envOr("WORLD_CHAIN_RPC_URL", string("https://worldchain.drpc.org"));
        uint256 forkBlock = vm.envOr("WORLD_CHAIN_FORK_BLOCK", uint256(27956180));
        worldChainFork = vm.createFork(rpcUrl, forkBlock);
        vm.selectFork(worldChainFork);

        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.startPrank(owner);
        _deploySwapper();
        _deploySystem();
        vm.stopPrank();

        _setVerifiedInTest(user, true);
    }

    // ── Setup helpers ─────────────────────────────────────────────────────────

    /// @dev Deploy real BeefySwapper with Uniswap V3 routes that have on-chain liquidity.
    ///      MORPHO has NO Uni V3 pools on World Chain. Merkl rewards are WLD.
    function _deploySwapper() internal {
        swapper = new BeefySwapper();
        swapper.initialize(address(0), 0);

        // WLD -> WETH (0.3% fee) — pool 0x494D68e... has liquidity
        _setUniV3Route(WLD, WETH, 3000);
        // WETH -> USDC (0.05% fee) — pool 0x5f8354... has liquidity
        _setUniV3Route(WETH, USDC, 500);
    }

    /// @dev Mirrors Deploy.s.sol _setUniV3Route exactly.
    function _setUniV3Route(address tokenIn, address tokenOut, uint24 fee) internal {
        bytes memory data = abi.encodeWithSelector(
            EXACT_INPUT_SINGLE,
            tokenIn,
            tokenOut,
            fee,
            address(swapper), // recipient
            uint256(0),       // amountIn placeholder (overwritten at index 132)
            uint256(0),       // amountOutMinimum placeholder (overwritten at index 164)
            uint160(0)        // sqrtPriceLimitX96 — no limit
        );

        swapper.setSwapInfo(
            tokenIn,
            tokenOut,
            BeefySwapper.SwapInfo({
                router: UNISWAP_V3_ROUTER,
                data: data,
                amountIndex: 132, // 4 + 4*32
                minIndex: 164,    // 4 + 5*32
                minAmountSign: 0
            })
        );
    }

    function _deploySystem() internal {
        address[] memory rewards = new address[](1);
        rewards[0] = WLD;

        HarvestDeployer.ExternalAddresses memory ext = HarvestDeployer.ExternalAddresses({
            want: USDC,
            depositToken: address(0),
            morphoVault: MORPHO_RE7_USDC_VAULT,
            claimer: MERKL_DISTRIBUTOR,
            swapper: address(swapper),
            strategist: owner,
            feeRecipient: owner
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo World Morpho USDC",
            vaultSymbol: "mooWorldMorphoUSDC",
            harvestOnDeposit: false,
            rewards: rewards,
            externalNullifierHash: 1
        });

        HarvestDeployer.Deployment memory d = HarvestDeployer.deploy(ext, params);
        vault = d.vault;
        strategy = d.strategy;
    }

    /// @dev Directly set verifiedHumans[_user] via vm.store (slot 204).
    function _setVerifiedInTest(address _user, bool _status) internal {
        bytes32 slot = keccak256(abi.encode(_user, uint256(204)));
        vm.store(address(vault), slot, _status ? bytes32(uint256(1)) : bytes32(uint256(0)));
    }

    function _depositAs(address depositor, uint256 amount) internal {
        deal(USDC, depositor, amount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(PERMIT2), amount);
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.approve(USDC, address(vault), uint160(amount), uint48(block.timestamp + 1 days));
        vault.deposit(amount);
        vm.stopPrank();
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    /// @dev Deal WLD to the strategy (simulating a Merkl claim),
    ///      then harvest. Verifies the full swap path:
    ///      WLD -> WETH (Uni V3 0.3%) -> USDC (Uni V3 0.05%) -> Morpho vault.
    function test_harvest_swaps_wld_rewards_to_usdc() public {
        // 1. Seed the vault with a real deposit so shares exist
        _depositAs(user, 1_000e6); // 1,000 USDC

        uint256 vaultBalBefore = vault.balance();
        uint256 morphoSharesBefore = IERC4626(MORPHO_RE7_USDC_VAULT).balanceOf(address(strategy));

        // 2. Simulate a Merkl claim by dealing WLD tokens to the strategy
        uint256 rewardAmount = 1_000e18; // 1,000 WLD
        deal(WLD, address(strategy), rewardAmount);
        assertEq(IERC20(WLD).balanceOf(address(strategy)), rewardAmount, "WLD not dealt");

        // 3. Harvest: WLD -> WETH -> USDC -> Morpho vault
        vm.prank(owner);
        strategy.harvest();

        // 4. Verify: WLD was consumed
        assertEq(IERC20(WLD).balanceOf(address(strategy)), 0, "WLD not fully swapped");

        // 5. Verify: WETH was consumed (intermediate step completed)
        assertEq(
            IERC20(WETH).balanceOf(address(strategy)),
            0,
            "WETH left over - native to want swap incomplete"
        );

        // 6. Verify: Morpho shares increased (funds redeposited)
        uint256 morphoSharesAfter = IERC4626(MORPHO_RE7_USDC_VAULT).balanceOf(address(strategy));
        assertGt(morphoSharesAfter, morphoSharesBefore, "Morpho shares did not increase");

        // 7. Verify: vault balance increased after locked profit releases
        vm.warp(block.timestamp + 2 days);
        uint256 vaultBalAfter = vault.balance();
        assertGt(vaultBalAfter, vaultBalBefore, "vault balance did not increase after harvest");

        // 8. Verify: lastHarvest timestamp updated
        assertGt(strategy.lastHarvest(), 0, "lastHarvest not set");
    }

    /// @dev Verifies that harvest with zero rewards is a no-op.
    function test_harvest_with_no_rewards_is_noop() public {
        _depositAs(user, 1_000e6);

        uint256 vaultBalBefore = vault.balance();
        uint256 lastHarvestBefore = strategy.lastHarvest();

        vm.prank(owner);
        strategy.harvest();

        assertApproxEqAbs(vault.balance(), vaultBalBefore, 1, "balance changed on empty harvest");
        assertEq(strategy.lastHarvest(), lastHarvestBefore, "lastHarvest updated on empty harvest");
    }

    /// @dev Dust reward amount should not revert.
    function test_harvest_dust_reward_below_min() public {
        _depositAs(user, 1_000e6);

        deal(WLD, address(strategy), 1); // 1 wei WLD

        uint256 vaultBalBefore = vault.balance();
        vm.prank(owner);
        strategy.harvest();

        uint256 vaultBalAfter = vault.balance();
        assertGe(vaultBalAfter, vaultBalBefore, "vault balance decreased");
    }

    /// @dev Verify share price increases after harvest with rewards.
    function test_share_price_increases_after_harvest() public {
        _depositAs(user, 10_000e6);

        uint256 priceBefore = vault.getPricePerFullShare();

        deal(WLD, address(strategy), 1_000e18); // 1,000 WLD
        vm.prank(owner);
        strategy.harvest();

        // Warp past lock duration so locked profit is fully released
        vm.warp(block.timestamp + 2 days);

        uint256 priceAfter = vault.getPricePerFullShare();
        assertGt(priceAfter, priceBefore, "share price did not increase after harvest");
    }

    /// @dev Multiple harvests accumulate yield correctly.
    function test_multiple_harvests_compound() public {
        _depositAs(user, 10_000e6);

        uint256 vaultBalStart = vault.balance();

        // Harvest 1
        deal(WLD, address(strategy), 500e18);
        vm.prank(owner);
        strategy.harvest();
        vm.warp(block.timestamp + 1 days);

        uint256 vaultBalMid = vault.balance();
        assertGt(vaultBalMid, vaultBalStart, "first harvest didn't increase balance");

        // Harvest 2
        deal(WLD, address(strategy), 500e18);
        vm.prank(owner);
        strategy.harvest();
        vm.warp(block.timestamp + 1 days);

        uint256 vaultBalEnd = vault.balance();
        assertGt(vaultBalEnd, vaultBalMid, "second harvest didn't increase balance");
    }

    /// @dev Full cycle: deposit -> harvest -> withdraw. User gets more than they put in.
    function test_full_cycle_deposit_harvest_withdraw() public {
        uint256 depositAmount = 10_000e6;
        _depositAs(user, depositAmount);

        deal(WLD, address(strategy), 1_000e18);
        vm.prank(owner);
        strategy.harvest();

        // Warp past lock duration
        vm.warp(block.timestamp + 2 days);

        // Withdraw all
        uint256 shares = vault.balanceOf(user);
        vm.prank(user);
        vault.withdraw(shares);

        uint256 finalBalance = IERC20(USDC).balanceOf(user);
        assertGt(finalBalance, depositAmount, "user didn't profit from harvest");
    }

    /// @dev Verify harvest reverts for non-manager.
    function test_harvest_reverts_for_non_manager() public {
        _depositAs(user, 1_000e6);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(BaseAllToNativeFactoryStrat.NotManager.selector);
        strategy.harvest();
    }
}
