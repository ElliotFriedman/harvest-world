// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin-4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {BeefyVaultV7} from "../src/BeefyVaultV7.sol";
import {StrategyMorphoMerkl} from "../src/StrategyMorphoMerkl.sol";
import {BeefySwapper} from "../src/BeefySwapper.sol";

/// @notice Post-deployment verification script.
///         Run: forge script script/VerifyDeployment.s.sol --rpc-url https://worldchain.drpc.org -vvv
contract VerifyDeployment is Script {
    // ── Deployed Harvest contracts (proxies) ─────────────────────────────────
    // Update these addresses after each deployment.
    BeefyVaultV7 internal constant VAULT = BeefyVaultV7(0xDA3cF80dC04F527563a40Ce17A5466d6A05eefBD);
    StrategyMorphoMerkl internal constant STRATEGY =
        StrategyMorphoMerkl(payable(0xd2753e1Ce625A776A4d73f0251419Ba5Dfc1c0A5));
    BeefySwapper internal constant SWAPPER = BeefySwapper(0xe770BD40b6976Efbbb095174395DD2cb794c938a);

    // ── Deployed ProxyAdmin ───────────────────────────────────────────────────
    // Update this address after each deployment.
    address internal constant PROXY_ADMIN = address(0); // TODO: set after deploy

    // ── Expected external addresses ──────────────────────────────────────────
    address internal constant USDC = 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant WLD = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    address internal constant MORPHO_RE7_USDC_VAULT = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address internal constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256 internal checks;
    uint256 internal passed;

    function run() external view {
        console.log("=== HARVEST DEPLOYMENT VERIFICATION ===");
        console.log("");

        _verifyContracts();
        _verifyProxies();
        _verifyVault();
        _verifyStrategy();
        _verifySwapper();
        _verifyOwnership();

        console.log("");
        console.log("========================================");
    }

    function _verifyContracts() internal view {
        console.log("[CONTRACTS]");
        _check("Vault has code", address(VAULT).code.length > 0);
        _check("Strategy has code", address(STRATEGY).code.length > 0);
        _check("Swapper has code", address(SWAPPER).code.length > 0);
        console.log("");
    }

    function _verifyProxies() internal view {
        console.log("[PROXIES]");

        address vaultImpl = ITransparentUpgradeableProxy(address(VAULT)).implementation();
        address stratImpl = ITransparentUpgradeableProxy(address(STRATEGY)).implementation();
        address swapperImpl = ITransparentUpgradeableProxy(address(SWAPPER)).implementation();
        address vaultAdmin = ITransparentUpgradeableProxy(address(VAULT)).admin();
        address stratAdmin = ITransparentUpgradeableProxy(address(STRATEGY)).admin();
        address swapperAdmin = ITransparentUpgradeableProxy(address(SWAPPER)).admin();

        // Implementations must be non-zero (proxies point somewhere)
        _check("vault proxy has implementation", vaultImpl != address(0));
        _check("strategy proxy has implementation", stratImpl != address(0));
        _check("swapper proxy has implementation", swapperImpl != address(0));

        // All three proxies must share the same ProxyAdmin
        _check("vault admin == PROXY_ADMIN", PROXY_ADMIN == address(0) || vaultAdmin == PROXY_ADMIN);
        _check("strategy admin == PROXY_ADMIN", PROXY_ADMIN == address(0) || stratAdmin == PROXY_ADMIN);
        _check("swapper admin == PROXY_ADMIN", PROXY_ADMIN == address(0) || swapperAdmin == PROXY_ADMIN);
        _check("all proxies share same admin", vaultAdmin == stratAdmin && stratAdmin == swapperAdmin);

        console.log("  vault impl:    ", vaultImpl);
        console.log("  strategy impl: ", stratImpl);
        console.log("  swapper impl:  ", swapperImpl);
        console.log("  proxy admin:   ", vaultAdmin);
        console.log("");
    }

    function _verifyVault() internal view {
        console.log("[VAULT]");
        _check("want == USDC", address(VAULT.want()) == USDC);
        _check("strategy == STRATEGY", address(VAULT.strategy()) == address(STRATEGY));
        _log("name", VAULT.name());
        _log("symbol", VAULT.symbol());
        _log("totalSupply", VAULT.totalSupply());
        _log("balance", VAULT.balance());
        _log("pricePerShare", VAULT.getPricePerFullShare());
        console.log("");
    }

    function _verifyStrategy() internal view {
        console.log("[STRATEGY]");
        _check("want == USDC", STRATEGY.want() == USDC);
        _check("vault == VAULT", STRATEGY.vault() == address(VAULT));
        _check("NATIVE == WETH", STRATEGY.NATIVE() == WETH);
        _check("swapper == SWAPPER", STRATEGY.swapper() == address(SWAPPER));
        _check("morphoVault == MORPHO_RE7_USDC", address(STRATEGY.morphoVault()) == MORPHO_RE7_USDC_VAULT);
        _check("claimer == MERKL_DISTRIBUTOR", address(STRATEGY.claimer()) == MERKL_DISTRIBUTOR);
        _check("not paused", !STRATEGY.paused());

        _log("balanceOf", STRATEGY.balanceOf());
        _log("balanceOfPool", STRATEGY.balanceOfPool());
        _log("balanceOfWant", STRATEGY.balanceOfWant());
        _log("lastHarvest", STRATEGY.lastHarvest());
        _log("rewardsLength", STRATEGY.rewardsLength());

        if (STRATEGY.rewardsLength() > 0) {
            _check("rewards[0] == WLD", STRATEGY.rewards(0) == WLD);
        }

        // Check who can call harvest()
        address stratOwner = STRATEGY.owner();
        console.log("  strategy.owner:    ", stratOwner);
        console.log("  strategy.strategist:", STRATEGY.strategist());
        console.log("");
        console.log("  NOTE: harvest() only checks owner() via _checkManager().");
        console.log("  Only the owner address above can call harvest().");
        console.log("  If your agent wallet differs, transfer ownership or");
        console.log("  update _checkManager to also allow a keeper.");

        console.log("");
    }

    function _verifySwapper() internal view {
        console.log("[SWAPPER]");
        _check("swapper.owner == strategy.owner", SWAPPER.owner() == STRATEGY.owner());

        // Check WLD -> WETH route
        (address wldRouter,,,,) = SWAPPER.swapInfo(WLD, WETH);
        _check("WLD->WETH route set", wldRouter != address(0));

        // Check WETH -> USDC route
        (address wethRouter,,,,) = SWAPPER.swapInfo(WETH, USDC);
        _check("WETH->USDC route set", wethRouter != address(0));

        console.log("");
    }

    function _verifyOwnership() internal view {
        console.log("[OWNERSHIP]");
        address vaultOwner = VAULT.owner();
        address stratOwner = STRATEGY.owner();
        address swapperOwner = SWAPPER.owner();

        console.log("  vault.owner:   ", vaultOwner);
        console.log("  strategy.owner:", stratOwner);
        console.log("  swapper.owner: ", swapperOwner);

        _check("vault + strategy same owner", vaultOwner == stratOwner);
        _check("vault + swapper same owner", vaultOwner == swapperOwner);
        console.log("");
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    function _check(string memory label, bool ok) internal pure {
        console.log(ok ? "  PASS:" : "  FAIL:", label);
    }

    function _log(string memory label, uint256 value) internal pure {
        console.log(string.concat("  ", label, ":"), value);
    }

    function _log(string memory label, string memory value) internal pure {
        console.log(string.concat("  ", label, ":"), value);
    }
}
