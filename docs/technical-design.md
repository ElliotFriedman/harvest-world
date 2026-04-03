# HARVEST v2 -- Technical Design Document
## Yield Aggregator on World Chain (Beefy Finance Fork)

**Version:** 1.0
**Date:** April 3, 2026
**Status:** Implementation-ready
**Companion to:** `product-spec.md` (Product Specification)

This is the v2 evolution of Harvest. v1 claimed scattered Merkl rewards. v2 adds autocompounding yield vaults built by forking Beefy Finance contracts, deployed on World Chain, targeting Morpho lending vaults. A developer reads this and starts building without questions.

---

## 1. BEEFY FORK GUIDE

### 1.1 Source Repository

```
git clone https://github.com/beefyfinance/beefy-contracts.git
cd beefy-contracts
git checkout main  # pin to a specific commit after audit
```

### 1.2 Files to Copy

Copy these files into your Foundry project at `contracts/src/`:

```
From beefy-contracts/contracts/:
  vaults/
    BeefyVaultV7.sol              -> contracts/src/vaults/HarvestVaultV7.sol
    BeefyVaultV7Factory.sol       -> contracts/src/vaults/HarvestVaultFactory.sol
  strategies/
    Morpho/
      StrategyMorpho.sol          -> contracts/src/strategies/StrategyMorpho.sol
  utils/
    UniswapV3Utils.sol            -> contracts/src/utils/UniV3Utils.sol
  interfaces/
    common/
      IWrappedNative.sol          -> contracts/src/interfaces/IWrappedNative.sol
      IERC20Extended.sol          -> contracts/src/interfaces/IERC20Extended.sol
      IFeeConfig.sol              -> contracts/src/interfaces/IFeeConfig.sol
    morpho/
      IMorpho.sol                 -> contracts/src/interfaces/IMorpho.sol
      IMetaMorpho.sol             -> contracts/src/interfaces/IMetaMorpho.sol
    beefy/
      IStrategyV7.sol             -> contracts/src/interfaces/IStrategyV7.sol
```

### 1.3 What to Strip

The goal is to remove governance overhead and complex fee infrastructure. We want the simplest possible vault + strategy that autocompounds Morpho yields on World Chain.

**Remove entirely:**

| File / Concept | Why |
|---|---|
| `BeefyFeeRecipient.sol` | Complex fee splitting to treasury, strategist, harvester. Replace with a single `feeRecipient` address. |
| `BeefyFeeConfig.sol` | On-chain fee config registry. Hardcode fees in the strategy. |
| `TimelockController.sol` | Governance timelock. Not needed for a hackathon vault. |
| `BeefySwapper.sol` | Generic token swap router. Replace with hardcoded Uniswap V3 path. |
| `BeefyOracle.sol` + all oracle adapters | Price oracle aggregator. Replace with Chainlink direct call or hardcode. |
| All governance contracts | `Ownable` with a single admin EOA is sufficient. |
| `StrategyPassiveManagerUniswap.sol` | Not relevant -- we target Morpho, not Uniswap LP. |

**Strip from BeefyVaultV7.sol (rename to HarvestVaultV7.sol):**

```solidity
// REMOVE these imports and references:
// - IBeefyFeeConfig references
// - IStrategyV7.beefyFeeRecipient() calls
// - Timelock modifier patterns

// KEEP:
// - ERC4626 vault logic (deposit, withdraw, redeem, convertToAssets, convertToShares)
// - Strategy link (strategy address, earn(), available())
// - Share price calculation (getPricePerFullShare)
// - Pause/unpause
// - Ownership (OwnableUpgradeable)
```

**Strip from StrategyMorpho.sol:**

```solidity
// REMOVE:
// - References to IBeefySwapper (the generic swap router)
// - References to IBeefyOracle (price oracle aggregator)
// - Complex fee tier lookup via IFeeConfig
// - Keeper/harvester role management (simplify to owner-only or open)

// REPLACE:
// - Swap logic: hardcode Uniswap V3 exactInput path for reward -> want
// - Fee logic: hardcode fee = 4.5% of harvest profit
//   - 3.0% to feeRecipient (protocol treasury)
//   - 1.0% to msg.sender (harvester incentive)
//   - 0.5% to strategist
// - Oracle: use Chainlink price feed or skip oracle entirely
```

### 1.4 Exact StrategyMorpho.sol Modifications

The Beefy StrategyMorpho deposits `want` tokens (e.g., USDC) into a MetaMorpho vault, earns yield, and claims Merkl rewards (typically WLD). On harvest, it swaps rewards back to `want` and redeposits.

Here is the simplified harvest function:

```solidity
// contracts/src/strategies/StrategyMorpho.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IMetaMorpho} from "../interfaces/IMetaMorpho.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";

contract StrategyMorpho is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // -- Immutable-ish config (set once in initialize) --
    address public vault;           // HarvestVaultV7
    address public want;            // e.g., USDC (0x79A02482A880bCE3B13e09Da970dC34db4CD24d1)
    address public morphoVault;     // MetaMorpho vault on World Chain
    address public swapRouter;      // Uniswap V3 SwapRouter on World Chain
    address public feeRecipient;    // Single address receives protocol fees
    address public strategist;      // Strategist fee recipient

    // -- Reward tokens (claimed via Merkl) --
    address[] public rewardTokens;

    // -- Hardcoded swap paths (reward -> want via Uniswap V3) --
    // Packed path: tokenA | fee | tokenB | fee | tokenC
    mapping(address => bytes) public swapPaths;

    // -- Fee structure (basis points, 10000 = 100%) --
    uint256 public constant TOTAL_FEE = 450;      // 4.5%
    uint256 public constant PROTOCOL_FEE = 300;    // 3.0% to feeRecipient
    uint256 public constant HARVEST_FEE = 100;     // 1.0% to caller
    uint256 public constant STRATEGIST_FEE = 50;   // 0.5% to strategist
    uint256 public constant FEE_DIVISOR = 10000;

    // -- Merkl distributor for reward claims --
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    event Harvest(address indexed caller, uint256 wantEarned, uint256 fee);
    event SwapPathSet(address indexed token, bytes path);

    function initialize(
        address _vault,
        address _want,
        address _morphoVault,
        address _swapRouter,
        address _feeRecipient,
        address _strategist,
        address[] calldata _rewardTokens,
        bytes[] calldata _swapPaths
    ) external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();

        vault = _vault;
        want = _want;
        morphoVault = _morphoVault;
        swapRouter = _swapRouter;
        feeRecipient = _feeRecipient;
        strategist = _strategist;

        require(_rewardTokens.length == _swapPaths.length, "length mismatch");
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            rewardTokens.push(_rewardTokens[i]);
            swapPaths[_rewardTokens[i]] = _swapPaths[i];
        }

        // Approve morpho vault to spend want
        IERC20(_want).safeApprove(_morphoVault, type(uint256).max);
    }

    // ============================================================
    // HARVEST -- the core function
    // ============================================================

    /// @notice Claims Merkl rewards, swaps to want, charges fees, redeposits.
    ///         Callable by anyone (harvester incentive = 1% of profit).
    /// @param merklUsers Merkl claim params -- users array
    /// @param merklTokens Merkl claim params -- tokens array
    /// @param merklAmounts Merkl claim params -- cumulative amounts
    /// @param merklProofs Merkl claim params -- merkle proofs
    function harvest(
        address[] calldata merklUsers,
        address[] calldata merklTokens,
        uint256[] calldata merklAmounts,
        bytes32[][] calldata merklProofs
    ) external whenNotPaused {
        // Step 1: Claim Merkl rewards
        if (merklUsers.length > 0) {
            IMerklDistributor(MERKL_DISTRIBUTOR).claim(
                merklUsers, merklTokens, merklAmounts, merklProofs
            );
        }

        // Step 2: Swap all reward tokens to want via Uniswap V3
        uint256 wantBefore = IERC20(want).balanceOf(address(this));

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address reward = rewardTokens[i];
            uint256 rewardBal = IERC20(reward).balanceOf(address(this));
            if (rewardBal == 0) continue;

            bytes memory path = swapPaths[reward];
            if (path.length == 0) continue;

            IERC20(reward).safeApprove(swapRouter, rewardBal);

            ISwapRouter(swapRouter).exactInput(
                ISwapRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: rewardBal,
                    amountOutMinimum: 0  // MEV protection via private mempool on World Chain
                })
            );
        }

        uint256 wantEarned = IERC20(want).balanceOf(address(this)) - wantBefore;
        if (wantEarned == 0) return;

        // Step 3: Charge fees
        uint256 protocolFee = (wantEarned * PROTOCOL_FEE) / FEE_DIVISOR;
        uint256 harvesterFee = (wantEarned * HARVEST_FEE) / FEE_DIVISOR;
        uint256 strategistFee = (wantEarned * STRATEGIST_FEE) / FEE_DIVISOR;

        if (protocolFee > 0) IERC20(want).safeTransfer(feeRecipient, protocolFee);
        if (harvesterFee > 0) IERC20(want).safeTransfer(msg.sender, harvesterFee);
        if (strategistFee > 0) IERC20(want).safeTransfer(strategist, strategistFee);

        // Step 4: Deposit remaining into Morpho vault
        uint256 remaining = IERC20(want).balanceOf(address(this));
        if (remaining > 0) {
            IMetaMorpho(morphoVault).deposit(remaining, address(this));
        }

        emit Harvest(msg.sender, wantEarned, protocolFee + harvesterFee + strategistFee);
    }

    // ============================================================
    // VAULT INTERFACE -- called by HarvestVaultV7
    // ============================================================

    /// @notice Deposit want into Morpho vault
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            IMetaMorpho(morphoVault).deposit(wantBal, address(this));
        }
    }

    /// @notice Withdraw want from Morpho vault back to the HarvestVaultV7
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal < _amount) {
            IMetaMorpho(morphoVault).withdraw(_amount - wantBal, address(this), address(this));
        }
        IERC20(want).safeTransfer(vault, _amount);
    }

    /// @notice Total want controlled by strategy (idle + deposited in Morpho)
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    /// @notice Idle want sitting in the strategy contract
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /// @notice Want deposited in the Morpho vault
    function balanceOfPool() public view returns (uint256) {
        uint256 shares = IERC20(morphoVault).balanceOf(address(this));
        if (shares == 0) return 0;
        return IMetaMorpho(morphoVault).convertToAssets(shares);
    }

    /// @notice Called on panic -- withdraw everything from Morpho
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        uint256 shares = IERC20(morphoVault).balanceOf(address(this));
        if (shares > 0) {
            IMetaMorpho(morphoVault).redeem(shares, address(this), address(this));
        }
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).safeTransfer(vault, wantBal);
    }

    // ============================================================
    // ADMIN
    // ============================================================

    function setSwapPath(address _token, bytes calldata _path) external onlyOwner {
        swapPaths[_token] = _path;
        emit SwapPathSet(_token, _path);
    }

    function addRewardToken(address _token, bytes calldata _path) external onlyOwner {
        rewardTokens.push(_token);
        swapPaths[_token] = _path;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}

interface IMerklDistributor {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
```

### 1.5 HarvestVaultV7.sol (Simplified Beefy Vault)

The vault is a standard ERC4626 wrapper. Users deposit `want` (USDC), receive `harvest-USDC` shares. The vault pushes funds to the strategy. Share price appreciates as harvests compound.

Key modifications from BeefyVaultV7:

```solidity
// contracts/src/vaults/HarvestVaultV7.sol
// Core changes from Beefy original:

// 1. Remove IFeeConfig dependency -- fees are in the strategy
// 2. Remove treasury address -- feeRecipient is on the strategy
// 3. Simplify strategy upgrade -- owner can set strategy, no timelock

// The vault's core logic is UNCHANGED from Beefy:
// - deposit(uint256 amount) -- pull want from user, push to strategy
// - withdraw(uint256 shares) -- burn shares, pull want from strategy
// - getPricePerFullShare() -- returns (balance() * 1e18) / totalSupply()
// - balance() -- vault idle want + strategy.balanceOf()
// - earn() -- push vault idle want to strategy

// Initialize with:
//   name: "Harvest USDC Vault"
//   symbol: "harvestUSDC"
//   strategy: address of StrategyMorpho
//   want: 0x79A02482A880bCE3B13e09Da970dC34db4CD24d1 (USDC on World Chain)
```

### 1.6 World Chain Morpho Vault Configuration

Known MetaMorpho vaults on World Chain (chain ID 480):

| Vault | Want Token | Morpho Vault Address | Description |
|---|---|---|---|
| Re7 USDC | USDC | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` | Gauntlet curated, diversified USDC lending |
| Re7 WETH | WETH | `0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca` | Re7 Labs curated WETH lending |

**For the hackathon, target Re7 USDC.** It has the deepest liquidity and USDC is the simplest UX story.

### 1.7 Swap Path Configuration

Merkl rewards on World Chain distribute WLD. The swap path converts WLD -> USDC via Uniswap V3.

```
WLD (0x2cFc85d8E48F8EAB294be644d9E25C3030863003)
  -> fee 3000 (0.3%)
  -> WETH (0x4200000000000000000000000000000000000006)
  -> fee 500 (0.05%)
  -> USDC (0x79A02482A880bCE3B13e09Da970dC34db4CD24d1)
