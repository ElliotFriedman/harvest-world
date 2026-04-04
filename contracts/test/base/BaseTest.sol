// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAllowanceTransfer} from "@permit2/interfaces/IAllowanceTransfer.sol";

import {HarvestDeployer} from "../../script/deployers/HarvestDeployer.sol";
import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorphoMerkl} from "../../src/StrategyMorphoMerkl.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockBeefySwapper} from "../mocks/MockBeefySwapper.sol";
import {MockMerklClaimer} from "../mocks/MockMerklClaimer.sol";
import {MockMorphoVault} from "../mocks/MockMorphoVault.sol";
import {MockPermit2} from "../mocks/MockPermit2.sol";

abstract contract BaseTest is Test {
    address internal constant PERMIT2_ADDR = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    // WETH on World Chain mainnet — hardcoded in BaseAllToNativeFactoryStrat.NATIVE
    address internal constant NATIVE_ADDR = 0x4200000000000000000000000000000000000006;

    IAllowanceTransfer internal constant PERMIT2 = IAllowanceTransfer(PERMIT2_ADDR);

    // Deployed system
    BeefyVaultV7 internal vault;
    StrategyMorphoMerkl internal strategy;

    // Mocks
    MockERC20 internal want; // USDC — 6 decimals
    MockERC20 internal native; // WETH — 18 decimals, etched to NATIVE_ADDR
    MockERC20 internal rewardToken; // MORPHO — 18 decimals
    MockMorphoVault internal morphoVault;
    MockBeefySwapper internal swapper;
    MockMerklClaimer internal claimer;

    // Actors
    address internal owner;
    address internal strategist;
    address internal feeRecipient;
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
        strategist = makeAddr("strategist");
        feeRecipient = makeAddr("feeRecipient");
        user = makeAddr("user");
    }

    function _deployMocks() internal virtual {
        want = new MockERC20("USD Coin", "USDC", 6);
        rewardToken = new MockERC20("Morpho Token", "MORPHO", 18);

        // Deploy WETH mock at the hardcoded NATIVE address used by the strategy constant.
        // vm.etch copies bytecode; vm.store sets the _decimals slot (slot 5 in MockERC20).
        MockERC20 wethImpl = new MockERC20("Wrapped Ether", "WETH", 18);
        vm.etch(NATIVE_ADDR, address(wethImpl).code);
        vm.store(NATIVE_ADDR, bytes32(uint256(5)), bytes32(uint256(18)));
        native = MockERC20(NATIVE_ADDR);

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
            swapper: address(swapper),
            strategist: strategist,
            feeRecipient: feeRecipient
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo Morpho USDC", vaultSymbol: "mooMorphoUSDC", harvestOnDeposit: false, rewards: rewards
        });

        // owner becomes msg.sender for all external calls → owner of vault and strategy
        vm.startPrank(owner);
        HarvestDeployer.Deployment memory d = HarvestDeployer.deploy(ext, params);
        vm.stopPrank();

        vault = d.vault;
        strategy = d.strategy;
    }

    function _postSetup() internal virtual {
        // Swap rates: rewardToken → WETH 1:1, WETH → USDC 1e6 (1 WETH = 1 USDC in tests)
        swapper.setSwapRate(address(rewardToken), NATIVE_ADDR, 1e18);
        swapper.setSwapRate(NATIVE_ADDR, address(want), 1e6);

        // Pre-fund swapper with output tokens
        deal(NATIVE_ADDR, address(swapper), 1_000 ether);
        deal(address(want), address(swapper), 100_000e6);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Mint want to `depositor`, approve Permit2, then deposit into vault.
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
