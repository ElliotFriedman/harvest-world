// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAllowanceTransfer} from "@permit2/interfaces/IAllowanceTransfer.sol";

import {HarvestDeployer} from "../../script/deployers/HarvestDeployer.sol";
import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorpho} from "../../src/StrategyMorpho.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStrategyFactory} from "../mocks/MockStrategyFactory.sol";
import {MockBeefySwapper} from "../mocks/MockBeefySwapper.sol";
import {MockFeeConfig} from "../mocks/MockFeeConfig.sol";
import {MockMerklClaimer} from "../mocks/MockMerklClaimer.sol";
import {MockMorphoVault} from "../mocks/MockMorphoVault.sol";
import {MockPermit2} from "../mocks/MockPermit2.sol";

abstract contract BaseTest is Test {
    address internal constant PERMIT2_ADDR = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IAllowanceTransfer internal constant PERMIT2 = IAllowanceTransfer(PERMIT2_ADDR);

    // Deployed system
    BeefyVaultV7 internal vault;
    StrategyMorpho internal strategy;

    // Mocks
    MockERC20 internal want; // USDC — 6 decimals
    MockERC20 internal native; // WETH — 18 decimals
    MockERC20 internal rewardToken; // MORPHO — 18 decimals
    MockMorphoVault internal morphoVault;
    MockStrategyFactory internal strategyFactory;
    MockBeefySwapper internal swapper;
    MockFeeConfig internal feeConfig;
    MockMerklClaimer internal claimer;

    // Actors
    address internal owner;
    address internal keeper;
    address internal strategist;
    address internal beefyFeeRecipient;
    address internal user;

    function setUp() public virtual {
        _createActors();
        _deployMocks();
        _deployPermit2();
        _deploySystem();
        _postSetup();
    }

    function _createActors() internal virtual {
        owner = makeAddr("owner");
        keeper = makeAddr("keeper");
        strategist = makeAddr("strategist");
        beefyFeeRecipient = makeAddr("beefyFeeRecipient");
        user = makeAddr("user");
    }

    function _deployMocks() internal virtual {
        want = new MockERC20("USD Coin", "USDC", 6);
        native = new MockERC20("Wrapped Ether", "WETH", 18);
        rewardToken = new MockERC20("Morpho Token", "MORPHO", 18);

        feeConfig = new MockFeeConfig();

        strategyFactory = new MockStrategyFactory(address(native), keeper, beefyFeeRecipient, address(feeConfig));

        swapper = new MockBeefySwapper();
        claimer = new MockMerklClaimer();

        morphoVault = new MockMorphoVault(address(want), "Morpho USDC Vault", "mUSDC", 6);
    }

    /// @dev Deploy MockPermit2 at the hardcoded address the vault uses.
    function _deployPermit2() internal virtual {
        MockPermit2 tmpPermit2 = new MockPermit2();
        vm.etch(PERMIT2_ADDR, address(tmpPermit2).code);
    }

    function _deploySystem() internal virtual {
        address[] memory rewards = new address[](1);
        rewards[0] = address(rewardToken);

        HarvestDeployer.ExternalAddresses memory ext = HarvestDeployer.ExternalAddresses({
            want: address(want),
            depositToken: address(0),
            morphoVault: address(morphoVault),
            claimer: address(claimer),
            strategyFactory: address(strategyFactory),
            swapper: address(swapper),
            strategist: strategist
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo Morpho USDC",
            vaultSymbol: "mooMorphoUSDC",
            harvestOnDeposit: false,
            rewards: rewards,
            externalNullifierHash: 1 // test placeholder
        });

        // owner becomes msg.sender for all external calls → owner of vault and strategy
        vm.startPrank(owner);
        HarvestDeployer.Deployment memory d = HarvestDeployer.deploy(ext, params);
        vm.stopPrank();

        vault = d.vault;
        strategy = d.strategy;
    }

    function _postSetup() internal virtual {
        // Set swap rates to handle decimal differences (want=6 dec, native=18 dec):
        //   rewardToken (18 dec) → native (18 dec): 1:1
        //   want (6 dec) → native (18 dec): 1e30, so round-trip ≈ identity
        //   native (18 dec) → want (6 dec): 1e6, so (1e30 * 1e6 = 1e36 = 1e18 * 1e18 ✓)
        swapper.setSwapRate(address(rewardToken), address(native), 1e18);
        swapper.setSwapRate(address(want), address(native), 1e30);
        swapper.setSwapRate(address(native), address(want), 1e6);

        // Pre-fund swapper with enough output tokens for any reasonable test swap
        deal(address(native), address(swapper), 1_000 ether);
        deal(address(want), address(swapper), 100_000e6);

        // Mark the test user as a verified human
        _setVerifiedInTest(user, true);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Directly set verifiedHumans[user] via vm.store (slot 204).
    ///      Bypasses World ID proof verification for unit testing.
    function _setVerifiedInTest(address _user, bool _status) internal {
        bytes32 slot = keccak256(abi.encode(_user, uint256(204)));
        vm.store(address(vault), slot, _status ? bytes32(uint256(1)) : bytes32(uint256(0)));
    }

    /// @dev Mint want to `depositor`, approve Permit2, then deposit into vault.
    ///      The depositor must already be verified (call _setVerifiedInTest first).
    function _depositAs(address depositor, uint256 amount) internal {
        deal(address(want), depositor, amount);
        vm.startPrank(depositor);
        want.approve(PERMIT2_ADDR, amount);
        // casting to 'uint160' is safe because test deposit amounts are bounded by real token supplies (< 2^160)
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.approve(address(want), address(vault), uint160(amount), uint48(block.timestamp + 1 days));
        vault.deposit(amount);
        vm.stopPrank();
    }

    /// @dev Simulate yield by bumping the Morpho vault exchange rate.
    /// @param newRate e.g. 1.05e18 for 5% yield
    function _simulateYield(uint256 newRate) internal {
        morphoVault.setExchangeRate(newRate);
    }
}