```

Encoded as packed bytes for Uniswap V3 exactInput:

```solidity
bytes memory wldToUsdc = abi.encodePacked(
    address(0x2cFc85d8E48F8EAB294be644d9E25C3030863003), // WLD
    uint24(3000),                                          // 0.3% fee tier
    address(0x4200000000000000000000000000000000000006),   // WETH
    uint24(500),                                           // 0.05% fee tier
    address(0x79A02482A880bCE3B13e09Da970dC34db4CD24d1)    // USDC
);
```

---

## 2. CONTRACT DEPLOYMENT

### 2.1 Foundry Setup

```bash
# Create Foundry project alongside the Next.js app
mkdir -p contracts && cd contracts

# Initialize Foundry
forge init --no-git

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.1.0

# foundry.toml
```

```toml
# contracts/foundry.toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.24"
optimizer = true
optimizer_runs = 200
evm_version = "paris"

[rpc_endpoints]
world_chain = "${WORLD_CHAIN_RPC_URL}"
world_chain_sepolia = "https://worldchain-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}"

[etherscan]
world_chain = { key = "${WORLDSCAN_API_KEY}", url = "https://api.worldscan.org/api" }
```

### 2.2 Deployment Script

Deployment order: Factory -> Vault -> Strategy -> Link -> Initialize

```solidity
// contracts/script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HarvestVaultV7} from "../src/vaults/HarvestVaultV7.sol";
import {HarvestVaultFactory} from "../src/vaults/HarvestVaultFactory.sol";
import {StrategyMorpho} from "../src/strategies/StrategyMorpho.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployHarvest is Script {
    // -- World Chain Addresses --
    address constant USDC = 0x79A02482A880bCE3B13e09Da970dC34db4CD24d1;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WLD  = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;

    address constant MORPHO_USDC_VAULT = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address constant UNISWAP_V3_ROUTER = 0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6;
    address constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address strategist = vm.envAddress("STRATEGIST_ADDRESS");

        vm.startBroadcast(deployerKey);

        // ---- Step 1: Deploy Vault Implementation ----
        HarvestVaultV7 vaultImpl = new HarvestVaultV7();
        console.log("Vault implementation:", address(vaultImpl));

        // ---- Step 2: Deploy Vault Proxy ----
        bytes memory vaultInitData = abi.encodeCall(
            HarvestVaultV7.initialize,
            (
                address(0),       // strategy -- set after strategy deploy
                USDC,             // want
                "Harvest USDC",   // name
                "harvestUSDC",    // symbol
                0                 // approvalDelay (0 for hackathon)
            )
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInitData);
        address vault = address(vaultProxy);
        console.log("Vault proxy:", vault);

        // ---- Step 3: Deploy Strategy Implementation ----
        StrategyMorpho stratImpl = new StrategyMorpho();
        console.log("Strategy implementation:", address(stratImpl));

        // ---- Step 4: Deploy Strategy Proxy ----
        // Build WLD -> WETH -> USDC swap path
        bytes memory wldToUsdc = abi.encodePacked(
            WLD, uint24(3000), WETH, uint24(500), USDC
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = WLD;
        bytes[] memory swapPaths = new bytes[](1);
        swapPaths[0] = wldToUsdc;

        bytes memory stratInitData = abi.encodeCall(
            StrategyMorpho.initialize,
            (
                vault,              // vault
                USDC,               // want
                MORPHO_USDC_VAULT,  // morphoVault
                UNISWAP_V3_ROUTER,  // swapRouter
                feeRecipient,       // feeRecipient
                strategist,         // strategist
                rewardTokens,       // reward tokens
                swapPaths           // swap paths
            )
        );
        ERC1967Proxy stratProxy = new ERC1967Proxy(address(stratImpl), stratInitData);
        address strategy = address(stratProxy);
        console.log("Strategy proxy:", strategy);

        // ---- Step 5: Link vault to strategy ----
        HarvestVaultV7(vault).setStrategy(strategy);
        console.log("Vault linked to strategy");

        // ---- Step 6: Push initial deposit to strategy ----
        // (Only if deployer pre-funds the vault)
        // HarvestVaultV7(vault).earn();

        vm.stopBroadcast();

        // ---- Summary ----
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Chain ID:    480 (World Chain)");
        console.log("Vault:       ", vault);
        console.log("Strategy:    ", strategy);
        console.log("Want (USDC): ", USDC);
        console.log("Morpho:      ", MORPHO_USDC_VAULT);
    }
}
```

### 2.3 Deploy Commands

```bash
# Deploy to World Chain Sepolia (testnet)
forge script script/Deploy.s.sol:DeployHarvest \
  --rpc-url https://worldchain-sepolia.g.alchemy.com/v2/$ALCHEMY_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $WORLDSCAN_API_KEY \
  --chain-id 4801 \
  -vvvv

# Deploy to World Chain Mainnet
forge script script/Deploy.s.sol:DeployHarvest \
  --rpc-url https://worldchain-mainnet.g.alchemy.com/v2/$ALCHEMY_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $WORLDSCAN_API_KEY \
  --chain-id 480 \
  -vvvv
```

### 2.4 Verification on WorldScan

```bash
# If automatic verification fails, verify manually:
forge verify-contract \
  --chain-id 480 \
  --constructor-args $(cast abi-encode "constructor()") \
  --etherscan-api-key $WORLDSCAN_API_KEY \
  --watch \
  $VAULT_IMPL_ADDRESS \
  src/vaults/HarvestVaultV7.sol:HarvestVaultV7

# Verify proxy implementation:
forge verify-contract \
  --chain-id 480 \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" $VAULT_IMPL_ADDRESS $INIT_DATA) \
  --etherscan-api-key $WORLDSCAN_API_KEY \
  --watch \
  $VAULT_PROXY_ADDRESS \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
```

### 2.5 Constructor / Initializer Parameters Reference

| Contract | Parameter | Value |
|---|---|---|
| HarvestVaultV7 | `want` | `0x79A02482A880bCE3B13e09Da970dC34db4CD24d1` (USDC) |
| HarvestVaultV7 | `name` | `"Harvest USDC"` |
| HarvestVaultV7 | `symbol` | `"harvestUSDC"` |
| HarvestVaultV7 | `approvalDelay` | `0` (no timelock for hackathon) |
| StrategyMorpho | `vault` | Vault proxy address (from step 2) |
| StrategyMorpho | `want` | `0x79A02482A880bCE3B13e09Da970dC34db4CD24d1` (USDC) |
| StrategyMorpho | `morphoVault` | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` (Re7 USDC) |
| StrategyMorpho | `swapRouter` | `0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6` (Uniswap V3 Router) |
| StrategyMorpho | `feeRecipient` | Deployer wallet or protocol treasury |
| StrategyMorpho | `strategist` | Deployer wallet |
| StrategyMorpho | `rewardTokens` | `[0x2cFc85d8E48F8EAB294be644d9E25C3030863003]` (WLD) |
| StrategyMorpho | `swapPaths` | WLD->WETH->USDC packed path (see Section 1.7) |

---

## 3. MINIKIT INTEGRATION

### 3.1 Deposit Flow: approve USDC + deposit into vault

Two transactions sent atomically via MiniKit.sendTransaction:
1. Approve vault to spend user's USDC
2. Deposit USDC into vault, minting harvestUSDC shares

```typescript
// src/lib/vault-actions.ts
import { encodeFunctionData, parseUnits } from "viem";
import { ERC20_ABI, HARVEST_VAULT_ABI } from "./constants";

export function buildDepositPayload(
  vaultAddress: `0x${string}`,
  usdcAddress: `0x${string}`,
  amount: string, // human-readable, e.g. "100.50"
  userAddress: `0x${string}`
): { chainId: number; transactions: { to: `0x${string}`; data: `0x${string}` }[] } {
  const amountWei = parseUnits(amount, 6); // USDC has 6 decimals

  // Transaction 1: Approve vault to spend USDC
  const approveData = encodeFunctionData({
    abi: ERC20_ABI,
    functionName: "approve",
    args: [vaultAddress, amountWei],
  });

  // Transaction 2: Deposit USDC into vault
  // Uses ERC4626 deposit(uint256 assets, address receiver)
  const depositData = encodeFunctionData({
    abi: HARVEST_VAULT_ABI,
    functionName: "deposit",
    args: [amountWei, userAddress],
  });

  return {
    chainId: 480,
    transactions: [
      { to: usdcAddress, data: approveData },
      { to: vaultAddress, data: depositData },
    ],
  };
}
```

**Terminal-based deposit flow -- the `deposit` command handler calls MiniKit.sendTransaction:**

The entire app is a single terminal UI. Users type commands (or tap shortcut buttons) and see output lines. Each command handler returns `TerminalLine[]` that get appended to the scrollback.

```typescript
// src/lib/commands/deposit.ts
import { MiniKit } from "@worldcoin/minikit-js";
import { buildDepositPayload } from "@/lib/vault-actions";
import { VAULT_ADDRESS, USDC_ADDRESS } from "@/lib/constants";
import { waitForTransaction } from "@/lib/poll-tx";
import type { TerminalLine } from "@/components/Terminal";

/**
 * Usage: deposit <amount> <token>
 * Example: deposit 50 usdc
 *
 * The terminal renders each line as it is yielded:
 *   > deposit 50 usdc
 *   Preparing deposit into Re7 USDC vault...
 *   Approve USDC ✓
 *   Confirm in World App? [waiting...]
 *   ✓ Deposited. tx: 0x7f3a...
 */
export async function handleDeposit(
  amount: string,
  token: string,
  wallet: string,
  pushLine: (line: TerminalLine) => void
): Promise<void> {
  if (!MiniKit.isInstalled()) {
    pushLine({ type: "error", content: "MiniKit not installed. Open in World App." });
    return;
  }

  if (!amount || isNaN(Number(amount)) || Number(amount) <= 0) {
    pushLine({ type: "error", content: "Usage: deposit <amount> <token>  (e.g. deposit 50 usdc)" });
    return;
  }

  pushLine({ type: "system", content: `Preparing deposit into Re7 USDC vault...` });

  try {
    const payload = buildDepositPayload(
      VAULT_ADDRESS,
      USDC_ADDRESS,
      amount,
      wallet as `0x${string}`
    );

    pushLine({ type: "output", content: "Approve USDC ✓" });
    pushLine({ type: "system", content: "Confirm in World App? [waiting...]" });

    // This is the exact MiniKit call
    const result = await MiniKit.sendTransaction({
      chainId: 480,
      transactions: payload.transactions,
    });

    if (result.executedWith === "fallback") {
      throw new Error("Transaction fell back to external wallet");
    }

    pushLine({ type: "system", content: "Transaction submitted. Polling for confirmation..." });

    const { transactionHash } = await waitForTransaction(result.data.userOpHash);

    pushLine({
      type: "success",
      content: `✓ Deposited ${amount} USDC. tx: ${transactionHash.slice(0, 10)}...`,
      timestamp: new Date().toISOString(),
    });

    // Record in database
    await fetch("/api/deposit/confirm", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        tx_hash: transactionHash,
        vault_address: VAULT_ADDRESS,
        amount,
        user_op_hash: result.data.userOpHash,
      }),
    });
  } catch (err: any) {
    pushLine({ type: "error", content: `Deposit failed: ${err.message}` });
  }
}
```

### 3.2 Withdraw Flow: redeem shares -> receive USDC

```typescript
// src/lib/vault-actions.ts (continued)

export function buildWithdrawPayload(
  vaultAddress: `0x${string}`,
  shares: bigint, // user's share amount in wei
  userAddress: `0x${string}`
): { chainId: number; transactions: { to: `0x${string}`; data: `0x${string}` }[] } {
  // ERC4626 redeem(uint256 shares, address receiver, address owner)
  const redeemData = encodeFunctionData({
    abi: HARVEST_VAULT_ABI,
    functionName: "redeem",
    args: [shares, userAddress, userAddress],
  });

  return {
    chainId: 480,
    transactions: [
      { to: vaultAddress, data: redeemData },
    ],
  };
}

// For "withdraw exact USDC amount" instead of "redeem all shares":
export function buildWithdrawExactPayload(
  vaultAddress: `0x${string}`,
  usdcAmount: string, // human-readable
  userAddress: `0x${string}`
): { chainId: number; transactions: { to: `0x${string}`; data: `0x${string}` }[] } {
  const amountWei = parseUnits(usdcAmount, 6);

  // ERC4626 withdraw(uint256 assets, address receiver, address owner)
  const withdrawData = encodeFunctionData({
    abi: HARVEST_VAULT_ABI,
    functionName: "withdraw",
    args: [amountWei, userAddress, userAddress],
  });

  return {
    chainId: 480,
    transactions: [
      { to: vaultAddress, data: withdrawData },
    ],
  };
}
```

**Terminal-based withdraw flow -- the `withdraw` command handler:**

