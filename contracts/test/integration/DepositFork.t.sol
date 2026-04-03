// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin-4/contracts/interfaces/IERC4626.sol";
import {IAllowanceTransfer} from "@permit2/interfaces/IAllowanceTransfer.sol";

import {HarvestDeployer} from "../../script/deployers/HarvestDeployer.sol";
import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorpho} from "../../src/StrategyMorpho.sol";
import {BaseAllToNativeFactoryStrat} from "../../src/BaseAllToNativeFactoryStrat.sol";

import {MockStrategyFactory} from "../mocks/MockStrategyFactory.sol";
import {MockFeeConfig} from "../mocks/MockFeeConfig.sol";
import {MockBeefySwapper} from "../mocks/MockBeefySwapper.sol";

/// @notice Fork tests against World Chain mainnet (chainId 480).
///         Set WORLD_CHAIN_RPC_URL in the environment to run these.
///         They are skipped automatically when the env var is absent.
///
///         Run with:
///         WORLD_CHAIN_RPC_URL=<url> forge test --match-contract DepositForkTest -vvv
contract DepositForkTest is Test {
    // ── World Chain mainnet addresses ─────────────────────────────────────────
    address internal constant USDC = 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant MORPHO_RE7_USDC_VAULT = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address internal constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address internal constant MORPHO_TOKEN = 0xe2108e43dBD43c9Dc6E494F86c4C4D938Bd10f56;
    IAllowanceTransfer internal constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // ── Deployed system ───────────────────────────────────────────────────────
    BeefyVaultV7 internal vault;
    StrategyMorpho internal strategy;

    // ── Beefy infra mocks (not yet deployed on World Chain) ───────────────────
    MockStrategyFactory internal strategyFactory;
    MockFeeConfig internal feeConfig;
    MockBeefySwapper internal swapper;

    // ── Actors ────────────────────────────────────────────────────────────────
    address internal owner;
    address internal keeper;
    address internal strategist;
    address internal beefyFeeRecipient;
    address internal user;

    /// @dev Directly set verifiedHumans[_user] via vm.store (slot 204).
    function _setVerifiedInTest(address _user, bool _status) internal {
        bytes32 slot = keccak256(abi.encode(_user, uint256(204)));
        vm.store(address(vault), slot, _status ? bytes32(uint256(1)) : bytes32(uint256(0)));
    }

    uint256 internal worldChainFork;

    function setUp() public {
        string memory rpcUrl = vm.envOr("WORLD_CHAIN_RPC_URL", string("https://worldchain.drpc.org"));

        // Pin to a recent block so all tests in a run share the same cached state.
        // Update this periodically or remove the pin to test against latest.
        uint256 forkBlock = vm.envOr("WORLD_CHAIN_FORK_BLOCK", uint256(27956180));
        worldChainFork = vm.createFork(rpcUrl, forkBlock);
        vm.selectFork(worldChainFork);

        owner = makeAddr("owner");
        keeper = makeAddr("keeper");
        strategist = makeAddr("strategist");
        beefyFeeRecipient = makeAddr("beefyFeeRecipient");
        user = makeAddr("user");

        _deployInfrastructure();
        _deploySystem();

        // Mark user as verified human (bypass World ID for test)
        _setVerifiedInTest(user, true);
    }

    // ── Infrastructure ────────────────────────────────────────────────────────

    function _deployInfrastructure() internal {
        feeConfig = new MockFeeConfig();
        strategyFactory = new MockStrategyFactory(WETH, keeper, beefyFeeRecipient, address(feeConfig));
        swapper = new MockBeefySwapper();
    }

    function _deploySystem() internal {
        address[] memory rewards = new address[](1);
        rewards[0] = MORPHO_TOKEN;

        HarvestDeployer.ExternalAddresses memory ext = HarvestDeployer.ExternalAddresses({
            want: USDC,
            depositToken: address(0),
            morphoVault: MORPHO_RE7_USDC_VAULT,
            claimer: MERKL_DISTRIBUTOR,
            strategyFactory: address(strategyFactory),
            swapper: address(swapper),
            strategist: strategist
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo World Morpho USDC",
            vaultSymbol: "mooWorldMorphoUSDC",
            harvestOnDeposit: false,
            rewards: rewards,
            externalNullifierHash: 1 // test placeholder
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

    /// @dev Unverified user is blocked by onlyHuman.
    function test_deposit_reverts_for_unverified() public {
        address stranger = makeAddr("stranger");
        deal(USDC, stranger, 100e6);

        vm.startPrank(stranger);
        IERC20(USDC).approve(address(PERMIT2), 100e6);
        PERMIT2.approve(USDC, address(vault), uint160(100e6), uint48(block.timestamp + 1 days));
        vm.expectRevert("Harvest: humans only");
        vault.deposit(100e6);
        vm.stopPrank();
    }

    /// @dev Second depositor gets proportional shares based on current vault NAV.
    function test_deposit_two_users_proportional_shares() public {
        address user2 = makeAddr("user2");
        _setVerifiedInTest(user2, true);

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
        // Price should remain very close to 1e18 immediately after deposit
        assertApproxEqRel(vault.getPricePerFullShare(), 1e18, 0.001e18, "price drifted >0.1%");
    }

    /// @dev Vault balance reflects funds deployed in Morpho.
    function test_vault_balance_reflects_morpho() public {
        uint256 amount = 500e6;
        _depositAs(user, amount);

        // vault.balance() = strategy.balanceOf() ≈ deposited amount
        assertApproxEqRel(vault.balance(), amount, 0.001e18, "vault balance off by >0.1%");
    }

    /// @dev depositAll: deposits user's entire USDC balance.
    function test_deposit_all() public {
        uint256 amount = 200e6;
        deal(USDC, user, amount);

        vm.startPrank(user);
        IERC20(USDC).approve(address(PERMIT2), amount);
        PERMIT2.approve(USDC, address(vault), uint160(amount), uint48(block.timestamp + 1 days));
        vault.depositAll();
        vm.stopPrank();

        assertGt(vault.balanceOf(user), 0, "no shares after depositAll");
        assertEq(IERC20(USDC).balanceOf(user), 0, "USDC balance not zero");
    }

    /// @dev Deposit without Permit2 approval reverts (not merely returns 0).
    function test_deposit_reverts_without_permit2_approval() public {
        deal(USDC, user, 100e6);

        vm.prank(user);
        vm.expectRevert(); // MockPermit2 or real Permit2 will revert
        vault.deposit(100e6);
    }
}
