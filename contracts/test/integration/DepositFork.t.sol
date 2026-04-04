// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin-4/contracts/interfaces/IERC4626.sol";
import {IAllowanceTransfer} from "@permit2/interfaces/IAllowanceTransfer.sol";

import {HarvestDeployer} from "../../script/deployers/HarvestDeployer.sol";
import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorphoMerkl} from "../../src/StrategyMorphoMerkl.sol";

import {MockBeefySwapper} from "../mocks/MockBeefySwapper.sol";

/// @notice Fork tests against World Chain mainnet (chainId 480).
///         Set WORLD_CHAIN_RPC_URL in the environment to run these.
///
///         Run with:
///         WORLD_CHAIN_RPC_URL=<url> forge test --match-contract DepositForkTest -vvv
contract DepositForkTest is Test {
    // ── World Chain mainnet addresses ─────────────────────────────────────────
    address internal constant USDC = 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant MORPHO_RE7_USDC_VAULT = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address internal constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address internal constant WLD = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    IAllowanceTransfer internal constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // ── Deployed Harvest contracts (from 480.json) ─────────────────────────
    address internal constant DEPLOYED_VAULT = 0xDA3cF80dC04F527563a40Ce17A5466d6A05eefBD;
    address payable internal constant DEPLOYED_STRATEGY = payable(0xd2753e1Ce625A776A4d73f0251419Ba5Dfc1c0A5);

    // ── Deployed system ───────────────────────────────────────────────────────
    BeefyVaultV7 internal vault;
    StrategyMorphoMerkl internal strategy;

    MockBeefySwapper internal swapper;

    // ── Actors ────────────────────────────────────────────────────────────────
    address internal owner;
    address internal strategist;
    address internal feeRecipient;
    address internal user;

    uint256 internal worldChainFork;

    function setUp() public {
        string memory rpcUrl = vm.envOr("WORLD_CHAIN_RPC_URL", string("https://worldchain.drpc.org"));
        worldChainFork = vm.createFork(rpcUrl);
        vm.selectFork(worldChainFork);

        user = makeAddr("user");

        // Use deployed contracts if they exist on-chain, otherwise deploy fresh
        if (DEPLOYED_VAULT.code.length > 0) {
            vault = BeefyVaultV7(DEPLOYED_VAULT);
            strategy = StrategyMorphoMerkl(DEPLOYED_STRATEGY);
            owner = vault.owner();
        } else {
            owner = makeAddr("owner");
            strategist = makeAddr("strategist");
            feeRecipient = makeAddr("feeRecipient");
            _deployInfrastructure();
            vm.startPrank(owner);
            _deploySystem();
            vm.stopPrank();
        }
    }

    // ── Infrastructure ────────────────────────────────────────────────────────

    function _deployInfrastructure() internal {
        swapper = new MockBeefySwapper();
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
            strategist: strategist,
            feeRecipient: feeRecipient
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo World Morpho USDC",
            vaultSymbol: "mooWorldMorphoUSDC",
            harvestOnDeposit: false,
            rewards: rewards
        });

        vm.startPrank(owner);
        HarvestDeployer.Deployment memory d = HarvestDeployer.deploy(ext, params);
        vm.stopPrank();

        vault = d.vault;
        strategy = d.strategy;
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    /// @dev Give `depositor` real USDC and run the full Permit2 deposit flow.
    function _depositAs(address depositor, uint256 amount) internal {
        deal(USDC, depositor, amount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(PERMIT2), amount);
        // casting to 'uint160' is safe because deposit amounts are bounded by real token supplies (< 2^160)
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.approve(USDC, address(vault), uint160(amount), uint48(block.timestamp + 1 days));
        vault.deposit(amount);
        vm.stopPrank();
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    /// @dev Happy path: verified user deposits USDC, receives vault shares,
    ///      funds are deployed into the real Morpho Re7 USDC vault.
    function test_deposit_happy_path() public {
        uint256 depositAmount = 100e6; // 100 USDC

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 morphoSharesBefore = IERC4626(MORPHO_RE7_USDC_VAULT).balanceOf(address(strategy));

        _depositAs(user, depositAmount);

        uint256 sharesAfter = vault.balanceOf(user);
        uint256 morphoSharesAfter = IERC4626(MORPHO_RE7_USDC_VAULT).balanceOf(address(strategy));

        // User received vault shares
        assertGt(sharesAfter, sharesBefore, "no vault shares minted");

        // Funds are deployed into Morpho
        assertGt(morphoSharesAfter, morphoSharesBefore, "no Morpho shares acquired");

        // Vault holds no idle USDC (earn() was called)
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "vault holds idle USDC");
    }

    /// @dev Second depositor gets proportional shares based on current vault NAV.
    function test_deposit_two_users_proportional_shares() public {
        address user2 = makeAddr("user2");

        _depositAs(user, 100e6);
        _depositAs(user2, 50e6);

        uint256 shares1 = vault.balanceOf(user);
        uint256 shares2 = vault.balanceOf(user2);

        // user2 deposited half of user1, should have ~half the shares
        assertApproxEqRel(shares2, shares1 / 2, 0.01e18, "share ratio off by >1%");
    }

    /// @dev Full round-trip: deposit then withdraw recovers approximately the deposited amount.
    function test_withdraw_round_trip() public {
        uint256 depositAmount = 100e6;
        _depositAs(user, depositAmount);

        uint256 shares = vault.balanceOf(user);
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);

        vm.prank(user);
        vault.withdraw(shares);

        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 received = usdcAfter - usdcBefore;

        // Allow up to 0.1% slippage/rounding from ERC4626 share math
        assertApproxEqRel(received, depositAmount, 0.001e18, "round-trip loss >0.1%");
    }

    /// @dev getPricePerFullShare starts at 1e18 for an empty vault.
    function test_price_per_share_initial() public view {
        assertEq(vault.getPricePerFullShare(), 1e18);
    }

    /// @dev After deposit, price per share stays ~1e18 (no yield yet).
    function test_price_per_share_after_deposit() public {
        _depositAs(user, 1000e6);
        assertApproxEqRel(vault.getPricePerFullShare(), 1e18, 0.001e18, "price drifted >0.1%");
    }

    /// @dev Vault balance reflects funds deployed in Morpho.
    function test_vault_balance_reflects_morpho() public {
        uint256 amount = 500e6;
        _depositAs(user, amount);

        assertApproxEqRel(vault.balance(), amount, 0.001e18, "vault balance off by >0.1%");
    }

    /// @dev depositAll: deposits user's entire USDC balance.
    function test_deposit_all() public {
        uint256 amount = 200e6;
        deal(USDC, user, amount);

        vm.startPrank(user);
        IERC20(USDC).approve(address(PERMIT2), amount);
        // casting to 'uint160' is safe because deposit amounts are bounded by real token supplies (< 2^160)
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.approve(USDC, address(vault), uint160(amount), uint48(block.timestamp + 1 days));
        vault.depositAll();
        vm.stopPrank();

        assertGt(vault.balanceOf(user), 0, "no shares after depositAll");
        assertEq(IERC20(USDC).balanceOf(user), 0, "USDC balance not zero");
    }

    /// @dev Deposit without Permit2 approval reverts.
    function test_deposit_reverts_without_permit2_approval() public {
        deal(USDC, user, 100e6);

        vm.prank(user);
        vm.expectRevert();
        vault.deposit(100e6);
    }
}