```typescript
// src/lib/commands/withdraw.ts
import { MiniKit } from "@worldcoin/minikit-js";
import { buildWithdrawPayload, buildWithdrawExactPayload } from "@/lib/vault-actions";
import { VAULT_ADDRESS } from "@/lib/constants";
import { waitForTransaction } from "@/lib/poll-tx";
import type { TerminalLine } from "@/components/Terminal";

/**
 * Usage: withdraw <amount> usdc   -- withdraw exact USDC
 *        withdraw all              -- redeem all shares
 *
 * Terminal output:
 *   > withdraw 50 usdc
 *   Preparing withdrawal from Harvest USDC vault...
 *   Confirm in World App? [waiting...]
 *   ✓ Withdrawn 50.00 USDC. tx: 0xab12...
 */
export async function handleWithdraw(
  args: string[],
  wallet: string,
  userShares: bigint,
  pushLine: (line: TerminalLine) => void
): Promise<void> {
  if (!MiniKit.isInstalled()) {
    pushLine({ type: "error", content: "MiniKit not installed. Open in World App." });
    return;
  }

  pushLine({ type: "system", content: "Preparing withdrawal from Harvest USDC vault..." });

  try {
    let payload;
    let description: string;

    if (args[0] === "all") {
      payload = buildWithdrawPayload(VAULT_ADDRESS, userShares, wallet as `0x${string}`);
      description = "all shares";
    } else {
      const amount = args[0];
      if (!amount || isNaN(Number(amount))) {
        pushLine({ type: "error", content: "Usage: withdraw <amount> usdc  OR  withdraw all" });
        return;
      }
      payload = buildWithdrawExactPayload(VAULT_ADDRESS, amount, wallet as `0x${string}`);
      description = `${amount} USDC`;
    }

    pushLine({ type: "system", content: "Confirm in World App? [waiting...]" });

    const result = await MiniKit.sendTransaction({
      chainId: 480,
      transactions: payload.transactions,
    });

    if (result.executedWith === "fallback") throw new Error("Fallback");

    pushLine({ type: "system", content: "Transaction submitted. Polling for confirmation..." });

    const { transactionHash } = await waitForTransaction(result.data.userOpHash);

    pushLine({
      type: "success",
      content: `✓ Withdrawn ${description}. tx: ${transactionHash.slice(0, 10)}...`,
      timestamp: new Date().toISOString(),
    });

    await fetch("/api/withdraw/confirm", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        tx_hash: transactionHash,
        vault_address: VAULT_ADDRESS,
        shares: userShares.toString(),
        user_op_hash: result.data.userOpHash,
      }),
    });
  } catch (err: any) {
    pushLine({ type: "error", content: `Withdraw failed: ${err.message}` });
  }
}
```

### 3.3 Wallet Auth + World ID Verification

```typescript
// src/lib/auth.ts
import { MiniKit } from "@worldcoin/minikit-js";

export async function authenticateWithWorldId(): Promise<{
  address: string;
  nullifierHash: string;
}> {
  if (!MiniKit.isInstalled()) throw new Error("Open in World App");

  // Step 1: Get nonce
  const { nonce } = await fetch("/api/auth/nonce").then((r) => r.json());

  // Step 2: World ID verify (proves human)
  const verifyResult = await MiniKit.commandsAsync.verify({
    action: "harvest-v2-auth",
    verification_level: "orb",
  });

  if (verifyResult.finalPayload.status === "error") {
    throw new Error("World ID verification failed");
  }

  const { merkle_root, nullifier_hash, proof } = verifyResult.finalPayload;

  // Step 3: Verify on backend
  const verifyRes = await fetch("/api/auth/verify-worldid", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ merkle_root, nullifier_hash, proof }),
  });

  if (!verifyRes.ok) throw new Error("Backend verification failed");

  // Step 4: SIWE wallet auth (gets wallet address)
  const walletResult = await MiniKit.commandsAsync.walletAuth({
    nonce,
    statement: "Sign in to Harvest v2 to manage your yield vaults",
    expirationTime: new Date(Date.now() + 15 * 60 * 1000),
  });

  if (walletResult.finalPayload.status === "error") {
    throw new Error("Wallet auth failed");
  }

  // Step 5: Create session
  const session = await fetch("/api/auth/verify-siwe", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      payload: walletResult.finalPayload,
      nullifier_hash,
    }),
  }).then((r) => r.json());

  return {
    address: session.wallet_address,
    nullifierHash: nullifier_hash,
  };
}
```

### 3.4 Transaction Confirmation Polling

```typescript
// src/lib/poll-tx.ts
export async function waitForTransaction(
  userOpHash: string,
  options?: { timeoutMs?: number; intervalMs?: number }
): Promise<{ transactionHash: string; status: "confirmed" }> {
  const timeout = options?.timeoutMs ?? 30000;
  const interval = options?.intervalMs ?? 2000;
  const deadline = Date.now() + timeout;

  while (Date.now() < deadline) {
    try {
      const res = await fetch(
        `https://developer.world.org/api/v2/minikit/userop/${userOpHash}`
      );

      if (res.ok) {
        const data = await res.json();
        if (data.transaction_hash) {
          return {
            transactionHash: data.transaction_hash,
            status: "confirmed",
          };
        }
      }
    } catch {
      // Network error, retry
    }

    await new Promise((r) => setTimeout(r, interval));
  }

  throw new Error(`Transaction not confirmed after ${timeout}ms`);
}
```

---

## 4. AGENT / HARVESTER

### 4.1 TypeScript Harvest Loop

The harvester is a standalone process that periodically calls `harvest()` on each strategy. It earns 1% of each harvest as an incentive fee.

```typescript
// agent/harvester.ts
import { createWalletClient, createPublicClient, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { worldchain } from "./chain";

const STRATEGY_ABI = parseAbi([
  "function harvest(address[] calldata, address[] calldata, uint256[] calldata, bytes32[][] calldata) external",
  "function balanceOf() external view returns (uint256)",
  "function balanceOfWant() external view returns (uint256)",
  "function balanceOfPool() external view returns (uint256)",
  "function want() external view returns (address)",
]);

const MERKL_API = "https://api.merkl.xyz/v4";

interface VaultConfig {
  name: string;
  vaultAddress: `0x${string}`;
  strategyAddress: `0x${string}`;
  wantToken: `0x${string}`;
}

const VAULTS: VaultConfig[] = [
  {
    name: "Harvest USDC",
    vaultAddress: "0x__VAULT_ADDRESS__" as `0x${string}`,
    strategyAddress: "0x__STRATEGY_ADDRESS__" as `0x${string}`,
    wantToken: "0x79A02482A880bCE3B13e09Da970dC34db4CD24d1",
  },
];

const account = privateKeyToAccount(process.env.HARVESTER_PRIVATE_KEY as `0x${string}`);

const publicClient = createPublicClient({
  chain: worldchain,
  transport: http(process.env.WORLD_CHAIN_RPC_URL),
});

const walletClient = createWalletClient({
  account,
  chain: worldchain,
  transport: http(process.env.WORLD_CHAIN_RPC_URL),
});

// ============================================================
// Fetch Merkl proofs for a strategy address
// <!-- Merged from claimall-spec.md: detailed API response handling -->
//
// Merkl API: GET https://api.merkl.xyz/v4/users/{address}/rewards?chainId=480
// - Public API, no auth required
// - `amount` is CUMULATIVE total ever earned (pass this to contract, not unclaimed)
// - `claimed` is what has already been claimed on-chain
// - `unclaimed` = amount - claimed
// - `proofs` is the merkle proof array, ready to pass to contract
// - Each proof element must be a bytes32 (66-char hex string: 0x + 64 hex chars)
//
// Error handling:
// - Timeout (5s): skip harvest, retry next cycle
// - API down: skip harvest, retry next cycle
// - Empty response: return empty arrays (no rewards to claim)
// ============================================================

interface MerklRewardData {
  users: `0x${string}`[];
  tokens: `0x${string}`[];
  amounts: bigint[];
  proofs: `0x${string}`[][];
}

async function fetchMerklProofs(strategyAddress: string): Promise<MerklRewardData> {
  const res = await fetch(
    `${MERKL_API}/users/${strategyAddress}/rewards?chainId=480`
  );

  if (!res.ok) {
    console.error(`Merkl API error: ${res.status}`);
    return { users: [], tokens: [], amounts: [], proofs: [] };
  }

  const data = await res.json();

  const users: `0x${string}`[] = [];
  const tokens: `0x${string}`[] = [];
  const amounts: bigint[] = [];
  const proofs: `0x${string}`[][] = [];

  // Parse Merkl v4 response
  // Structure: array of reward objects with token info and proofs
  if (Array.isArray(data)) {
    for (const entry of data) {
      if (!entry.token?.address || !entry.amount) continue;
      const unclaimed = BigInt(entry.amount) - BigInt(entry.claimed || "0");
      if (unclaimed <= 0n) continue;

      users.push(strategyAddress as `0x${string}`);
      tokens.push(entry.token.address as `0x${string}`);
      amounts.push(BigInt(entry.amount)); // cumulative, NOT unclaimed
      proofs.push((entry.proofs || []) as `0x${string}`[]);
    }
  }

  return { users, tokens, amounts, proofs };
}

// ============================================================
// Execute harvest on a single vault
// ============================================================

async function harvestVault(config: VaultConfig): Promise<{
  success: boolean;
  txHash?: string;
  wantEarned?: string;
  error?: string;
}> {
  try {
    // 1. Check if there are rewards to harvest
    const merklData = await fetchMerklProofs(config.strategyAddress);

    // 2. Check strategy balance to estimate if harvest is worthwhile
    const poolBalance = await publicClient.readContract({
      address: config.strategyAddress,
      abi: STRATEGY_ABI,
      functionName: "balanceOfPool",
    });

    console.log(`[${config.name}] Pool balance: ${poolBalance}`);
    console.log(`[${config.name}] Merkl rewards: ${merklData.tokens.length} tokens`);

    // 3. Execute harvest
    const txHash = await walletClient.writeContract({
      address: config.strategyAddress,
      abi: STRATEGY_ABI,
      functionName: "harvest",
      args: [merklData.users, merklData.tokens, merklData.amounts, merklData.proofs],
    });

    console.log(`[${config.name}] Harvest tx: ${txHash}`);

    // 4. Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

    return {
      success: receipt.status === "success",
      txHash,
    };
  } catch (err: any) {
    return {
      success: false,
      error: err.message || "Unknown error",
    };
  }
}

// ============================================================
// Main harvest loop
// ============================================================

async function runHarvestLoop() {
  console.log("=== Harvest Agent Started ===");
  console.log(`Agent address: ${account.address}`);
  console.log(`Vaults: ${VAULTS.length}`);

  for (const vault of VAULTS) {
    console.log(`\nHarvesting ${vault.name}...`);
    const result = await harvestVault(vault);

    if (result.success) {
      console.log(`  SUCCESS: ${result.txHash}`);

      // Record harvest in database
      await fetch(`${process.env.APP_URL}/api/harvests`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.CRON_SECRET}`,
        },
        body: JSON.stringify({
          vault_address: vault.vaultAddress,
          strategy_address: vault.strategyAddress,
          tx_hash: result.txHash,
          harvester: account.address,
        }),
      });
    } else {
      console.log(`  FAILED: ${result.error}`);
    }
  }
}

// Execute
runHarvestLoop().catch(console.error);
```

### 4.2 Chain Definition for Viem

```typescript
// agent/chain.ts
import { defineChain } from "viem";

export const worldchain = defineChain({
  id: 480,
  name: "World Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: {
      http: [process.env.WORLD_CHAIN_RPC_URL || "https://worldchain-mainnet.gateway.tenderly.co"],
    },
  },
  blockExplorers: {
    default: { name: "Worldscan", url: "https://worldscan.org" },
  },
});
```

### 4.3 Rebalance Detection

Compare APYs across vaults. If a new Morpho vault offers significantly higher yield, flag it for manual strategy migration.

```typescript
// agent/rebalance-check.ts

interface VaultAPY {
  name: string;
  address: string;
  currentApy: number;
}

async function checkRebalanceOpportunity(): Promise<{
  shouldRebalance: boolean;
  suggestion?: string;
}> {
  // Fetch current vault APYs from DeFi Llama
  const res = await fetch("https://yields.llama.fi/pools");
  const { data: pools } = await res.json();

  // Filter to World Chain Morpho vaults
  const worldChainMorpho = pools.filter(
    (p: any) => p.chain === "World" && p.project === "morpho-blue"
  );

  // Find our current vault's APY
  const ourVault = worldChainMorpho.find(
    (p: any) => p.pool.toLowerCase().includes("usdc")
  );

  // Find the best alternative
  const bestAlternative = worldChainMorpho
    .filter((p: any) => p.pool !== ourVault?.pool)
    .sort((a: any, b: any) => b.apy - a.apy)[0];

  if (ourVault && bestAlternative && bestAlternative.apy > ourVault.apy * 1.5) {
    return {
      shouldRebalance: true,
      suggestion: `Current vault APY: ${ourVault.apy.toFixed(2)}%. ` +
        `${bestAlternative.pool} offers ${bestAlternative.apy.toFixed(2)}%. ` +
        `Consider migrating strategy.`,
    };
  }

  return { shouldRebalance: false };
}
```

### 4.4 AgentKit Integration

Register the harvester agent wallet, proving it is human-backed:

```typescript
// agent/register-agent.ts
import { AgentKit } from "@worldcoin/agentkit";

async function registerHarvesterAgent() {
  const agent = new AgentKit({
    walletAddress: process.env.AGENT_WALLET_ADDRESS!,
    privateKey: process.env.AGENT_PRIVATE_KEY!,
  });

  // Register on AgentBook (triggers World App verification)
  const registration = await agent.register({
    name: "Harvest v2 Autocompounder",
    description: "Autocompounds Morpho vault yields on World Chain",
    capabilities: ["harvest", "yield-data"],
  });

  console.log("Agent registered:", registration.agentId);
  return registration;
}
```

### 4.5 x402 Integration: Paying for Yield Data

```typescript
// agent/x402-client.ts
import { privateKeyToAccount } from "viem/accounts";

const account = privateKeyToAccount(process.env.AGENT_PRIVATE_KEY as `0x${string}`);

export async function fetchYieldDataWithX402(): Promise<any> {
  const url = `${process.env.APP_URL}/api/x402/yield-data`;

  // First request -- expect 402
  const initial = await fetch(url);

  if (initial.status === 402) {
    // Build payment header
    const timestamp = Date.now();
    const message = `x402:${url}:${timestamp}`;
    const signature = await account.signMessage({ message });

    const paymentHeader = JSON.stringify({
      agentAddress: account.address,
      signature,
      timestamp,
    });

    // Retry with payment
    const paid = await fetch(url, {
      headers: { "X-PAYMENT": paymentHeader },
    });

    if (!paid.ok) throw new Error(`x402 failed: ${paid.status}`);
    return paid.json();
  }

  if (initial.ok) return initial.json();
  throw new Error(`Unexpected: ${initial.status}`);
}
```

### 4.6 Cron Scheduling

**Option A: Vercel Cron (if hosted on Vercel)**

```json
// vercel.json
{
  "crons": [
    {
      "path": "/api/cron/harvest",
      "schedule": "0 */6 * * *"
    },
    {
      "path": "/api/cron/snapshot",
      "schedule": "0 * * * *"
    }
  ]
}
```

**Option B: Standalone cron (pm2 or systemd)**

```bash
# package.json script
"scripts": {
  "harvest": "tsx agent/harvester.ts",
  "harvest:cron": "node -e \"setInterval(() => require('child_process').execSync('tsx agent/harvester.ts', {stdio: 'inherit'}), 6 * 60 * 60 * 1000)\""
}

# Or with crontab
# Every 6 hours
0 */6 * * * cd /app && npx tsx agent/harvester.ts >> /var/log/harvest.log 2>&1
```

---

## 5. TERMINAL UI + DASHBOARD DATA

The entire frontend is a single-page terminal interface. No multi-page routing, no card components. Users interact through typed commands and tappable shortcut buttons. All data display happens as formatted terminal output lines.

### 5.0 Terminal Components

```typescript
// src/components/Terminal.tsx — the entire app UI
"use client";

import { useState, useRef, useEffect } from "react";
import { CommandInput } from "./CommandInput";
import { TerminalOutput } from "./TerminalOutput";
import { routeCommand } from "@/lib/commands";

export interface TerminalLine {
  type: "input" | "output" | "system" | "error" | "success";
  content: string;
  timestamp?: string;
}

export function Terminal({ wallet }: { wallet: string }) {
  const [lines, setLines] = useState<TerminalLine[]>([
    { type: "system", content: "harvest v2 — yield aggregator on world chain" },
    { type: "system", content: 'Type "help" for available commands.' },
  ]);
  const scrollRef = useRef<HTMLDivElement>(null);

  function pushLine(line: TerminalLine) {
    setLines((prev) => [...prev, line]);
  }

  async function handleCommand(raw: string) {
    const trimmed = raw.trim();
    if (!trimmed) return;

    pushLine({ type: "input", content: `> ${trimmed}` });
    await routeCommand(trimmed, wallet, pushLine);
  }

  // Auto-scroll to bottom on new output
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [lines]);

  return (
    <div className="terminal-container flex flex-col h-screen bg-[#0a0a0a] text-[#00ff00] font-mono">
      <TerminalOutput lines={lines} scrollRef={scrollRef} />
      <CommandInput onSubmit={handleCommand} />
    </div>
  );
}
```

```typescript
// src/components/CommandInput.tsx — input bar + tappable shortcuts
"use client";

import { useState } from "react";

const QUICK_COMMANDS = ["portfolio", "vaults", "deposit", "withdraw", "agent status"] as const;

export function CommandInput({ onSubmit }: { onSubmit: (cmd: string) => void }) {
  const [input, setInput] = useState("");

  function submit() {
    if (!input.trim()) return;
    onSubmit(input);
    setInput("");
  }

  return (
    <div className="flex-shrink-0 border-t border-[#00ff00]/20 p-3 space-y-2">
      {/* Shortcut buttons */}
      <div className="flex gap-2 overflow-x-auto pb-1">
        {QUICK_COMMANDS.map((cmd) => (
          <button
            key={cmd}
            onClick={() => onSubmit(cmd)}
            className="px-3 py-1 text-xs border border-[#00ff00]/40 rounded
                       text-[#00ff00] bg-[#0a0a0a] hover:bg-[#00ff00]/10
                       whitespace-nowrap flex-shrink-0"
          >
            {cmd}
          </button>
        ))}
      </div>
      {/* Input bar */}
      <div className="flex items-center gap-2">
        <span className="text-[#00ff00]/60">$</span>
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
          placeholder="type a command..."
          className="flex-1 bg-transparent outline-none text-[#00ff00]
                     placeholder:text-[#00ff00]/30 caret-[#00ff00]"
          autoFocus
        />
      </div>
    </div>
  );
}
```

```typescript
// src/components/TerminalOutput.tsx — scrollable output area
"use client";

import { RefObject } from "react";
import { TerminalLineComponent } from "./TerminalLine";
import type { TerminalLine } from "./Terminal";

export function TerminalOutput({
  lines,
  scrollRef,
}: {
  lines: TerminalLine[];
  scrollRef: RefObject<HTMLDivElement>;
}) {
  return (
    <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-1">
      {lines.map((line, i) => (
        <TerminalLineComponent key={i} line={line} />
      ))}
    </div>
  );
}
```

```typescript
// src/components/TerminalLine.tsx — single line renderer
"use client";

import type { TerminalLine } from "./Terminal";

const LINE_STYLES: Record<TerminalLine["type"], string> = {
  input: "text-white font-bold",
  output: "text-[#00ff00]",
  system: "text-[#00ff00]/60 italic",
  error: "text-red-400",
  success: "text-[#00ff00] font-bold",
};

export function TerminalLineComponent({ line }: { line: TerminalLine }) {
  return (
    <div className={`whitespace-pre-wrap break-all text-sm ${LINE_STYLES[line.type]}`}>
      {line.timestamp && (
        <span className="text-[#00ff00]/30 mr-2 text-xs">
          [{new Date(line.timestamp).toLocaleTimeString()}]
        </span>
      )}
      {line.content}
    </div>
  );
}
```

### 5.0.1 Command Router

```typescript
// src/lib/commands/index.ts — command router/parser
import type { TerminalLine } from "@/components/Terminal";
import { handlePortfolio } from "./portfolio";
import { handleVaults } from "./vaults";
import { handleDeposit } from "./deposit";
import { handleWithdraw } from "./withdraw";
import { handleAgent } from "./agent";
import { handleHelp } from "./help";

export async function routeCommand(
  raw: string,
  wallet: string,
  pushLine: (line: TerminalLine) => void
): Promise<void> {
  const parts = raw.trim().toLowerCase().split(/\s+/);
  const cmd = parts[0];
  const args = parts.slice(1);

  switch (cmd) {
    case "portfolio":
      return handlePortfolio(wallet, pushLine);
    case "vaults":
      return handleVaults(pushLine);
    case "deposit":
      return handleDeposit(args[0], args[1] || "usdc", wallet, pushLine);
    case "withdraw":
      return handleWithdraw(args, wallet, 0n /* fetched inside handler */, pushLine);
    case "agent":
      return handleAgent(args, pushLine);
    case "help":
      return handleHelp(pushLine);
    default:
      pushLine({ type: "error", content: `Unknown command: ${cmd}. Type "help" for available commands.` });
  }
}
```

### 5.0.2 Portfolio Command

```typescript
// src/lib/commands/portfolio.ts
import type { TerminalLine } from "@/components/Terminal";
import { getVaultData } from "@/lib/vault-reads";
import { VAULT_ADDRESS } from "@/lib/constants";

/**
 * Usage: portfolio
 *
 * Terminal output:
 *   > portfolio
 *   ┌─────────────────────────────────────┐
 *   │ PORTFOLIO                           │
 *   ├──────────────┬──────────┬───────────┤
 *   │ Vault        │ Deposited│ Value     │
 *   ├──────────────┼──────────┼───────────┤
 *   │ Harvest USDC │ 1,000.00 │ $1,020.00 │
 *   └──────────────┴──────────┴───────────┘
 *   Total value: $1,020.00
 */
export async function handlePortfolio(
  wallet: string,
  pushLine: (line: TerminalLine) => void
): Promise<void> {
  pushLine({ type: "system", content: "Fetching positions..." });

  try {
    const data = await getVaultData(VAULT_ADDRESS, wallet as `0x${string}`);

    pushLine({ type: "output", content: "" });
    pushLine({ type: "output", content: "  PORTFOLIO" });
    pushLine({ type: "output", content: "  ─────────────────────────────────" });
    pushLine({ type: "output", content: `  Vault          Harvest USDC` });
    pushLine({ type: "output", content: `  Shares         ${data.userShares}` });
    pushLine({ type: "output", content: `  Value          $${data.userAssetsUsdc.toFixed(2)}` });
    pushLine({ type: "output", content: `  Share price    ${(Number(data.pricePerShare) / 1e18).toFixed(6)}` });
    pushLine({ type: "output", content: "  ─────────────────────────────────" });
    pushLine({ type: "success", content: `  Total: $${data.userAssetsUsdc.toFixed(2)}` });
  } catch (err: any) {
    pushLine({ type: "error", content: `Failed to fetch portfolio: ${err.message}` });
  }
}
```

### 5.0.3 Vaults Command

```typescript
// src/lib/commands/vaults.ts
import type { TerminalLine } from "@/components/Terminal";

/**
 * Usage: vaults
 *
 * Terminal output:
 *   > vaults
 *   AVAILABLE VAULTS
 *   ─────────────────────────────────
 *   [1] Harvest USDC
 *       APY (7d): 8.2%  |  TVL: $125,000
 *       Strategy: Morpho Re7 USDC
 */
export async function handleVaults(
  pushLine: (line: TerminalLine) => void
): Promise<void> {
  pushLine({ type: "system", content: "Fetching vaults..." });

  try {
    const res = await fetch("/api/vaults");
    const { vaults } = await res.json();

    pushLine({ type: "output", content: "" });
    pushLine({ type: "output", content: "  AVAILABLE VAULTS" });
    pushLine({ type: "output", content: "  ─────────────────────────────────" });

    for (const [i, vault] of vaults.entries()) {
      pushLine({ type: "output", content: `  [${i + 1}] ${vault.name}` });
      pushLine({
        type: "output",
        content: `      APY (7d): ${vault.apy.apy7d.toFixed(1)}%  |  TVL: $${vault.tvlUsdc.toLocaleString()}`,
      });
      pushLine({ type: "output", content: `      Token: ${vault.wantSymbol}` });
      pushLine({ type: "output", content: "" });
    }
  } catch (err: any) {
    pushLine({ type: "error", content: `Failed to fetch vaults: ${err.message}` });
  }
}
```

### 5.0.4 Agent Command

```typescript
// src/lib/commands/agent.ts
import type { TerminalLine } from "@/components/Terminal";

/**
 * Usage: agent status     -- show agent info + recent harvests
 *        agent harvest    -- show last harvest details
 */
export async function handleAgent(
  args: string[],
  pushLine: (line: TerminalLine) => void
): Promise<void> {
  const sub = args[0] || "status";

  if (sub === "status" || sub === "harvest") {
    pushLine({ type: "system", content: "Fetching agent activity..." });

    try {
      const res = await fetch("/api/harvests?limit=5");
      const { harvests } = await res.json();

      pushLine({ type: "output", content: "" });
      pushLine({ type: "output", content: "  AGENT STATUS" });
      pushLine({ type: "output", content: "  ─────────────────────────────────" });
      pushLine({ type: "output", content: `  Recent harvests: ${harvests.length}` });

      for (const h of harvests) {
        const earned = h.want_earned ? `+$${Number(h.want_earned).toFixed(2)}` : "pending";
        const time = new Date(h.created_at).toLocaleString();
        pushLine({
          type: "output",
          content: `  ${time}  ${earned}  tx:${h.tx_hash.slice(0, 10)}...`,
        });
      }

      pushLine({ type: "output", content: "  ─────────────────────────────────" });
    } catch (err: any) {
      pushLine({ type: "error", content: `Failed to fetch agent data: ${err.message}` });
    }
  } else {
    pushLine({ type: "error", content: `Unknown subcommand: agent ${sub}. Try: agent status, agent harvest` });
  }
}
```

### 5.0.5 Help Command

```typescript
// src/lib/commands/help.ts
import type { TerminalLine } from "@/components/Terminal";

export async function handleHelp(
  pushLine: (line: TerminalLine) => void
): Promise<void> {
  const lines = [
    "",
    "  HARVEST v2 — COMMANDS",
    "  ─────────────────────────────────",
    "  portfolio          Show your vault positions and value",
    "  vaults             List available vaults with APY and TVL",
    "  deposit <amt> usdc Deposit USDC into the vault",
    "  withdraw <amt> usdc Withdraw USDC from the vault",
    "  withdraw all       Redeem all shares",
    "  agent status       Show harvester agent activity",
    "  agent harvest      Show last harvest details",
    "  help               Show this message",
    "  ─────────────────────────────────",
    "",
  ];

  for (const content of lines) {
    pushLine({ type: "output", content });
  }
}
```

### 5.0.6 Terminal Formatting Helpers

```typescript
// src/lib/terminal-format.ts — formatting helpers for terminal output

/** Pad/align a label:value pair for terminal display */
export function formatRow(label: string, value: string, labelWidth = 16): string {
  return `  ${label.padEnd(labelWidth)} ${value}`;
}

/** Format a USD amount with commas and 2 decimal places */
export function formatUsd(n: number): string {
  return `$${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** Format a bigint token amount given decimals */
export function formatTokenAmount(wei: bigint, decimals: number, symbol: string): string {
  const value = Number(wei) / 10 ** decimals;
  return `${value.toLocaleString(undefined, { maximumFractionDigits: decimals })} ${symbol}`;
}

/** Horizontal rule for terminal sections */
export const HR = "  ─────────────────────────────────";
```

### 5.0.7 Layout and Styling

```typescript
// src/app/layout.tsx — dark theme, monospace font
import type { Metadata } from "next";
import { MiniKit } from "@worldcoin/minikit-js";
import "./globals.css";

export const metadata: Metadata = {
  title: "harvest v2",
  description: "Yield aggregator on World Chain",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <head>
        <link
          href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="bg-[#0a0a0a] text-[#00ff00] font-mono antialiased">
        {children}
      </body>
    </html>
  );
}
```

```css
/* src/app/globals.css — terminal aesthetic */

@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --terminal-bg: #0a0a0a;
  --terminal-green: #00ff00;
  --terminal-dim: rgba(0, 255, 0, 0.4);
  --terminal-error: #ff4444;
}

body {
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
  background: var(--terminal-bg);
  color: var(--terminal-green);
}

/* Scrollbar styling */
.terminal-container ::-webkit-scrollbar {
  width: 6px;
}
.terminal-container ::-webkit-scrollbar-track {
  background: var(--terminal-bg);
}
.terminal-container ::-webkit-scrollbar-thumb {
  background: var(--terminal-dim);
  border-radius: 3px;
}

/* Shortcut buttons: dark bg, green border, green text */
button {
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
}

/* Blinking caret effect */
input:focus {
  caret-color: var(--terminal-green);
}
```

```typescript
// src/app/page.tsx — Terminal (only page)
"use client";

import { useState, useEffect } from "react";
import { Terminal } from "@/components/Terminal";
import { authenticateWithWorldId } from "@/lib/auth";

export default function Home() {
  const [wallet, setWallet] = useState<string | null>(null);

  useEffect(() => {
    authenticateWithWorldId()
      .then(({ address }) => setWallet(address))
      .catch(() => {
        // Auth will be retried on user action
      });
  }, []);

  if (!wallet) {
    return (
      <div className="h-screen flex items-center justify-center bg-[#0a0a0a] text-[#00ff00] font-mono">
        <div className="text-center space-y-4">
          <pre className="text-xs">
{`
  _  _   _   _____   _____ ___ _____
 | || | /_\\ | _ \\ \\ / / __/ __|_   _|
 | __ |/ _ \\|   /\\ V /| _|\\__ \\ | |
 |_||_/_/ \\_\\_|_\\ \\_/ |___|___/ |_|
`}
          </pre>
          <p className="text-[#00ff00]/60">Connecting to World App...</p>
        </div>
      </div>
    );
  }

  return <Terminal wallet={wallet} />;
}
```

### 5.1 Reading Vault State

```typescript
// src/lib/vault-reads.ts
import { publicClient } from "./viem-client";
import { HARVEST_VAULT_ABI } from "./constants";
import { formatUnits } from "viem";

export async function getVaultData(
  vaultAddress: `0x${string}`,
  userAddress?: `0x${string}`
) {
  // Batch read all vault state in one multicall
  const results = await publicClient.multicall({
    contracts: [
      {
        address: vaultAddress,
        abi: HARVEST_VAULT_ABI,
        functionName: "getPricePerFullShare",
      },
      {
        address: vaultAddress,
        abi: HARVEST_VAULT_ABI,
        functionName: "totalSupply",
      },
      {
        address: vaultAddress,
        abi: HARVEST_VAULT_ABI,
        functionName: "balance", // total assets (vault + strategy)
      },
      // User-specific reads (only if userAddress provided)
      ...(userAddress
        ? [
            {
              address: vaultAddress,
              abi: HARVEST_VAULT_ABI,
              functionName: "balanceOf" as const,
              args: [userAddress] as readonly [`0x${string}`],
            },
          ]
        : []),
    ],
  });

  const pricePerShare = results[0].result as bigint;     // 1e18 scaled
  const totalSupply = results[1].result as bigint;        // total shares
  const totalAssets = results[2].result as bigint;         // total USDC in vault+strategy

  const tvlUsdc = Number(formatUnits(totalAssets, 6));     // USDC has 6 decimals

  let userShares = 0n;
  let userAssetsUsdc = 0;

  if (userAddress && results[3]?.result) {
    userShares = results[3].result as bigint;
    // Convert shares to assets: shares * pricePerShare / 1e18
    const userAssets = (userShares * pricePerShare) / BigInt(1e18);
    userAssetsUsdc = Number(formatUnits(userAssets, 6));
  }

  return {
    pricePerShare: pricePerShare.toString(),
    totalSupply: totalSupply.toString(),
    totalAssets: totalAssets.toString(),
    tvlUsdc,
    userShares: userShares.toString(),
    userAssetsUsdc,
  };
}
```

### 5.2 APY Calculation from Share Price History

```typescript
// src/lib/apy.ts

interface VaultSnapshot {
  price_per_share: string;  // BigInt string, 1e18 scaled
  recorded_at: string;       // ISO timestamp
}

export function calculateAPY(snapshots: VaultSnapshot[]): {
  apy7d: number;
  apy30d: number;
  apySinceInception: number;
} {
  if (snapshots.length < 2) {
    return { apy7d: 0, apy30d: 0, apySinceInception: 0 };
  }

  const now = new Date();
  const latest = snapshots[0]; // most recent
  const latestPPS = Number(latest.price_per_share) / 1e18;

  function apySince(targetDate: Date): number {
    // Find the snapshot closest to targetDate
    const target = snapshots.reduce((closest, s) => {
      const diff = Math.abs(new Date(s.recorded_at).getTime() - targetDate.getTime());
      const closestDiff = Math.abs(new Date(closest.recorded_at).getTime() - targetDate.getTime());
      return diff < closestDiff ? s : closest;
    });

    const targetPPS = Number(target.price_per_share) / 1e18;
    if (targetPPS === 0) return 0;

    const growthRate = (latestPPS - targetPPS) / targetPPS;
    const daysDiff = (now.getTime() - new Date(target.recorded_at).getTime()) / (1000 * 60 * 60 * 24);
    if (daysDiff < 1) return 0;

    // Annualize: (1 + rate) ^ (365 / days) - 1
    const annualized = Math.pow(1 + growthRate, 365 / daysDiff) - 1;
    return annualized * 100; // percentage
  }

  return {
    apy7d: apySince(new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)),
    apy30d: apySince(new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)),
    apySinceInception: apySince(new Date(snapshots[snapshots.length - 1].recorded_at)),
  };
}
```

### 5.3 Agent Activity Feed

```typescript
// src/lib/harvests.ts
import { supabaseAdmin } from "./supabase";

export async function getRecentHarvests(
  vaultAddress: string,
  limit = 20
) {
  const { data, error } = await supabaseAdmin
    .from("harvests")
    .select("*")
    .eq("vault_address", vaultAddress)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error) throw error;
  return data;
}
```

---

## 6. DATABASE SCHEMA

Run this SQL in the Supabase SQL Editor. One shot, creates everything.

```sql
-- ============================================================
-- USERS
-- ============================================================
-- <!-- Merged from claimall-spec.md: notification dedup columns -->
CREATE TABLE users (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_address    TEXT NOT NULL UNIQUE,
  nullifier_hash    TEXT NOT NULL UNIQUE,       -- HMAC'd for privacy
  notification_enabled       BOOLEAN DEFAULT FALSE,
  notification_threshold_usd DECIMAL(10, 2) DEFAULT 1.00,
  last_notified_at  TIMESTAMPTZ,               -- when last notification sent (dedup)
  last_claimable_usd DECIMAL(10, 2),           -- USD at last notification (dedup)
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_wallet ON users(wallet_address);
CREATE INDEX idx_users_notif ON users(notification_enabled) WHERE notification_enabled = TRUE;

-- ============================================================
-- DEPOSITS
-- ============================================================
CREATE TABLE deposits (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  vault_address   TEXT NOT NULL,
  tx_hash         TEXT NOT NULL,
  user_op_hash    TEXT,
  amount          DECIMAL(24, 6) NOT NULL,    -- human-readable USDC amount
  amount_wei      TEXT NOT NULL,               -- raw wei string
  shares_received TEXT,                        -- vault shares minted
  status          TEXT DEFAULT 'pending'
                  CHECK (status IN ('pending', 'confirmed', 'failed')),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  confirmed_at    TIMESTAMPTZ
);

CREATE INDEX idx_deposits_user ON deposits(user_id);
CREATE INDEX idx_deposits_vault ON deposits(vault_address);
CREATE INDEX idx_deposits_status ON deposits(status) WHERE status = 'pending';

-- ============================================================
-- WITHDRAWALS
-- ============================================================
CREATE TABLE withdrawals (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  vault_address   TEXT NOT NULL,
  tx_hash         TEXT NOT NULL,
  user_op_hash    TEXT,
  shares_burned   TEXT NOT NULL,               -- vault shares redeemed
  amount_received DECIMAL(24, 6),              -- USDC received (filled on confirm)
  amount_wei      TEXT,
  status          TEXT DEFAULT 'pending'
                  CHECK (status IN ('pending', 'confirmed', 'failed')),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  confirmed_at    TIMESTAMPTZ
);

CREATE INDEX idx_withdrawals_user ON withdrawals(user_id);
CREATE INDEX idx_withdrawals_vault ON withdrawals(vault_address);

-- ============================================================
-- HARVESTS (agent activity log)
-- ============================================================
CREATE TABLE harvests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_address     TEXT NOT NULL,
  strategy_address  TEXT NOT NULL,
  tx_hash           TEXT NOT NULL,
  harvester_address TEXT NOT NULL,
  want_earned       DECIMAL(24, 6),           -- profit in want token (USDC)
  want_earned_wei   TEXT,
  fee_total         DECIMAL(24, 6),
  gas_used          BIGINT,
  status            TEXT DEFAULT 'pending'
                    CHECK (status IN ('pending', 'confirmed', 'failed')),
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_harvests_vault ON harvests(vault_address);
CREATE INDEX idx_harvests_time ON harvests(created_at DESC);

-- ============================================================
-- VAULT SNAPSHOTS (for APY calculation)
-- ============================================================
CREATE TABLE vault_snapshots (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_address     TEXT NOT NULL,
  price_per_share   TEXT NOT NULL,             -- BigInt string (1e18 scaled)
  total_assets      TEXT NOT NULL,             -- BigInt string
  total_supply      TEXT NOT NULL,             -- BigInt string (total shares)
  tvl_usd           DECIMAL(16, 2),
  recorded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_snapshots_vault_time ON vault_snapshots(vault_address, recorded_at DESC);

-- Partition-friendly index for APY queries over time windows
CREATE INDEX idx_snapshots_lookup ON vault_snapshots(vault_address, recorded_at)
  INCLUDE (price_per_share);

-- ============================================================
-- NOTIFICATION LOG (stretch goal)
-- <!-- Merged from claimall-spec.md -->
-- ============================================================
CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,              -- 'harvest_complete', 'yield_update'
  title       TEXT NOT NULL,
  message     TEXT NOT NULL,
  sent_at     TIMESTAMPTZ DEFAULT NOW(),
  opened_at   TIMESTAMPTZ,               -- tracked if open callbacks available
  deep_link   TEXT
);

CREATE INDEX idx_notifications_user_sent ON notifications(user_id, sent_at);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON users
  FOR ALL USING (auth.role() = 'service_role');

ALTER TABLE deposits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON deposits
  FOR ALL USING (auth.role() = 'service_role');

ALTER TABLE withdrawals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON withdrawals
  FOR ALL USING (auth.role() = 'service_role');

ALTER TABLE harvests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON harvests
  FOR ALL USING (auth.role() = 'service_role');

ALTER TABLE vault_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON vault_snapshots
  FOR ALL USING (auth.role() = 'service_role');

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON notifications
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

## 7. API ROUTES

### 7.1 Auth: GET /api/auth/nonce

```typescript
// src/app/api/auth/nonce/route.ts
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import crypto from "crypto";

export async function GET() {
  const nonce = crypto.randomBytes(16).toString("hex");
  const cookieStore = await cookies();
  cookieStore.set("siwe-nonce", nonce, {
    httpOnly: true, secure: true, sameSite: "strict", maxAge: 300,
  });
  return NextResponse.json({ nonce });
}
```

### 7.2 Auth: POST /api/auth/verify-siwe

<!-- Merged from claimall-spec.md -->

Creates JWT session from SIWE wallet auth. Includes HMAC nullifier hashing and per-wallet authorization.

```typescript
// src/app/api/auth/verify-siwe/route.ts
import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";
import { SignJWT, jwtVerify } from "jose";
import { createHmac } from "crypto";

const JWT_SECRET = new TextEncoder().encode(process.env.JWT_SECRET);

/**
 * hashNullifier: one-way HMAC of the World ID nullifier hash.
 * Computed SERVER-SIDE ONLY -- raw nullifier never stored or leaked.
 * Uses a dedicated secret separate from JWT_SECRET.
 *
 * Env var: NULLIFIER_HMAC_SECRET (generate with: openssl rand -base64 32)
 */
function hashNullifier(nullifierHash: string): string {
  return createHmac("sha256", process.env.NULLIFIER_HMAC_SECRET!)
    .update(nullifierHash)
    .digest("hex");
}

export async function POST(req: NextRequest) {
  const { payload, nullifier_hash } = await req.json();

  // 1. Verify SIWE signature (via MiniKit utility or manual verification)
  // ...signature verification here...

  // 2. Create session JWT with HMAC'd nullifier
  const token = await new SignJWT({
    wallet: payload.address,
    nullifier: hashNullifier(nullifier_hash),
  })
    .setProtectedHeader({ alg: "HS256" })
    .setExpirationTime("15m")
    .sign(JWT_SECRET);

  // 3. Set httpOnly cookie
  const cookieStore = await cookies();
  cookieStore.set("session", token, {
    httpOnly: true,
    secure: true,
    sameSite: "strict",  // Provides baseline CSRF protection
    maxAge: 900,         // 15 minutes
  });

  return NextResponse.json({
    wallet_address: payload.address,
    expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
  });
}
```

### 7.2.1 Per-Wallet Auth Middleware

<!-- Merged from claimall-spec.md -->

**CRITICAL:** Every protected API route MUST verify that the session wallet matches the wallet in the request. This prevents acting on behalf of another user's wallet.

```typescript
// src/lib/session.ts
import { cookies } from "next/headers";
import { jwtVerify } from "jose";

const JWT_SECRET = new TextEncoder().encode(process.env.JWT_SECRET);

export async function requireAuth(req: Request): Promise<string> {
  const cookieStore = await cookies();
  const sessionCookie = cookieStore.get("session")?.value;
  if (!sessionCookie) {
    throw new Response("Unauthorized: no session", { status: 401 });
  }

  const { payload } = await jwtVerify(sessionCookie, JWT_SECRET);
  const sessionWallet = payload.wallet as string;
  if (!sessionWallet) {
    throw new Response("Unauthorized: invalid session", { status: 401 });
  }

  return sessionWallet;
}

export function assertWalletMatch(sessionWallet: string, requestWallet: string): void {
  if (sessionWallet.toLowerCase() !== requestWallet.toLowerCase()) {
    throw new Response("Forbidden: wallet mismatch", { status: 403 });
  }
}
```

### 7.2.2 CSRF Protection

<!-- Merged from claimall-spec.md -->

All state-changing API routes (POST, PUT, DELETE) are protected by the session cookie with `SameSite=Strict`:

- The cookie is never readable by client-side JavaScript (`httpOnly: true`)
- The cookie is only sent over HTTPS (`secure: true`)
- The cookie is never sent on cross-site requests (`sameSite: "strict"`)

No additional CSRF token needed for the hackathon. For production, add a double-submit cookie or synchronizer token pattern.

### 7.2.3 World ID Proof Freshness Check

<!-- Merged from claimall-spec.md -->

In the verify-worldid endpoint, check proof freshness to prevent replay attacks:

```typescript
const PROOF_MAX_AGE_MS = 5 * 60 * 1000; // 5 minutes
const proofAge = Date.now() - proofTimestamp;
if (proofAge > PROOF_MAX_AGE_MS) {
  return new Response("Proof expired: must be less than 5 minutes old", { status: 400 });
}
```

### 7.3 Auth: POST /api/auth/logout

```typescript
// src/app/api/auth/logout/route.ts
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

export async function POST() {
  const cookieStore = await cookies();
  cookieStore.delete("session");
  return NextResponse.json({ success: true });
}
```

### 7.4 GET /api/vaults -- List Vaults

```typescript
// src/app/api/vaults/route.ts
import { NextResponse } from "next/server";
import { getVaultData } from "@/lib/vault-reads";
import { getSession } from "@/lib/session";
import { supabaseAdmin } from "@/lib/supabase";
import { calculateAPY } from "@/lib/apy";
import { VAULTS } from "@/lib/constants";

export async function GET() {
  const session = await getSession();

  const vaults = await Promise.all(
    VAULTS.map(async (vault) => {
      // On-chain data
      const onchain = await getVaultData(
        vault.address as `0x${string}`,
        session?.wallet as `0x${string}` | undefined
      );

      // Historical snapshots for APY
      const { data: snapshots } = await supabaseAdmin
        .from("vault_snapshots")
        .select("price_per_share, recorded_at")
        .eq("vault_address", vault.address)
        .order("recorded_at", { ascending: false })
        .limit(90); // 90 days of hourly snapshots

      const apy = calculateAPY(snapshots || []);

      // Recent harvests
      const { data: harvests } = await supabaseAdmin
        .from("harvests")
        .select("tx_hash, want_earned, created_at")
        .eq("vault_address", vault.address)
        .order("created_at", { ascending: false })
        .limit(5);

      return {
        address: vault.address,
        name: vault.name,
        wantToken: vault.wantToken,
        wantSymbol: vault.wantSymbol,
        tvlUsdc: onchain.tvlUsdc,
        pricePerShare: onchain.pricePerShare,
        apy,
        userShares: onchain.userShares,
        userAssetsUsdc: onchain.userAssetsUsdc,
        recentHarvests: harvests || [],
      };
    })
  );

  return NextResponse.json({ vaults });
}
```

**Response shape:**

```json
{
  "vaults": [
    {
      "address": "0x...",
      "name": "Harvest USDC",
      "wantToken": "0x79A02482A880bCE3B13e09Da970dC34db4CD24d1",
      "wantSymbol": "USDC",
      "tvlUsdc": 125000.50,
      "pricePerShare": "1020000000000000000",
      "apy": { "apy7d": 8.2, "apy30d": 7.5, "apySinceInception": 6.8 },
      "userShares": "1000000000000000000",
      "userAssetsUsdc": 1020.00,
      "recentHarvests": [
        { "tx_hash": "0x...", "want_earned": 150.25, "created_at": "2026-04-03T..." }
      ]
    }
  ]
}
```

### 7.5 GET /api/vaults/[address] -- Vault Detail

```typescript
// src/app/api/vaults/[address]/route.ts
import { NextRequest, NextResponse } from "next/server";
import { getVaultData } from "@/lib/vault-reads";
import { getSession } from "@/lib/session";
import { supabaseAdmin } from "@/lib/supabase";
import { calculateAPY } from "@/lib/apy";

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ address: string }> }
) {
  const { address: vaultAddress } = await params;
  const session = await getSession();

  const onchain = await getVaultData(
    vaultAddress as `0x${string}`,
    session?.wallet as `0x${string}` | undefined
  );

  // Full snapshot history (hourly for 30 days)
  const { data: snapshots } = await supabaseAdmin
    .from("vault_snapshots")
    .select("price_per_share, total_assets, tvl_usd, recorded_at")
    .eq("vault_address", vaultAddress)
    .order("recorded_at", { ascending: false })
    .limit(720); // 30 days * 24 hours

  const apy = calculateAPY(snapshots || []);

  // User's deposit/withdrawal history
  let userHistory = null;
  if (session) {
    const [deposits, withdrawals] = await Promise.all([
      supabaseAdmin
        .from("deposits")
        .select("*")
        .eq("user_id", session.userId)
        .eq("vault_address", vaultAddress)
        .order("created_at", { ascending: false }),
      supabaseAdmin
        .from("withdrawals")
        .select("*")
        .eq("user_id", session.userId)
        .eq("vault_address", vaultAddress)
        .order("created_at", { ascending: false }),
    ]);

    userHistory = {
      deposits: deposits.data || [],
      withdrawals: withdrawals.data || [],
    };
  }

  // All harvests
  const { data: harvests } = await supabaseAdmin
    .from("harvests")
    .select("*")
    .eq("vault_address", vaultAddress)
    .order("created_at", { ascending: false })
    .limit(50);

  return NextResponse.json({
    vault: {
      address: vaultAddress,
      ...onchain,
      apy,
      snapshots: snapshots || [],
      harvests: harvests || [],
      userHistory,
    },
  });
}
```

### 7.6 POST /api/deposit/prepare

```typescript
// src/app/api/deposit/prepare/route.ts
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/session";
import { buildDepositPayload } from "@/lib/vault-actions";
import { VAULT_ADDRESS, USDC_ADDRESS } from "@/lib/constants";

export async function POST(req: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { amount } = await req.json(); // human-readable USDC amount, e.g. "100.50"

  if (!amount || isNaN(Number(amount)) || Number(amount) <= 0) {
    return NextResponse.json({ error: "Invalid amount" }, { status: 400 });
  }

  const payload = buildDepositPayload(
    VAULT_ADDRESS,
    USDC_ADDRESS,
    amount,
    session.wallet as `0x${string}`
  );

  return NextResponse.json({
    payload,
    summary: {
      action: "deposit",
      amount,
      token: "USDC",
      vault: VAULT_ADDRESS,
      transactions: payload.transactions.length,
    },
  });
}
```

### 7.7 POST /api/withdraw/prepare

```typescript
// src/app/api/withdraw/prepare/route.ts
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/session";
import { buildWithdrawPayload, buildWithdrawExactPayload } from "@/lib/vault-actions";
import { VAULT_ADDRESS } from "@/lib/constants";

export async function POST(req: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { shares, amount } = await req.json();
  // Either pass shares (bigint string) to redeem all, or amount (USDC string) to withdraw exact

  let payload;

  if (shares) {
    payload = buildWithdrawPayload(
      VAULT_ADDRESS,
      BigInt(shares),
      session.wallet as `0x${string}`
    );
  } else if (amount) {
    payload = buildWithdrawExactPayload(
      VAULT_ADDRESS,
      amount,
      session.wallet as `0x${string}`
    );
  } else {
    return NextResponse.json({ error: "Provide shares or amount" }, { status: 400 });
  }

  return NextResponse.json({
    payload,
    summary: {
      action: "withdraw",
      shares: shares || null,
      amount: amount || null,
      vault: VAULT_ADDRESS,
    },
  });
}
```

### 7.8 GET /api/harvests -- Agent Activity Feed

```typescript
// src/app/api/harvests/route.ts
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const vaultAddress = req.nextUrl.searchParams.get("vault");
  const limit = Math.min(Number(req.nextUrl.searchParams.get("limit") || 20), 100);

  let query = supabaseAdmin
    .from("harvests")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);

  if (vaultAddress) {
    query = query.eq("vault_address", vaultAddress);
  }

  const { data, error } = await query;

  if (error) {
    return NextResponse.json({ error: "Failed to fetch harvests" }, { status: 500 });
  }

  return NextResponse.json({ harvests: data });
}
```

### 7.9 POST /api/cron/harvest -- Trigger Harvest

```typescript
// src/app/api/cron/harvest/route.ts
import { NextRequest, NextResponse } from "next/server";
import { createWalletClient, createPublicClient, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { worldchain } from "@/lib/viem-client";
import { supabaseAdmin } from "@/lib/supabase";
import { VAULTS } from "@/lib/constants";

const MERKL_API = "https://api.merkl.xyz/v4";

export async function POST(req: NextRequest) {
  // Verify cron secret
  const auth = req.headers.get("authorization");
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const account = privateKeyToAccount(process.env.HARVESTER_PRIVATE_KEY as `0x${string}`);
  const walletClient = createWalletClient({
    account,
    chain: worldchain,
    transport: http(process.env.WORLD_CHAIN_RPC_URL),
  });
  const publicClient = createPublicClient({
    chain: worldchain,
    transport: http(process.env.WORLD_CHAIN_RPC_URL),
  });

  const results = [];

  for (const vault of VAULTS) {
    try {
      // Fetch Merkl proofs for the strategy
      const merklRes = await fetch(
        `${MERKL_API}/users/${vault.strategyAddress}/rewards?chainId=480`
      );
      const merklData = await merklRes.json();

      // Parse into harvest args
      const users: `0x${string}`[] = [];
      const tokens: `0x${string}`[] = [];
      const amounts: bigint[] = [];
      const proofs: `0x${string}`[][] = [];

      if (Array.isArray(merklData)) {
        for (const entry of merklData) {
          if (!entry.token?.address || !entry.amount) continue;
          const unclaimed = BigInt(entry.amount) - BigInt(entry.claimed || "0");
          if (unclaimed <= 0n) continue;
          users.push(vault.strategyAddress as `0x${string}`);
          tokens.push(entry.token.address as `0x${string}`);
          amounts.push(BigInt(entry.amount));
          proofs.push((entry.proofs || []) as `0x${string}`[]);
        }
      }

      // Execute harvest
      const txHash = await walletClient.writeContract({
        address: vault.strategyAddress as `0x${string}`,
        abi: parseAbi([
          "function harvest(address[],address[],uint256[],bytes32[][]) external",
        ]),
        functionName: "harvest",
        args: [users, tokens, amounts, proofs],
      });

      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

      // Record in DB
      await supabaseAdmin.from("harvests").insert({
        vault_address: vault.address,
        strategy_address: vault.strategyAddress,
        tx_hash: txHash,
        harvester_address: account.address,
        status: receipt.status === "success" ? "confirmed" : "failed",
        gas_used: Number(receipt.gasUsed),
      });

      results.push({ vault: vault.name, txHash, status: "success" });
    } catch (err: any) {
      results.push({ vault: vault.name, error: err.message, status: "failed" });
    }
  }

  return NextResponse.json({ results });
}
```

### 7.10 POST /api/cron/snapshot -- Take Vault Snapshots

```typescript
// src/app/api/cron/snapshot/route.ts
import { NextRequest, NextResponse } from "next/server";
import { getVaultData } from "@/lib/vault-reads";
import { supabaseAdmin } from "@/lib/supabase";
import { VAULTS } from "@/lib/constants";

export async function POST(req: NextRequest) {
  const auth = req.headers.get("authorization");
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const snapshots = [];

  for (const vault of VAULTS) {
    const data = await getVaultData(vault.address as `0x${string}`);

    snapshots.push({
      vault_address: vault.address,
      price_per_share: data.pricePerShare,
      total_assets: data.totalAssets,
      total_supply: data.totalSupply,
      tvl_usd: data.tvlUsdc,
    });
  }

  const { error } = await supabaseAdmin.from("vault_snapshots").insert(snapshots);

  if (error) {
    return NextResponse.json({ error: "Failed to insert snapshots" }, { status: 500 });
  }

  return NextResponse.json({ snapshotted: snapshots.length });
}
```

### 7.11 Push Notification System (Stretch Goal)

<!-- Merged from claimall-spec.md -->

#### POST /api/notifications/enable

Enables push notifications for the authenticated user. **IMPORTANT:** Do NOT accept a wallet address from the request body -- use the session wallet exclusively.

```typescript
// src/app/api/notifications/enable/route.ts
import { NextResponse } from "next/server";
import { requireAuth } from "@/lib/session";
import { supabaseAdmin } from "@/lib/supabase";

export async function POST(req: Request) {
  const sessionWallet = await requireAuth(req);

  await supabaseAdmin
    .from("users")
    .update({ notification_enabled: true })
    .eq("wallet_address", sessionWallet);

  return NextResponse.json({ enabled: true });
}
```

#### GET /api/cron/check-rewards

Cron-triggered endpoint that checks for yield updates and sends notifications.

```typescript
// src/app/api/cron/check-rewards/route.ts
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { data: users } = await supabaseAdmin
    .from("users")
    .select("*")
    .eq("notification_enabled", true);

  let notifiedCount = 0;

  for (const user of users || []) {
    try {
      // Check latest harvests since last notification
      const { data: recentHarvests } = await supabaseAdmin
        .from("harvests")
        .select("rewards_compounded_usd")
        .gt("created_at", user.last_notified_at || "1970-01-01")
        .order("created_at", { ascending: false });

      const totalUsd = (recentHarvests || [])
        .reduce((sum: number, h: any) => sum + (h.rewards_compounded_usd || 0), 0);

      // Notification deduplication:
      // Only notify if compounded amount INCREASED since last notification.
      const shouldNotify =
        totalUsd >= user.notification_threshold_usd &&
        (user.last_claimable_usd === null || totalUsd > user.last_claimable_usd);

      if (shouldNotify) {
        await sendNotification(user, totalUsd);

        await supabaseAdmin
          .from("users")
          .update({
            last_notified_at: new Date().toISOString(),
            last_claimable_usd: totalUsd,
          })
          .eq("id", user.id);

        notifiedCount++;
      }
    } catch (err) {
      console.error(`Failed to check for ${user.id}`, err);
    }
  }

  return NextResponse.json({ checked: (users || []).length, notified: notifiedCount });
}

async function sendNotification(user: any, totalUsd: number) {
  const response = await fetch(
    "https://developer.worldcoin.org/api/v2/minikit/send-notification",
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${process.env.WORLD_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        app_id: process.env.NEXT_PUBLIC_APP_ID,
        wallets: [user.wallet_address],
        title: "Yield compounded!",
        message: `The agent compounded $${totalUsd.toFixed(2)} for depositors`,
        mini_app_path: "/",
      }),
    }
  );

  if (!response.ok) {
    throw new Error(`Notification failed: ${response.status}`);
  }

  await supabaseAdmin.from("notifications").insert({
    user_id: user.id,
    type: "harvest_complete",
    title: "Yield compounded!",
    message: `$${totalUsd.toFixed(2)} compounded`,
    deep_link: "/",
  });
}
```

#### Notification Quality Rules

World's notification system has a quality threshold:
- **Minimum 10% open rate required** -- if open rate drops below 10%, notifications are paused for 1 week
- Max 1 notification per user per 4-hour cycle
- Do NOT notify for trivial amounts (respect threshold setting)
- Dedup via `last_claimable_usd` prevents re-notifying for same amount

#### MiniKit Notification Permission (Client-Side)

```typescript
import { MiniKit, Permission } from "@worldcoin/minikit-js";

async function requestNotifications() {
  const result = await MiniKit.commandsAsync.requestPermission({
    permission: Permission.Notifications,
  });

  if (result.finalPayload.status === "success") {
    await fetch("/api/notifications/enable", { method: "POST" });
    return true;
  }
  return false;
}
```

#### Vercel Cron Configuration

```json
// vercel.json (add to existing crons array)
{
  "crons": [
    {
      "path": "/api/cron/harvest",
      "schedule": "0 */6 * * *"
    },
    {
      "path": "/api/cron/snapshot",
      "schedule": "0 * * * *"
    },
    {
      "path": "/api/cron/check-rewards",
      "schedule": "0 */4 * * *"
    }
  ]
}
```

### 7.12 Error Handling Matrix

<!-- Merged from claimall-spec.md -->

| Scenario | Behavior | HTTP Status |
|----------|----------|-------------|
| Merkl API timeout (5s) | Agent skips harvest, retries next cycle | N/A (agent) |
| Merkl API down | Agent skips harvest, retries next cycle | N/A (agent) |
| Invalid session / expired JWT | Reject request | 401 |
| Wallet address mismatch (body vs session) | Reject request | 403 |
| Transaction preparation fails (encoding, proofs) | Descriptive error | 500 |
| Supabase unreachable | Descriptive error, log to console | 500 |
| Agent harvest tx reverts | Log error, continue to next vault | N/A (agent) |
| No claimable Merkl rewards | Agent skips vault, logs info | N/A (agent) |
| Cron secret mismatch | Reject request | 401 |
| World notification API failure | Log error, continue to next user | N/A (cron) |

---

## 8. FILE STRUCTURE

The frontend is a single-page terminal UI. No multi-page routing. All user interaction happens through typed commands and tappable shortcut buttons.

```
harvest-v2/
├── .env.local
├── .env.example
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── vercel.json
├── package.json
│
├── contracts/                              # Foundry project (unchanged)
│   ├── foundry.toml
│   ├── src/
│   │   ├── vaults/
│   │   │   ├── HarvestVaultV7.sol         # Simplified Beefy vault (ERC4626)
│   │   │   └── HarvestVaultFactory.sol    # Optional factory for multi-vault
│   │   ├── strategies/
│   │   │   └── StrategyMorpho.sol         # Morpho strategy with hardcoded swaps
│   │   └── interfaces/
│   │       ├── IMetaMorpho.sol
│   │       ├── ISwapRouter.sol
│   │       └── IStrategyV7.sol
│   ├── script/
│   │   └── Deploy.s.sol                   # Deployment script
│   ├── test/
│   │   ├── HarvestVault.t.sol
│   │   └── StrategyMorpho.t.sol
│   └── lib/                               # Forge dependencies (OZ, etc.)
│
├── agent/                                  # Standalone harvester agent (unchanged)
│   ├── harvester.ts                       # Main harvest loop
│   ├── chain.ts                           # Viem chain definition
│   ├── rebalance-check.ts                 # APY comparison logic
│   ├── register-agent.ts                  # AgentKit registration
│   └── x402-client.ts                     # x402 payment client
│
├── public/
│   ├── harvest-logo.svg
│   └── favicon.ico
│
├── src/
│   ├── app/
│   │   ├── page.tsx                       # Terminal (only page)
│   │   ├── layout.tsx                     # Dark theme, monospace font
│   │   ├── globals.css                    # Terminal aesthetic styles
│   │   │
│   │   └── api/                           # Same API routes
│   │       ├── auth/
│   │       │   ├── nonce/route.ts
│   │       │   ├── verify-siwe/route.ts
│   │       │   ├── verify-worldid/route.ts
│   │       │   └── logout/route.ts
│   │       │
│   │       ├── vaults/
│   │       │   ├── route.ts               # GET -- list all vaults
│   │       │   └── [address]/
│   │       │       └── route.ts           # GET -- vault detail
│   │       │
│   │       ├── deposit/
│   │       │   ├── prepare/route.ts       # POST -- build deposit payload
│   │       │   └── confirm/route.ts       # POST -- record deposit
│   │       │
│   │       ├── withdraw/
│   │       │   ├── prepare/route.ts       # POST -- build withdraw payload
│   │       │   └── confirm/route.ts       # POST -- record withdrawal
│   │       │
│   │       ├── harvests/
│   │       │   └── route.ts              # GET -- agent activity feed
│   │       │
│   │       ├── cron/
│   │       │   ├── harvest/route.ts       # POST -- trigger harvest
│   │       │   ├── snapshot/route.ts      # POST -- take vault snapshots
│   │       │   └── check-rewards/route.ts # GET -- check yields, send notifications (stretch)
│   │       │
│   │       ├── notifications/
│   │       │   └── enable/route.ts        # POST -- enable push notifications (stretch)
│   │       │
│   │       └── x402/
│   │           └── yield-data/route.ts    # GET -- x402-protected yield data
│   │
│   ├── components/
│   │   ├── Terminal.tsx                   # Main terminal component (full-screen)
│   │   ├── CommandInput.tsx               # Input bar + shortcut buttons
│   │   ├── TerminalOutput.tsx             # Scrollable output area
│   │   └── TerminalLine.tsx               # Single line renderer
│   │
│   ├── lib/
│   │   ├── commands/
│   │   │   ├── index.ts                   # Command router/parser
│   │   │   ├── portfolio.ts               # portfolio command
│   │   │   ├── vaults.ts                  # vaults command
│   │   │   ├── deposit.ts                 # deposit command
│   │   │   ├── withdraw.ts                # withdraw command
│   │   │   ├── agent.ts                   # agent status / agent harvest
│   │   │   └── help.ts                    # help command
│   │   ├── terminal-format.ts             # Formatting helpers (tables, alignment)
│   │   ├── constants.ts                   # Addresses, ABIs, vault configs
│   │   ├── vault-actions.ts               # Build deposit/withdraw payloads
│   │   ├── vault-reads.ts                 # Read on-chain vault state
│   │   ├── apy.ts                         # APY calculation from snapshots
│   │   ├── viem-client.ts                 # Viem public client
│   │   ├── supabase.ts                    # Supabase clients
│   │   ├── session.ts                     # JWT session helpers
│   │   ├── auth.ts                        # MiniKit auth flow
│   │   └── poll-tx.ts                     # UserOp confirmation polling
│   │
│   └── types/
│       └── index.ts                       # All TypeScript interfaces
```

---

## 9. ENVIRONMENT VARIABLES

```bash
# ============================================================
# World Mini App
# ============================================================
NEXT_PUBLIC_APP_ID=app_harvest_v2_xxxxxxxxxxxxx
WORLD_API_KEY=sk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# ============================================================
# Supabase
# ============================================================
NEXT_PUBLIC_SUPABASE_URL=https://xxxxxxxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIs...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIs...

# ============================================================
# RPC
# ============================================================
WORLD_CHAIN_RPC_URL=https://worldchain-mainnet.g.alchemy.com/v2/YOUR_KEY
ALCHEMY_KEY=YOUR_KEY

# ============================================================
# Session / Auth
# ============================================================
JWT_SECRET=<openssl rand -hex 32>
NULLIFIER_HMAC_SECRET=<openssl rand -hex 32>

# ============================================================
# Contract Addresses (filled after deployment)
# ============================================================
NEXT_PUBLIC_VAULT_ADDRESS=0x__DEPLOYED_VAULT__
NEXT_PUBLIC_STRATEGY_ADDRESS=0x__DEPLOYED_STRATEGY__

# ============================================================
# Harvester Agent
# ============================================================
HARVESTER_PRIVATE_KEY=0x__AGENT_PRIVATE_KEY__
AGENT_WALLET_ADDRESS=0x__AGENT_PUBLIC_ADDRESS__
AGENT_PRIVATE_KEY=0x__SAME_OR_DIFFERENT_KEY__

# ============================================================
# AI / Agent
# ============================================================
OPENAI_API_KEY=sk-...

# ============================================================
# Deployment
# ============================================================
DEPLOYER_PRIVATE_KEY=0x__DEPLOYER_KEY__
FEE_RECIPIENT=0x__TREASURY_ADDRESS__
STRATEGIST_ADDRESS=0x__STRATEGIST_ADDRESS__
WORLDSCAN_API_KEY=__API_KEY__

# ============================================================
# Cron
# ============================================================
CRON_SECRET=<openssl rand -hex 16>

# ============================================================
# App
# ============================================================
NEXT_PUBLIC_APP_URL=https://harvest-v2.vercel.app
NEXT_PUBLIC_BLOCK_EXPLORER_URL=https://worldscan.org
```

---

## 10. CONTRACT ADDRESSES REFERENCE

### World Chain Mainnet (Chain ID: 480)

| Contract | Address | Notes |
|---|---|---|
| USDC | `0x79A02482A880bCE3B13e09Da970dC34db4CD24d1` | Bridged USDC, 6 decimals |
| WETH | `0x4200000000000000000000000000000000000006` | Wrapped ETH, 18 decimals |
| WLD | `0x2cFc85d8E48F8EAB294be644d9E25C3030863003` | Worldcoin token, 18 decimals |
| Merkl Distributor | `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae` | Reward claim contract |
| Uniswap V3 Router | `0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6` | SwapRouter |
| Uniswap V3 NFPM | `0xec12a9F9a09f50550686363766Cc153D03c27b5e` | NonfungiblePositionManager |
| Morpho Re7 USDC | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` | MetaMorpho vault |
| Morpho Re7 WETH | `0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca` | MetaMorpho vault |

### Deployed by Harvest v2 (fill after deployment)

| Contract | Address | Notes |
|---|---|---|
| HarvestVaultV7 (impl) | `0x__TBD__` | Implementation contract |
| HarvestVaultV7 (proxy) | `0x__TBD__` | User-facing vault address |
| StrategyMorpho (impl) | `0x__TBD__` | Implementation contract |
| StrategyMorpho (proxy) | `0x__TBD__` | Strategy proxy |

---

## 11. TYPESCRIPT TYPES

```typescript
// src/types/index.ts

// ============================================================
// Terminal Types
// ============================================================

export interface TerminalLine {
  type: "input" | "output" | "system" | "error" | "success";
  content: string;
  timestamp?: string;
}

export type CommandHandler = (
  args: string[],
  wallet: string,
  pushLine: (line: TerminalLine) => void
) => Promise<void>;

export type QuickCommand = "portfolio" | "vaults" | "deposit" | "withdraw" | "agent status";

// ============================================================
// Vault Types
// ============================================================

export interface VaultConfig {
  address: string;
  name: string;
  wantToken: string;
  wantSymbol: string;
  wantDecimals: number;
  strategyAddress: string;
  morphoVault: string;
}

export interface VaultData {
  address: string;
  name: string;
  wantToken: string;
  wantSymbol: string;
  tvlUsdc: number;
  pricePerShare: string;     // BigInt string, 1e18 scaled
  totalSupply: string;       // BigInt string
  totalAssets: string;       // BigInt string
  apy: {
    apy7d: number;
    apy30d: number;
    apySinceInception: number;
  };
  userShares: string;        // BigInt string
  userAssetsUsdc: number;
  recentHarvests: HarvestRecord[];
}

export interface VaultDetailResponse {
  vault: VaultData & {
    snapshots: VaultSnapshot[];
    harvests: HarvestRecord[];
    userHistory: {
      deposits: DepositRecord[];
      withdrawals: WithdrawalRecord[];
    } | null;
  };
}

export interface VaultSnapshot {
  price_per_share: string;
  total_assets: string;
  tvl_usd: number;
  recorded_at: string;
}

// ============================================================
// Transaction Types
// ============================================================

export interface PreparedPayload {
  chainId: number;
  transactions: {
    to: `0x${string}`;
    data: `0x${string}`;
  }[];
}

export interface DepositPrepareRequest {
  amount: string;              // human-readable USDC
}

export interface WithdrawPrepareRequest {
  shares?: string;             // BigInt string -- redeem all shares
  amount?: string;             // human-readable USDC -- withdraw exact
}

export interface PrepareResponse {
  payload: PreparedPayload;
  summary: {
    action: "deposit" | "withdraw";
    amount?: string;
    shares?: string;
    token: string;
    vault: string;
    transactions: number;
  };
}

// ============================================================
// Database Records
// ============================================================

export interface User {
  id: string;
  wallet_address: string;
  nullifier_hash: string;           // HMAC'd for privacy
  notification_enabled: boolean;
  notification_threshold_usd: number;
  last_notified_at: string | null;  // ISO timestamp, for dedup
  last_claimable_usd: number | null; // USD at last notification, for dedup
  created_at: string;
  updated_at: string;
}

export interface DepositRecord {
  id: string;
  user_id: string;
  vault_address: string;
  tx_hash: string;
  user_op_hash: string | null;
  amount: number;
  amount_wei: string;
  shares_received: string | null;
  status: "pending" | "confirmed" | "failed";
  created_at: string;
  confirmed_at: string | null;
}

export interface WithdrawalRecord {
  id: string;
  user_id: string;
  vault_address: string;
  tx_hash: string;
  user_op_hash: string | null;
  shares_burned: string;
  amount_received: number | null;
  amount_wei: string | null;
  status: "pending" | "confirmed" | "failed";
  created_at: string;
  confirmed_at: string | null;
}

export interface HarvestRecord {
  id: string;
  vault_address: string;
  strategy_address: string;
  tx_hash: string;
  harvester_address: string;
  want_earned: number | null;
  want_earned_wei: string | null;
  fee_total: number | null;
  gas_used: number | null;
  status: "pending" | "confirmed" | "failed";
  created_at: string;
}

// ============================================================
// Auth Types
// ============================================================

export interface SessionData {
  wallet: string;
  userId: string;
  exp: number;
}

export interface NonceResponse {
  nonce: string;
}

export interface VerifyWorldIdRequest {
  merkle_root: string;
  nullifier_hash: string;
  proof: string;
  verification_level?: "orb" | "device";
}

// <!-- Merged from claimall-spec.md -->

export interface VerifyWorldIdResponse {
  success: boolean;
  nullifier_hash: string;
}

export interface WalletAuthRequest {
  payload: {
    status: string;
    address: string;
    message: string;
    signature: string;
  };
}

export interface SessionResponse {
  wallet_address: string;
  expires_at: string;
}

// ============================================================
// Merkl API Types
// <!-- Merged from claimall-spec.md -->
// ============================================================

/** Represents a single Merkl reward token with proof data */
export interface MerklReward {
  token: { symbol: string; address: string; decimals: number };
  amount: string;       // cumulative total earned (BigInt string)
  claimed: string;      // already claimed on-chain
  unclaimed: string;    // amount - claimed (what can be claimed now)
  unclaimedUsd: number;
  proofs: string[];     // merkle proof nodes (ready to pass to contract)
}

// ============================================================
// Notification Types
// <!-- Merged from claimall-spec.md -->
// ============================================================

export interface EnableNotificationsRequest {
  // No body -- wallet from session only
}

export interface EnableNotificationsResponse {
  enabled: boolean;
}

export interface NotificationRecord {
  id: string;
  user_id: string;
  type: string;       // 'harvest_complete', 'yield_update'
  title: string;
  message: string;
  sent_at: string;
  opened_at: string | null;
  deep_link: string | null;
}

// ============================================================
// API Response Types
// ============================================================

/** Standard error shape returned by every API route on failure */
export interface ApiError {
  error: string;       // human-readable message
  code?: string;       // machine-readable code, e.g. "MERKL_TIMEOUT"
}

export interface VaultListResponse {
  vaults: VaultData[];
}

export interface HarvestListResponse {
  harvests: HarvestRecord[];
}

export interface CronHarvestResponse {
  results: {
    vault: string;
    txHash?: string;
    error?: string;
    status: "success" | "failed";
  }[];
}
```

---

## 12. KEY ABIs

### 12.1 HarvestVaultV7 (ERC4626 Vault)

```typescript
// src/lib/constants.ts (partial)

export const HARVEST_VAULT_ABI = [
  // ERC4626 deposit: transfer want from msg.sender, mint shares to receiver
  {
    inputs: [
      { name: "assets", type: "uint256" },
      { name: "receiver", type: "address" },
    ],
    name: "deposit",
    outputs: [{ name: "shares", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  // ERC4626 withdraw: burn shares from owner, transfer exact assets to receiver
  {
    inputs: [
      { name: "assets", type: "uint256" },
      { name: "receiver", type: "address" },
      { name: "owner", type: "address" },
    ],
    name: "withdraw",
    outputs: [{ name: "shares", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  // ERC4626 redeem: burn exact shares from owner, transfer assets to receiver
  {
    inputs: [
      { name: "shares", type: "uint256" },
      { name: "receiver", type: "address" },
      { name: "owner", type: "address" },
    ],
    name: "redeem",
    outputs: [{ name: "assets", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  // Share price: (totalAssets * 1e18) / totalSupply
  {
    inputs: [],
    name: "getPricePerFullShare",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // Total assets in vault + strategy
  {
    inputs: [],
    name: "balance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // ERC20: user's share balance
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // ERC20: total shares outstanding
  {
    inputs: [],
    name: "totalSupply",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // ERC4626: preview how many shares for given assets
  {
    inputs: [{ name: "assets", type: "uint256" }],
    name: "previewDeposit",
    outputs: [{ name: "shares", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // ERC4626: preview how many assets for given shares
  {
    inputs: [{ name: "shares", type: "uint256" }],
    name: "previewRedeem",
    outputs: [{ name: "assets", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // Strategy address
  {
    inputs: [],
    name: "strategy",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  // Want token address
  {
    inputs: [],
    name: "want",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
] as const;
```

### 12.2 StrategyMorpho

```typescript
export const STRATEGY_MORPHO_ABI = [
  // Harvest: claim rewards, swap, redeposit
  {
    inputs: [
      { name: "merklUsers", type: "address[]" },
      { name: "merklTokens", type: "address[]" },
      { name: "merklAmounts", type: "uint256[]" },
      { name: "merklProofs", type: "bytes32[][]" },
    ],
    name: "harvest",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  // Total want controlled by strategy
  {
    inputs: [],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // Idle want in strategy contract
  {
    inputs: [],
    name: "balanceOfWant",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // Want deposited in Morpho vault
  {
    inputs: [],
    name: "balanceOfPool",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  // Want token address
  {
    inputs: [],
    name: "want",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  // Harvest event
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "caller", type: "address" },
      { indexed: false, name: "wantEarned", type: "uint256" },
      { indexed: false, name: "fee", type: "uint256" },
    ],
    name: "Harvest",
    type: "event",
  },
] as const;
```

### 12.3 ERC20 (USDC)

```typescript
export const ERC20_ABI = [
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "decimals",
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "symbol",
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
    type: "function",
  },
] as const;
```

### 12.4 Vault Configs Constant

```typescript
// src/lib/constants.ts (continued)

export const USDC_ADDRESS = "0x79A02482A880bCE3B13e09Da970dC34db4CD24d1" as const;
export const WETH_ADDRESS = "0x4200000000000000000000000000000000000006" as const;
export const WLD_ADDRESS = "0x2cFc85d8E48F8EAB294be644d9E25C3030863003" as const;
export const MERKL_DISTRIBUTOR = "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae" as const;

// Fill these after deployment
export const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export const STRATEGY_ADDRESS = (process.env.NEXT_PUBLIC_STRATEGY_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export const VAULTS: VaultConfig[] = [
  {
    address: VAULT_ADDRESS,
    name: "Harvest USDC",
    wantToken: USDC_ADDRESS,
    wantSymbol: "USDC",
    wantDecimals: 6,
    strategyAddress: STRATEGY_ADDRESS,
    morphoVault: "0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B",
  },
];
```

---

## END OF DOCUMENT

Summary of what a developer does with this document:

1. Fork Beefy contracts, strip governance (Section 1)
2. Deploy via Foundry to World Chain (Section 2)
3. Wire MiniKit deposit/withdraw flows as terminal command handlers (Section 3)
4. Run the harvest agent on a cron (Section 4)
5. Build the terminal UI with command components; read on-chain data + Supabase snapshots (Section 5)
6. Create database tables (Section 6)
7. Implement API routes (Section 7)
8. Scaffold the terminal-based file structure (Section 8)
9. Configure env vars (Section 9)
10. Reference contract addresses (Section 10)
11. Use the type definitions including TerminalLine and CommandHandler (Section 11)
12. Import the ABIs (Section 12)
