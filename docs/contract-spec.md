# Harvest: Smart Contract Specification

> Definitive contract reference for the hackathon team.
> Every modification, every function signature, every deployment parameter.

**Version:** 2.0 (Permit2 ambiguity resolved, authoritative)
**Date:** April 3, 2026
**Status:** Implementation-ready -- no remaining decisions
**Companion to:** `product-spec.md`, `technical-design.md`

---

## Table of Contents

1. [Part 1: Beefy Fork -- Exact Changes Needed](#part-1-beefy-fork----exact-changes-needed)
   - [A. BeefyVaultV7.sol (HarvestVault)](#a-beefyvaultv7sol-harvestvault)
   - [B. StrategyMorpho.sol](#b-strategymorphosol)
   - [C. BeefySwapper.sol -- Eliminated](#c-beefyswappersol----eliminated)
   - [D. Fee Structure](#d-fee-structure)
   - [E. Factory Contracts](#e-factory-contracts)
2. [Part 2: Deployment Script](#part-2-deployment-script)
   - [Part 2.5: AgentKit Server-Side Integration](#part-25-agentkit-server-side-integration-x402-protected-deposit)
   - [Part 2.6: Why AgentKit -- Not Bolted On](#part-26-why-agentkit----not-bolted-on)
3. [Part 3: FPS Assessment](#part-3-fps-forge-proposal-simulator-assessment)
4. [Part 4: Testing Strategy](#part-4-testing-strategy)
5. [Part 5: Security Considerations](#part-5-security-considerations)
6. [Appendix A: Complete Interface Definitions](#appendix-a-complete-interface-definitions)
7. [Appendix B: Contract Address Registry](#appendix-b-contract-address-registry)
8. [Appendix C: File Manifest](#appendix-c-file-manifest)
9. [Appendix D: foundry.toml](#appendix-d-foundrytoml)
10. [Appendix E: remappings.txt](#appendix-e-remappingstxt)

---

## Part 1: Beefy Fork -- Exact Changes Needed

### Source Repository

```
github.com/beefyfinance/beefy-contracts (MIT License)
Commit: 5c1b65f3c9b5e03bde67adba08aa42b6f0e4e5b0  (main as of 2026-04-03)
Verify: git ls-remote https://github.com/beefyfinance/beefy-contracts.git HEAD
```

### Dependency Graph

```
BeefyVaultV7Factory
  └── BeefyVaultV7 (implementation template)
        └── IStrategyV7 (interface to strategy)

StrategyMorpho
  └── BaseAllToNativeFactoryStrat
        └── IStrategyFactory (keeper, fees, global pause)
        └── IBeefySwapper (generic swap routing)
        └── IFeeConfig (fee tiers)
  └── IERC4626 (MetaMorpho vault)
  └── IMerklClaimer (Merkl distributor)
```

We are flattening this dependency tree significantly. The fork eliminates `IStrategyFactory`, `IBeefySwapper`, `IFeeConfig`, and the complex base strategy, replacing them with hardcoded equivalents.

---

### A. BeefyVaultV7.sol (HarvestVault)

**Original file:** `contracts/BIFI/vaults/BeefyVaultV7.sol`
**Our file:** `contracts/src/vaults/HarvestVault.sol`

#### What Stays As-Is

The core vault accounting logic is battle-tested and does not change:

| Function | Purpose | Changes |
|----------|---------|---------|
| `initialize()` | Sets strategy, name, symbol, approvalDelay | Signature changes (see below) |
| `want()` | Returns the underlying token (USDC.e) | No change |
| `balance()` | Total want: vault idle + strategy balance | No change |
| `available()` | Want sitting idle in vault | No change |
| `getPricePerFullShare()` | Share price: `balance() * 1e18 / totalSupply()` | No change |
| `earn()` | Push idle want to strategy | No change |
| `withdraw(uint256 _shares)` | Burn shares, pull want from strategy | No change |
| `withdrawAll()` | Withdraw all sender shares | No change |
| `depositAll()` | Deposit all sender want | Calls modified `deposit()` |
| `inCaseTokensGetStuck()` | Rescue stuck tokens | No change |

The ERC-20 share token (mooToken / harvestToken) is unchanged: `ERC20Upgradeable`, `OwnableUpgradeable`, `ReentrancyGuardUpgradeable`.

#### What Gets Modified

##### Modification 1: deposit() -- Permit2 Allowance-Based Transfer

<!-- Interface verified against Permit2 source at lib/permit2/src/AllowanceTransfer.sol on 2026-04-03.
     - approve(address token, address spender, uint160 amount, uint48 expiration) external  [line 26]
     - transferFrom(address from, address to, uint160 amount, address token) external  [line 59]
     - allowance(address user, address token, address spender) returns (uint160, uint48, uint48)  [line 111 of IAllowanceTransfer]
     - Signature-based PermitTransferFrom is NOT used. Only allowance-based flow.
-->

**Decision: Use Permit2 allowance-based `transferFrom`. No signature-based flow. No fallbacks. One path.**

**Why this works in World App:** World App **pre-approves all ERC-20 tokens to the Permit2 contract** (`0x000000000022D473030F116dDEE9F6B43aC78BA3`) automatically. Users never need to call `token.approve(Permit2)` -- it is already done. The only step the user performs via MiniKit is approving our vault as a spender within Permit2 (via `Permit2.approve()`), then calling `vault.deposit()`. The vault internally calls `Permit2.transferFrom()` to pull tokens.

**Before (Beefy original):**

```solidity
function deposit(uint _amount) public nonReentrant {
    strategy.beforeDeposit();
    uint256 _pool = balance();
    want().safeTransferFrom(msg.sender, address(this), _amount);
    earn();
    uint256 _after = balance();
    _amount = _after - _pool;
    uint256 shares = 0;
    if (totalSupply() == 0) {
        shares = _amount;
    } else {
        shares = (_amount * totalSupply()) / _pool;
    }
    _mint(msg.sender, shares);
}
```

**After (Harvest -- single canonical deposit function):**

```solidity
import {IPermit2} from "../interfaces/IPermit2.sol";

// State variable added:
IPermit2 public constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

/// @notice Deposit want tokens into the vault. Pulls tokens via Permit2.
/// @dev User must have approved this vault as a Permit2 spender beforehand.
///      In World App, this is done in the same MiniKit multicall (step 1: Permit2.approve,
///      step 2: vault.deposit). The vault calls Permit2.transferFrom() to pull tokens.
/// @param _amount Amount of want token to deposit
function deposit(uint256 _amount) public override onlyHuman nonReentrant {
    strategy.beforeDeposit();

    uint256 _pool = balance();

    // Pull tokens via Permit2 allowance-based transferFrom
    // Requires: user approved Permit2 to spend their token (World App does this automatically)
    // Requires: user approved this vault as spender via Permit2.approve() (MiniKit multicall step 1)
    PERMIT2.transferFrom(msg.sender, address(this), uint160(_amount), address(want()));

    uint256 shares = totalSupply() == 0 ? _amount : (_amount * totalSupply()) / _pool;
    _mint(msg.sender, shares);
    earn();
}
```

There is **one** `deposit()` function. No overloads. No signature-based variant. No legacy `safeTransferFrom` path.

**Key differences from Beefy original:**
1. Uses `PERMIT2.transferFrom()` instead of `want().safeTransferFrom()`
2. Amount cast to `uint160` (Permit2 uses `uint160` for amounts, not `uint256`)
3. Removed deflationary-token check (`_after - _pool`) -- USDC.e is not deflationary
4. `earn()` moved after `_mint()` for clarity (order does not matter for accounting)
5. `onlyHuman` modifier added for World ID / AgentKit gate

**MiniKit integration (TypeScript side):**

```typescript
import { encodeFunctionData } from "viem";

const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";
const USDC_E_ADDRESS = "0x79A02482A880bCE3F13e09Da970dC34db4CD24d1";
const VAULT_ADDRESS = "0x..."; // deployed vault address

// Expiration: 30 minutes from now (short-lived approval)
const expiration = Math.floor(Date.now() / 1000) + 1800;

// 2-step atomic multicall via MiniKit sendTransaction
const result = await MiniKit.sendTransaction({
  chainId: 480,
  transactions: [
    // Step 1: Approve vault as spender in Permit2
    {
      to: PERMIT2_ADDRESS,
      data: encodeFunctionData({
        abi: PERMIT2_ABI,
        functionName: "approve",
        args: [USDC_E_ADDRESS, VAULT_ADDRESS, BigInt(amountRaw), expiration],
      }),
    },
    // Step 2: Deposit into vault (vault calls Permit2.transferFrom internally)
    {
      to: VAULT_ADDRESS,
      data: encodeFunctionData({
        abi: HARVEST_VAULT_ABI,
        functionName: "deposit",
        args: [BigInt(amountRaw)],
      }),
    },
  ],
});
```

**Why NOT signature-based PermitTransferFrom:**
- Requires EIP-712 signature construction on the frontend, adding complexity
- The allowance-based path is simpler: two calls in a multicall, no signatures to construct
- World App already pre-approved tokens to Permit2, so only one `Permit2.approve()` call is needed
- Verified against Permit2 source: `AllowanceTransfer.sol` line 59 (`transferFrom`) and line 26 (`approve`)

##### Modification 2: Verified Humans Gate -- "DeFi, for Humans"

**Core thesis:** The vault cryptographically guarantees every depositor is a unique verified human. This is the on-chain enforcement of "DeFi, for humans." Two verification paths exist: World ID for direct human deposits, and AgentKit for human-backed agent deposits. Both paths converge on a single on-chain mapping.

**Recommendation: Option A -- Off-chain verification, on-chain whitelist.**

**Why Option A over Option B:**

| Criterion | Option A (Off-chain) | Option B (On-chain) |
|-----------|---------------------|---------------------|
| Gas cost per deposit | ~2,100 gas (SLOAD check) | ~200,000+ gas (proof verification) |
| Complexity | Low -- one mapping, one setter | High -- WorldID contract integration, proof parsing |
| Trust assumption | Trusted backend signer | Trustless | 
| Hackathon speed | Fast to implement | Slow, error-prone |
| Demo reliability | High | Medium (proof generation can fail) |
| Prize judges | "World ID gates deposits" -- both options satisfy this | On-chain is more impressive but riskier |

**Option A wins for hackathon.** The backend verifies the World ID proof (or AgentKit challenge) via the respective APIs, then calls `vault.setVerified(userAddress, true)` from the owner wallet. The contract checks `verifiedHumans[msg.sender]` on deposit.

**New code to add:**

```solidity
// --- Verified Humans Gate (unified for World ID + AgentKit) ---

/// @notice Mapping of addresses verified as unique humans (or human-backed agents)
mapping(address => bool) public verifiedHumans;

/// @notice Emitted when a user/agent is verified or unverified
event HumanVerification(address indexed user, bool verified);

/// @notice Modifier that gates deposits to verified humans only
modifier onlyHuman() {
    require(verifiedHumans[msg.sender], "Harvest: humans only");
    _;
}

/// @notice Set the verification status for an address
/// @dev Called by the backend/owner after:
///      - World ID verification (human deposits via MiniKit), OR
///      - AgentKit verification (agent deposits via x402 endpoint)
/// @param user The user or agent address to verify
/// @param status True to verify, false to revoke
function setVerified(address user, bool status) external onlyOwner {
    verifiedHumans[user] = status;
    emit HumanVerification(user, status);
}
```

**NOTE:** The previous `worldIdVerified` / `setWorldIdVerified` / `worldIdSigner` pattern is superseded by `verifiedHumans` / `setVerified`. The unified mapping covers both World ID and AgentKit verification paths. Only `onlyOwner` can call `setVerified` -- for hackathon, the deployer EOA is the owner. Post-hackathon, transfer ownership to a multisig.

**Integration in initialize():**

```solidity
function initialize(
    IStrategyV7 _strategy,
    string memory _name,
    string memory _symbol,
    uint256 _approvalDelay
) public initializer {
    __ERC20_init(_name, _symbol);
    __Ownable_init();
    __ReentrancyGuard_init();
    strategy = _strategy;
    approvalDelay = _approvalDelay;
}
```

**Deposit already gated:** The canonical `deposit(uint256)` function in Modification 1 already includes the `onlyHuman` modifier. No separate override needed. `depositAll()` calls `deposit()` internally, so it is also gated.

```solidity
// depositAll inherits the gate from deposit():
function depositAll() public onlyHuman {
    deposit(want().balanceOf(msg.sender));
}
```

##### Two Deposit Paths + Bot Rejection

There are exactly two valid deposit paths and one rejection case:

**Path 1: Human deposits via World App (MiniKit)**

```
1. User verifies with World ID (IDKit / MiniKit.verify)
2. Backend verifies proof: POST https://developer.world.org/api/v4/verify/{rp_id}
3. Backend calls vault.setVerified(userAddress, true) via deployer/owner wallet
4. User calls deposit() via MiniKit sendTransaction
5. Contract checks verifiedHumans[msg.sender] -> allowed
```

**Path 2: Agent deposits via x402 API (AgentKit)**

```
1. External agent hits POST /api/deposit/agent endpoint
2. Server returns 402 with AgentKit extension (CAIP-122 challenge)
3. Agent signs challenge with their registered wallet
4. Server verifies signature + checks AgentBook on-chain: lookupHuman(agentAddress)
5. If human-backed: server calls vault.setVerified(agentAddress, true)
6. Agent can now call deposit() on the contract directly
7. If NOT human-backed: request rejected (403)
```

**Path 3: Random bot (rejected)**

```
1. Bot tries deposit() directly on the contract
2. verifiedHumans[msg.sender] is false
3. Transaction reverts with "Harvest: humans only"
```

**Backend flow (Next.js API route -- human path):**

```
User opens app
  -> MiniKit.verify(World ID proof) -> sends to backend
  -> Backend POST /api/v4/verify/{rp_id} -> success
  -> Backend calls vault.setVerified(userAddress, true) via deployer key
  -> User can now deposit
```

##### Modification 3: Simplified Strategy Upgrade

**What gets stripped:**

```solidity
// REMOVE: Strategy candidate with timelock
struct StratCandidate {             // DELETE
    address implementation;         // DELETE
    uint proposedTime;              // DELETE
}                                   // DELETE
StratCandidate public stratCandidate; // DELETE
uint256 public approvalDelay;         // DELETE (or keep but set to 0)

// REMOVE: proposeStrat() and upgradeStrat() with timelock logic
function proposeStrat(address _implementation) public onlyOwner { ... }  // DELETE
function upgradeStrat() public onlyOwner { ... }                         // DELETE

// REPLACE WITH: Direct strategy setter (owner only, no timelock)
function setStrategy(IStrategyV7 _strategy) external onlyOwner {
    require(address(_strategy) != address(0), "!strategy");
    require(_strategy.want() == want(), "!want");
    // Retire old strategy if one exists
    if (address(strategy) != address(0)) {
        strategy.retireStrat();
    }
    strategy = _strategy;
    earn();
}
```

##### Complete HarvestVault.sol -- Diff Summary

```
 contracts/BIFI/vaults/BeefyVaultV7.sol -> contracts/src/vaults/HarvestVault.sol

 KEEP:
   - ERC20Upgradeable inheritance
   - OwnableUpgradeable inheritance
   - ReentrancyGuardUpgradeable inheritance
   - IStrategyV7 strategy state variable
   - want(), balance(), available(), getPricePerFullShare()
   - earn(), withdraw(), withdrawAll()
   - inCaseTokensGetStuck()
   - All events (NewStratCandidate -> removed, UpgradeStrat -> removed)

 MODIFY:
   - initialize() -> simplified (no _worldIdSigner, owner is the verifier)
   - deposit(uint) -> replaced: uses Permit2.transferFrom(), onlyHuman modifier
   - depositAll() -> calls modified deposit(), inherits onlyHuman gate
   - proposeStrat() + upgradeStrat() -> replace with setStrategy()

 ADD:
   + IPermit2 constant PERMIT2
   + verifiedHumans mapping (unified for World ID + AgentKit)
   + onlyHuman modifier
   + setVerified(address, bool) -- owner-only, covers both verification paths
   + HumanVerification event

 DELETE:
   - want().safeTransferFrom() in deposit (replaced by Permit2.transferFrom)
   - StratCandidate struct
   - stratCandidate state variable
   - approvalDelay state variable (or keep at 0)
   - proposeStrat()
   - upgradeStrat()
   - NewStratCandidate event
   - UpgradeStrat event
   - worldIdSigner state variable (superseded by onlyOwner on setVerified)
   - setWorldIdSigner() (no longer needed)
   - worldIdVerified mapping (replaced by verifiedHumans)
```

---

### B. StrategyMorpho.sol

**Original file:** `contracts/BIFI/strategies/Morpho/StrategyMorpho.sol`
**Base class:** `contracts/BIFI/strategies/Common/BaseAllToNativeFactoryStrat.sol`
**Our file:** `contracts/src/strategies/HarvestStrategyMorpho.sol`

The Beefy `StrategyMorpho` extends `BaseAllToNativeFactoryStrat`, which has deep dependencies on `IStrategyFactory`, `IBeefySwapper`, and `IFeeConfig`. We flatten the inheritance: our strategy is a standalone contract that cherry-picks the logic we need.

#### What Stays As-Is (from StrategyMorpho.sol)

| Function | Purpose | Changes |
|----------|---------|---------|
| `balanceOfPool()` | Returns `storedBalance` (skim model) | No change |
| `_deposit(uint)` | `morphoVault.mint(shares, this)` with skim accounting | No change |
| `_withdraw(uint)` | `morphoVault.redeem(requiredShares, this, this)` | No change |
| `_emergencyWithdraw()` | Redeem all shares from Morpho | No change |
| `_verifyRewardToken()` | Prevent adding morphoVault as reward | No change |
| `claim()` | External Merkl claim with correct interface | No change |
| `storedBalance` tracking | Skim harvest model (see below) | No change |

**The Skim Harvest Model (critical to understand):**

Beefy's StrategyMorpho uses a "skim" model rather than claiming Merkl rewards directly in harvest. Here is how it works:

1. `storedBalance` tracks the strategy's known deposit in Morpho
2. The actual Morpho share balance grows over time (yield accrues)
3. On harvest, `_swapRewardsToNative()` computes `shares - requiredShares` (the excess)
4. The excess shares are redeemed and swapped to native, then to want
5. This excess represents the yield earned since last harvest

This means the strategy does NOT need to call `merkl.claim()` inside `harvest()`. Instead:
- Merkl rewards are claimed separately via the `claim()` function (called by the agent beforehand, or in the same transaction)
- The claimed tokens arrive as reward token balances in the strategy
- The harvest flow swaps those reward tokens to native, then to want, then redeposits

#### What Gets Modified

##### Modification 1: Flatten BaseAllToNativeFactoryStrat

We eliminate the `IStrategyFactory` dependency entirely. The factory provides: `keeper()`, `beefyFeeConfig()`, `beefyFeeRecipient()`, `globalPause()`, `native()`. We replace these with direct state variables.

**Before (via BaseAllToNativeFactoryStrat):**

```solidity
// Depends on factory for everything:
IStrategyFactory public factory;

function keeper() public view returns (address) {
    return factory.keeper();
}
function beefyFeeConfig() public view returns (IFeeConfig) {
    return IFeeConfig(factory.beefyFeeConfig());
}
function beefyFeeRecipient() public view returns (address) {
    return factory.beefyFeeRecipient();
}
modifier ifNotPaused() {
    if (paused() || factory.globalPause() || factory.strategyPause(stratName()))
        revert StrategyPaused();
    _;
}
```

**After (direct state variables):**

```solidity
// Direct state -- no factory dependency
address public keeper;
address public feeRecipient;
address public strategist;
address public vault;
address public want;
address public native;   // WETH on World Chain

modifier onlyManager() {
    require(msg.sender == owner() || msg.sender == keeper, "!manager");
    _;
}

// Simplified pause check -- no global pause registry
// Just uses PausableUpgradeable._pause() / _unpause()
```

##### Modification 2: Replace BeefySwapper with Inline Uniswap V3

**Before (via BaseAllToNativeFactoryStrat):**

```solidity
function _swap(address tokenFrom, address tokenTo, uint amount) internal {
    if (amount > 0 && tokenFrom != tokenTo) {
        IERC20(tokenFrom).forceApprove(swapper, amount);
        IBeefySwapper(swapper).swap(tokenFrom, tokenTo, amount);
    }
}
```

**After (direct Uniswap V3 call):**

```solidity
import {ISwapRouter02} from "../interfaces/ISwapRouter02.sol";

ISwapRouter02 public constant SWAP_ROUTER =
    ISwapRouter02(0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6);

/// @notice Hardcoded swap paths for each reward token -> want
/// @dev Packed encoding: tokenA | fee | tokenB | fee | tokenC
mapping(address => bytes) public swapPaths;

/// @notice Minimum output ratio in basis points (9900 = 1% max slippage)
uint256 public slippageBps;

/// @notice Swap a reward token to want using Uniswap V3 exactInput
/// @param _from Token to swap from
/// @param _to Token to swap to (unused -- path determines output)
/// @param _amount Amount of _from to swap
function _swap(address _from, address _to, uint256 _amount) internal {
    if (_amount == 0) return;

    bytes memory path = swapPaths[_from];
    require(path.length > 0, "!swapPath");

    IERC20(_from).forceApprove(address(SWAP_ROUTER), _amount);

    // For hackathon: use amountOutMinimum = 0 with a note
    // World Chain has a private mempool (no public MEV) so sandwich attacks
    // are not a concern on L2. In production, use an oracle for minAmountOut.
    SWAP_ROUTER.exactInput(
        ISwapRouter02.ExactInputParams({
            path: path,
            recipient: address(this),
            amountIn: _amount,
            amountOutMinimum: 0
        })
    );
}
```

**Swap Path Configuration for World Chain:**

```solidity
// WLD -> WETH -> USDC.e (multi-hop)
bytes memory wldToUsdc = abi.encodePacked(
    address(0x2cFc85d8E48F8EAB294be644d9E25C3030863003), // WLD
    uint24(3000),                                          // 0.3% fee tier
    address(0x4200000000000000000000000000000000000006),   // WETH
    uint24(500),                                           // 0.05% fee tier
    address(0x79A02482A880bCE3F13e09Da970dC34db4CD24d1)    // USDC.e
);

// MORPHO -> WETH -> USDC.e (if MORPHO rewards exist)
bytes memory morphoToUsdc = abi.encodePacked(
    address(0xe2108e43dBD43c9Dc6E494F86c4C4D938Bd10f56), // MORPHO
    uint24(3000),                                          // 0.3% fee tier
    address(0x4200000000000000000000000000000000000006),   // WETH
    uint24(500),                                           // 0.05% fee tier
    address(0x79A02482A880bCE3F13e09Da970dC34db4CD24d1)    // USDC.e
);
```

**NOTE:** Before deployment, verify these pools exist and have liquidity on Uniswap V3 on World Chain. Use the QuoterV2 at `0x10158D43e6cc414deE1Bd1eB0EfC6a5cBCfF244c` to test:

```bash
cast call 0x10158D43e6cc414deE1Bd1eB0EfC6a5cBCfF244c \
  "quoteExactInput(bytes,uint256)(uint256,uint160[],uint32[],uint256)" \
  $(cast abi-encode "f(address,uint24,address,uint24,address)" \
    0x2cFc85d8E48F8EAB294be644d9E25C3030863003 3000 \
    0x4200000000000000000000000000000000000006 500 \
    0x79A02482A880bCE3F13e09Da970dC34db4CD24d1) \
  1000000000000000000 \
  --rpc-url $WORLD_CHAIN_RPC
```

If WLD -> WETH -> USDC.e does not have liquidity, try:
1. WLD -> USDC.e direct (fee tier 3000 or 10000)
2. WLD -> WETH (3000) -> USDC.e (3000) -- different fee tier on second hop

##### Modification 3: Merkl Claim Integration

**Beefy's StrategyMorpho already has correct Merkl support.** The upstream `claim()` function matches the Merkl Distributor interface exactly:

```solidity
// Beefy upstream (KEEP AS-IS):
function claim(
    address[] calldata _tokens,
    uint256[] calldata _amounts,
    bytes32[][] calldata _proofs
) external {
    address[] memory users = new address[](1);
    users[0] = address(this);
    claimer.claim(users, _tokens, _amounts, _proofs);
}
```

**Merkl Distributor interface (verified):**

```solidity
interface IMerklClaimer {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
```

This matches the Merkl Distributor at `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae`. The `amounts` are cumulative (total ever claimable), not incremental. The Merkl API provides the correct cumulative amounts and proofs.

**Agent harvest flow (two calls):**

```
1. strategy.claim(tokens, amounts, proofs)   -- claims Merkl rewards to strategy
2. strategy.harvest()                        -- swaps rewards, skims yield, redeposits
```

Or combine into a single multicall if using a helper contract. For hackathon, two separate calls are fine.

##### Modification 4: Simplified Fee Logic

**Before (via BaseAllToNativeFactoryStrat):**

```solidity
function _chargeFees(address callFeeRecipient) internal {
    IFeeConfig.FeeCategory memory fees = beefyFeeConfig().getFees(address(this));
    uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;
    uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
    IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);
    uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
    IERC20(native).safeTransfer(beefyFeeRecipient(), beefyFeeAmount);
    uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
    IERC20(native).safeTransfer(strategist, strategistFeeAmount);
}
```

**After (hardcoded fees):**

```solidity
uint256 public constant PERFORMANCE_FEE = 0;    // 0% for hackathon
uint256 public constant FEE_DIVISOR = 10000;

function _chargeFees(address /*callFeeRecipient*/) internal {
    // No fees for hackathon MVP.
    // In production, charge 4.5% on harvested native:
    //   3.0% to feeRecipient (protocol treasury)
    //   1.0% to msg.sender (harvester incentive)
    //   0.5% to strategist
    //
    // For now, all harvested value goes back to depositors.
}
```

##### Modification 5: Simplified Harvest Flow

The base strategy's `_harvest()` does: claim -> swap rewards to native -> charge fees -> swap native to want -> deposit. We keep this flow but with our simplified swap.

**The full harvest function (flattened from BaseAllToNativeFactoryStrat):**

```solidity
/// @notice Compounds earnings. Called by the keeper/agent.
/// @dev Flow: skim excess Morpho shares -> swap rewards to native -> 
///      charge fees -> swap native to want -> redeposit
function harvest() external {
    _harvest(msg.sender, false);
}

function harvest(address callFeeRecipient) external {
    _harvest(callFeeRecipient, false);
}

function _harvest(address callFeeRecipient, bool onDeposit) internal whenNotPaused {
    uint256 beforeBal = balanceOfWant();

    // Step 1: Skim excess Morpho shares (yield that accrued since last harvest)
    _skimMorphoYield();

    // Step 2: Swap all reward token balances to native (WETH)
    _swapRewardsToNative();

    uint256 nativeBal = IERC20(native).balanceOf(address(this));
    if (nativeBal > minAmounts[native]) {
        // Step 3: Charge fees (0% for hackathon)
        _chargeFees(callFeeRecipient);

        // Step 4: Swap native (WETH) to want (USDC.e)
        _swapNativeToWant();

        uint256 wantHarvested = balanceOfWant() - beforeBal;
        totalLocked = wantHarvested + lockedProfit();
        lastHarvest = block.timestamp;

        // Step 5: Redeposit into Morpho
        if (!onDeposit) {
            deposit();
        }

        emit StratHarvest(msg.sender, wantHarvested, balanceOf());
    }
}

/// @notice Skim yield from Morpho -- redeem excess shares above storedBalance
/// @dev SUPERSEDED by optimized version below (no want->native->want round trip).
///      See the canonical _skimMorphoYield() in the Complete HarvestStrategyMorpho source.
function _skimMorphoYield() internal {
    try morphoVault.previewWithdraw(storedBalance) returns (uint256 requiredShares) {
        uint256 shares = morphoVault.balanceOf(address(this));
        if (shares > requiredShares) {
            uint256 sharesToRedeem = shares - requiredShares;
            uint256 redeemableAmount = morphoVault.previewRedeem(sharesToRedeem);
            if (redeemableAmount > minAmounts[want]) {
                morphoVault.redeem(sharesToRedeem, address(this), address(this));
                // Redeemed want stays in contract -- redeposited in Step 5
            }
        }
    } catch {
        // previewWithdraw reverted (stale Morpho state). Skip skimming.
    }
}

/// @notice Swap all reward tokens to native (WETH)
function _swapRewardsToNative() internal {
    for (uint256 i; i < rewards.length; ++i) {
        address token = rewards[i];
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount > minAmounts[token]) {
            _swap(token, native, amount);
        }
    }
}

/// @notice Swap native (WETH) to want (USDC.e)
function _swapNativeToWant() internal {
    uint256 nativeBal = IERC20(native).balanceOf(address(this));
    if (nativeBal > 0) {
        _swap(native, want, nativeBal);
    }
}
```

**Wait -- why swap to native first, then to want?**

This is Beefy's "AllToNative" pattern. All reward tokens are first swapped to the chain's native wrapped token (WETH), then from WETH to want. This simplifies routing: you only need reward->WETH paths and one WETH->want path, instead of reward->want paths for every reward token.

For our case:
- WLD -> WETH (via Uniswap V3, 0.3% pool)
- WETH -> USDC.e (via Uniswap V3, 0.05% pool)
- Morpho skimmed USDC.e -> WETH (via Uniswap V3, 0.05% pool) -> then back to USDC.e

**OPTIMIZATION:** For the skim path (want -> native -> want), this is a round trip that loses to fees. Skip the intermediate native step for skimmed yield. Also wrap `previewWithdraw` in try/catch for the stale oracle edge case:

```solidity
function _skimMorphoYield() internal {
    try morphoVault.previewWithdraw(storedBalance) returns (uint256 requiredShares) {
        uint256 shares = morphoVault.balanceOf(address(this));
        if (shares > requiredShares) {
            uint256 sharesToRedeem = shares - requiredShares;
            uint256 redeemableAmount = morphoVault.previewRedeem(sharesToRedeem);
            if (redeemableAmount > minAmounts[want]) {
                // Redeem directly to want -- no swap needed, yield is already in want
                morphoVault.redeem(sharesToRedeem, address(this), address(this));
                // DO NOT swap to native. The redeemed amount is already USDC.e.
                // It will be redeposited in Step 5.
            }
        }
    } catch {
        // previewWithdraw reverted (stale Morpho state). Skip skimming this cycle.
    }
}
```

This is correct because the Morpho vault's underlying IS our want token (USDC.e). Redeeming shares gives us USDC.e directly. No swap needed for the skim portion. The try/catch handles the edge case where `previewWithdraw` reverts due to stale oracle data or a removed market in the MetaMorpho vault.

**REVISED harvest flow:**

```
_harvest():
  1. _skimMorphoYield()       -> redeems excess Morpho shares to USDC.e (no swap)
  2. _swapRewardsToNative()   -> swaps WLD (and other rewards) to WETH
  3. _chargeFees()            -> takes fee cut from WETH (0% for hackathon)
  4. _swapNativeToWant()      -> swaps WETH to USDC.e
  5. deposit()                -> redeposits all USDC.e into Morpho
```

<!-- ERC-4626 interface verified against forge-std/src/interfaces/IERC4626.sol.
     All MetaMorpho calls used in this strategy match the standard:
     - deposit(uint256 assets, address receiver) -> returns shares
     - mint(uint256 shares, address receiver) -> returns assets
     - withdraw(uint256 assets, address receiver, address owner) -> returns shares
     - redeem(uint256 shares, address receiver, address owner) -> returns assets
     - previewDeposit/previewWithdraw/previewRedeem -> view functions
     - convertToShares/convertToAssets -> view functions
     - balanceOf(address) -> inherited from ERC-20 -->
##### Modification 5: Configure for World Chain Morpho Vaults

```solidity
// Hardcoded in initialize():
morphoVault = IERC4626(0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B); // Re7 USDC vault
claimer = IMerklClaimer(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);  // Merkl Distributor

// want = USDC.e = 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1
// native = WETH = 0x4200000000000000000000000000000000000006
```

#### Complete HarvestStrategyMorpho.sol -- Full Source

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ISwapRouter02} from "../interfaces/ISwapRouter02.sol";
import {IMerklClaimer} from "../interfaces/IMerklClaimer.sol";

/// @title HarvestStrategyMorpho
/// @notice Yield strategy for Morpho MetaMorpho vaults on World Chain.
///         Flattened from Beefy's StrategyMorpho + BaseAllToNativeFactoryStrat.
///         Strips factory/swapper/feeConfig dependencies.
/// @dev Skim harvest model: tracks storedBalance, redeems excess shares as yield.
contract HarvestStrategyMorpho is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // --- Core addresses ---
    address public vault;       // HarvestVault
    address public want;        // USDC.e
    address public native;      // WETH
    address public keeper;      // Agent EOA
    address public strategist;  // Fee recipient (unused at 0% fee)
    address public feeRecipient;

    // --- Protocol contracts ---
    IERC4626 public morphoVault;
    IMerklClaimer public claimer;
    ISwapRouter02 public constant SWAP_ROUTER =
        ISwapRouter02(0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6);

    // --- Reward management ---
    address[] public rewards;
    mapping(address => uint256) public minAmounts;
    mapping(address => bytes) public swapPaths; // token -> Uni V3 packed path

    // --- Skim harvest accounting ---
    uint256 public storedBalance;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;
    bool public harvestOnDeposit;

    // --- Fees (0% for hackathon) ---
    uint256 public constant PERFORMANCE_FEE = 0;
    uint256 public constant FEE_DIVISOR = 10000;
    uint256 constant DIVISOR = 1 ether;

    // --- Events ---
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 protocolFees, uint256 strategistFees);
    event SetKeeper(address keeper);
    event SetSwapPath(address indexed token, bytes path);

    // --- Errors ---
    error NotManager();
    error NotVault();

    // --- Modifiers ---
    modifier onlyManager() {
        if (msg.sender != owner() && msg.sender != keeper) revert NotManager();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    // ================================================================
    // INITIALIZER
    // ================================================================

    function initialize(
        address _vault,
        address _want,
        address _native,
        address _morphoVault,
        address _claimer,
        address _keeper,
        address _strategist,
        address _feeRecipient,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        bytes[] calldata _swapPaths
    ) external initializer {
        __Ownable_init();
        __Pausable_init();

        vault = _vault;
        want = _want;
        native = _native;
        morphoVault = IERC4626(_morphoVault);
        claimer = IMerklClaimer(_claimer);
        keeper = _keeper;
        strategist = _strategist;
        feeRecipient = _feeRecipient;

        if (_harvestOnDeposit) {
            harvestOnDeposit = true;
            lockDuration = 0;
        } else {
            lockDuration = 1 days;
        }

        require(_rewards.length == _swapPaths.length, "!length");
        for (uint256 i; i < _rewards.length; i++) {
            rewards.push(_rewards[i]);
            swapPaths[_rewards[i]] = _swapPaths[i];
        }
    }

    // ================================================================
    // VAULT INTERFACE -- called by HarvestVault
    // ================================================================

    /// @notice Deposit idle want into Morpho vault
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            IERC20(want).forceApprove(address(morphoVault), wantBal);
            uint256 shares = morphoVault.previewDeposit(wantBal);
            morphoVault.mint(shares, address(this));
            storedBalance += morphoVault.previewRedeem(shares);
            emit Deposit(balanceOf());
        }
    }

    /// @notice Withdraw want from Morpho back to HarvestVault
    function withdraw(uint256 _amount) external onlyVault {
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amount) {
            _withdrawFromMorpho(_amount - wantBal);
            wantBal = balanceOfWant();
        }
        if (wantBal > _amount) {
            wantBal = _amount;
        }
        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function _withdrawFromMorpho(uint256 amount) internal {
        if (amount > 0) {
            uint256 requiredShares = morphoVault.previewWithdraw(amount);
            uint256 redeemedAmount = morphoVault.redeem(
                requiredShares, address(this), address(this)
            );
            storedBalance -= redeemedAmount;
        }
    }

    /// @notice Hook called before vault deposit (harvest-on-deposit)
    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    // ================================================================
    // HARVEST -- the core compounding function
    // ================================================================

    /// @notice Compounds earnings. Callable by anyone.
    function harvest() external {
        _harvest(msg.sender, false);
    }

    function harvest(address callFeeRecipient) external {
        _harvest(callFeeRecipient, false);
    }

    function _harvest(address callFeeRecipient, bool onDeposit) internal whenNotPaused {
        uint256 beforeBal = balanceOfWant();

        // Step 1: Skim excess Morpho yield (redeems to want, no swap needed)
        _skimMorphoYield();

        // Step 2: Swap all reward token balances to native (WETH)
        _swapRewardsToNative();

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        // Only proceed if there is meaningful native balance OR skimmed want
        bool hasNative = nativeBal > minAmounts[native];
        bool hasSkimmedWant = balanceOfWant() > beforeBal;

        if (hasNative || hasSkimmedWant) {
            if (hasNative) {
                // Step 3: Charge fees (0% for hackathon)
                _chargeFees(callFeeRecipient);

                // Step 4: Swap native to want
                _swapNativeToWant();
            }

            uint256 wantHarvested = balanceOfWant() - beforeBal;
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;

            // Step 5: Redeposit into Morpho
            if (!onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    /// @notice Skim yield from Morpho -- redeem excess shares
    /// @dev Excess shares = actual shares - shares needed for storedBalance
    ///      Yield is already in want token, no swap needed.
    ///      Wrapped in try/catch: previewWithdraw can revert if Morpho vault
    ///      state is stale (e.g., after a market removal or oracle failure).
    ///      In that case, we skip skimming -- the harvest still processes
    ///      reward token swaps normally.
    function _skimMorphoYield() internal {
        try morphoVault.previewWithdraw(storedBalance) returns (uint256 requiredShares) {
            uint256 shares = morphoVault.balanceOf(address(this));
            if (shares > requiredShares) {
                uint256 sharesToRedeem = shares - requiredShares;
                uint256 redeemableAmount = morphoVault.previewRedeem(sharesToRedeem);
                if (redeemableAmount > minAmounts[want]) {
                    morphoVault.redeem(sharesToRedeem, address(this), address(this));
                    // Redeemed want stays in contract -- will be redeposited in Step 5
                }
            }
        } catch {
            // previewWithdraw reverted -- Morpho state may be stale.
            // Skip skimming this harvest cycle. Reward swaps still proceed.
        }
    }

    function _swapRewardsToNative() internal {
        for (uint256 i; i < rewards.length; ++i) {
            address token = rewards[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > minAmounts[token]) {
                _swap(token, native, amount);
            }
        }
    }

    function _chargeFees(address /*callFeeRecipient*/) internal {
        // 0% fee for hackathon. All yield goes to depositors.
        // Production version:
        // uint256 nativeBal = IERC20(native).balanceOf(address(this));
        // uint256 totalFee = nativeBal * PERFORMANCE_FEE / FEE_DIVISOR;
        // ... distribute to feeRecipient, callFeeRecipient, strategist
    }

    function _swapNativeToWant() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0 && native != want) {
            _swap(native, want, nativeBal);
        }
    }

    /// @notice Swap via Uniswap V3 exactInput using stored packed path
    function _swap(address _from, address _to, uint256 _amount) internal {
        if (_amount == 0 || _from == _to) return;

        bytes memory path = swapPaths[_from];
        require(path.length > 0, "!swapPath");

        IERC20(_from).forceApprove(address(SWAP_ROUTER), _amount);

        SWAP_ROUTER.exactInput(
            ISwapRouter02.ExactInputParams({
                path: path,
                recipient: address(this),
                amountIn: _amount,
                amountOutMinimum: 0  // World Chain private mempool, no sandwich risk
            })
        );
    }

    // ================================================================
    // MERKL CLAIM -- separate from harvest
    // ================================================================

    /// @notice Claim Merkl rewards. Called by agent before harvest().
    /// @param _tokens Reward token addresses
    /// @param _amounts Cumulative claimable amounts
    /// @param _proofs Merkle proofs per token
    function claim(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external {
        address[] memory users = new address[](1);
        users[0] = address(this);
        claimer.claim(users, _tokens, _amounts, _proofs);
    }

    function setClaimer(address _claimer) external onlyManager {
        claimer = IMerklClaimer(_claimer);
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        return storedBalance;
    }

    function lockedProfit() public view returns (uint256) {
        if (lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < lockDuration ? lockDuration - elapsed : 0;
        return totalLocked * remaining / lockDuration;
    }

    function rewardsLength() external view returns (uint256) {
        return rewards.length;
    }

    // ================================================================
    // ADMIN
    // ================================================================

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
        emit SetKeeper(_keeper);
    }

    function setSwapPath(address _token, bytes calldata _path) external onlyManager {
        swapPaths[_token] = _path;
        emit SetSwapPath(_token, _path);
    }

    function addReward(address _token, bytes calldata _path) external onlyManager {
        require(_token != want, "!want");
        require(_token != native, "!native");
        require(_token != address(morphoVault), "!morphoVault");
        rewards.push(_token);
        swapPaths[_token] = _path;
    }

    function removeReward(uint256 i) external onlyManager {
        rewards[i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    function setRewardMinAmount(address token, uint256 minAmount) external onlyManager {
        minAmounts[token] = minAmount;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        lockDuration = _harvestOnDeposit ? 0 : 1 days;
    }

    function setStoredBalance() external onlyOwner {
        uint256 bal = morphoVault.balanceOf(address(this));
        storedBalance = morphoVault.previewRedeem(bal);
    }

    function retireStrat() external onlyVault {
        _emergencyWithdraw();
        IERC20(want).safeTransfer(vault, balanceOfWant());
    }

    function panic() public onlyManager {
        _pause();
        _emergencyWithdraw();
    }

    function pause() public onlyManager {
        _pause();
    }

    function unpause() external onlyManager {
        _unpause();
        deposit();
    }

    function _emergencyWithdraw() internal {
        storedBalance = 0;
        uint256 bal = morphoVault.balanceOf(address(this));
        if (bal > 0) {
            morphoVault.redeem(bal, address(this), address(this));
        }
    }

    // Accept native ETH (for unwrapping WETH if needed)
    receive() external payable {}

    uint256[49] private __gap;
}
```

#### Diff Summary: StrategyMorpho

```
 Beefy StrategyMorpho + BaseAllToNativeFactoryStrat
   -> HarvestStrategyMorpho (flattened single contract)

 KEPT (from StrategyMorpho):
   - storedBalance skim model
   - _deposit() with mint + previewRedeem accounting
   - _withdraw() with previewWithdraw + redeem
   - _emergencyWithdraw()
   - claim() with IMerklClaimer interface
   - _verifyRewardToken() logic (inlined into addReward)
   - setStoredBalance()
   - addWantAsReward() -- removed (not needed for hackathon)

 KEPT (from BaseAllToNativeFactoryStrat):
   - harvest() / _harvest() flow
   - _swapRewardsToNative() loop
   - _swapNativeToWant()
   - deposit() / withdraw() / retireStrat()
   - beforeDeposit() / harvestOnDeposit
   - lockedProfit() / totalLocked / lockDuration
   - rewards[] / minAmounts mapping
   - pause() / unpause() / panic()
   - balanceOf() / balanceOfWant() / balanceOfPool()

 MODIFIED:
   - _swap() -> direct Uniswap V3 exactInput (was IBeefySwapper)
   - _chargeFees() -> hardcoded 0% (was IFeeConfig lookup)
   - _skimMorphoYield() -> skips want->native->want round trip
   - initialize() -> takes all params directly (was Addresses struct + factory)
   - onlyManager -> checks owner || keeper (was owner || factory.keeper())
   - ifNotPaused -> standard whenNotPaused (was paused || factory.globalPause)

 DELETED:
   - IStrategyFactory dependency (factory state var, keeper(), beefyFeeConfig(), etc.)
   - IBeefySwapper dependency (swapper state var)
   - IFeeConfig dependency (beefyFeeConfig(), beefyFeeRecipient())
   - globalPause / strategyPause checks
   - depositToken / setDepositToken (not needed)
   - depositFee() / withdrawFee() (always 0)
   - rewardsAvailable() / callReward() (always 0)
   - setVault() / setSwapper() / setStrategist()
   - __BaseStrategy_init()

 ADDED:
   + swapPaths mapping (token -> Uni V3 packed bytes)
   + SWAP_ROUTER constant
   + _skimMorphoYield() (extracted from _swapRewardsToNative override)
   + keeper state variable (direct, not via factory)
   + setKeeper()
```

---

### C. BeefySwapper.sol -- Eliminated

**Decision: Replace entirely with inline Uniswap V3 calls in the strategy.**

**Rationale:**

1. BeefySwapper is a generic multi-DEX swap router with oracle-based slippage protection, configurable routing tables, and admin-managed swap configurations. It is 500+ lines of code we do not need.

2. We have exactly one swap path: WLD -> WETH -> USDC.e. A second path if MORPHO rewards exist: MORPHO -> WETH -> USDC.e. And the native->want path: WETH -> USDC.e. Three paths total.

3. The inline `_swap()` function in `HarvestStrategyMorpho` (shown above) is 15 lines. It calls Uniswap V3 `exactInput` directly with a stored packed path. This is cleaner, cheaper to deploy, and eliminates an entire contract + approval chain.

4. For hackathon speed: one fewer contract to deploy, test, verify, and whitelist in the Developer Portal.

**What about slippage protection?** BeefySwapper uses an oracle to compute `amountOutMinimum`. We skip this because:
- World Chain uses a private mempool (sequencer ordering, no public mempool MEV)
- Sandwich attacks require mempool visibility, which World Chain does not provide
- Setting `amountOutMinimum = 0` is acceptable for hackathon
- In production, add a Chainlink price feed check or pass `minAmountOut` from the agent

**No new contract is created. The swap logic lives inside HarvestStrategyMorpho._swap().**

---

### D. Fee Structure

**Hackathon fee: 0% on everything.**

| Fee Type | Hackathon | Production |
|----------|-----------|------------|
| Performance fee (on harvest profits) | 0% | 4.5% |
| Deposit fee | 0% | 0% |
| Withdrawal fee | 0% | 0% |
| Call fee (harvester incentive) | 0% | 1.0% (of performance fee) |
| Protocol fee | 0% | 3.0% (of performance fee) |
| Strategist fee | 0% | 0.5% (of performance fee) |

**Why 0% for hackathon:**

1. Simplifies testing -- share price math is cleaner without fee deductions
2. Demo story is better -- "all yield goes to depositors"
3. Fee infrastructure adds code paths to test and debug
4. We can show the fee structure exists (constants in code, commented-out logic) without activating it

**Who receives fees in production:**

| Recipient | Address | Role |
|-----------|---------|------|
| `feeRecipient` | Deployer EOA or protocol multisig | Protocol treasury |
| `callFeeRecipient` | `msg.sender` (harvester) | Incentive to call harvest() |
| `strategist` | Deployer EOA | Strategy creator reward |

For hackathon, all three can be the deployer address. Fees are 0% so no transfers occur.

---

### E. Factory Contracts

#### BeefyVaultV7Factory.sol -- Keep for Convenience

**Decision: Keep, use as-is.**

**Original file:** `contracts/BIFI/vaults/BeefyVaultV7Factory.sol`
**Our file:** `contracts/src/vaults/HarvestVaultFactory.sol`

The factory is 30 lines. It uses EIP-1167 minimal proxy clones to deploy vault instances cheaply. Even for a single vault, it is worth keeping because:

1. Clone deployment costs ~45,000 gas vs ~2M+ gas for a full contract deployment
2. The factory pattern lets us add a WLD vault later (stretch goal) without redeploying
3. Zero modifications needed -- just change `BeefyVaultV7` references to `HarvestVault`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./HarvestVault.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

contract HarvestVaultFactory {
    using ClonesUpgradeable for address;

    HarvestVault public instance;

    event ProxyCreated(address proxy);

    constructor(address _instance) {
        if (_instance == address(0)) {
            instance = new HarvestVault();
        } else {
            instance = HarvestVault(_instance);
        }
    }

    function cloneVault() external returns (HarvestVault) {
        return HarvestVault(cloneContract(address(instance)));
    }

    function cloneContract(address implementation) public returns (address) {
        address proxy = implementation.clone();
        emit ProxyCreated(proxy);
        return proxy;
    }
}
```

#### StrategyFactory.sol -- Do NOT Use

**Decision: Deploy strategy directly. Do not use StrategyFactory.**

The Beefy `StrategyFactory` is a beacon proxy factory that also serves as the configuration registry (keeper, fee config, fee recipient, global pause). Since we eliminated the factory dependency from our strategy, `StrategyFactory` has no purpose.

Our strategy is a standard `OwnableUpgradeable` contract deployed behind an ERC1967 proxy (or deployed directly -- proxies are optional for a single deployment).

**For hackathon: deploy HarvestStrategyMorpho directly (no proxy).** Save gas and complexity. If we need upgradeability, use a transparent proxy.

---

## Part 2: Deployment Script

### Deployment Order and Dependencies

```
1. Deploy HarvestVault implementation (standalone, no constructor args)
2. Deploy HarvestVaultFactory(implementation)
3. Clone vault via factory.cloneVault()
4. Deploy HarvestStrategyMorpho (standalone)
5. Initialize strategy (vault=clone address, all config)
6. Set native->want swap path on strategy
7. Initialize vault clone (strategy, name, symbol, approvalDelay=0)
8. Set reward min amounts on strategy
9. Verify deployer as first human (vault.setVerified)
10. Seed deposit of 1 USDC.e via Permit2 (MANDATORY -- prevents share inflation)
```

### Complete Deploy.s.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HarvestVault} from "../src/vaults/HarvestVault.sol";
import {HarvestVaultFactory} from "../src/vaults/HarvestVaultFactory.sol";
import {HarvestStrategyMorpho} from "../src/strategies/HarvestStrategyMorpho.sol";
import {IPermit2} from "../src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployHarvest is Script {
    // ================================================================
    // WORLD CHAIN MAINNET ADDRESSES (Chain ID: 480)
    // ================================================================
    address constant USDC_E   = 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1;
    address constant WETH     = 0x4200000000000000000000000000000000000006;
    address constant WLD      = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    address constant MORPHO   = 0xe2108e43dBD43c9Dc6E494F86c4C4D938Bd10f56;

    address constant MORPHO_RE7_USDC = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address constant UNISWAP_ROUTER = 0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ================================================================
    // DEPLOYMENT
    // ================================================================
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address agentKeeper = vm.envOr("KEEPER_ADDRESS", deployer);
        console.log("=== HARVEST DEPLOYMENT ===");
        console.log("Deployer (vault owner, calls setVerified):", deployer);
        console.log("Keeper:", agentKeeper);
        console.log("Chain ID: 480 (World Chain)");
        console.log("");

        vm.startBroadcast(deployerKey);

        // ---- Step 1: Deploy Vault Implementation ----
        HarvestVault vaultImpl = new HarvestVault();
        console.log("[1/10] Vault implementation:", address(vaultImpl));

        // ---- Step 2: Deploy Factory ----
        HarvestVaultFactory factory = new HarvestVaultFactory(address(vaultImpl));
        console.log("[2/10] Vault factory:", address(factory));

        // ---- Step 3: Clone Vault ----
        HarvestVault vault = factory.cloneVault();
        console.log("[3/10] Vault clone:", address(vault));

        // ---- Step 4: Deploy Strategy ----
        HarvestStrategyMorpho strategy = new HarvestStrategyMorpho();
        console.log("[4/10] Strategy:", address(strategy));

        // ---- Step 5: Build swap paths ----
        // WLD -> WETH (0.3%) for reward swaps
        bytes memory wldToWeth = abi.encodePacked(
            WLD, uint24(3000), WETH
        );
        // WETH -> USDC.e (0.05%) for native-to-want
        bytes memory wethToUsdc = abi.encodePacked(
            WETH, uint24(500), USDC_E
        );
        // MORPHO -> WETH (0.3%) in case of MORPHO rewards
        bytes memory morphoToWeth = abi.encodePacked(
            MORPHO, uint24(3000), WETH
        );

        // Rewards array: WLD (primary)
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = WLD;

        bytes[] memory rewardPaths = new bytes[](1);
        rewardPaths[0] = wldToWeth;

        // ---- Step 6: Initialize Strategy ----
        strategy.initialize(
            address(vault),         // vault
            USDC_E,                 // want
            WETH,                   // native
            MORPHO_RE7_USDC,        // morphoVault
            MERKL_DISTRIBUTOR,      // claimer
            agentKeeper,            // keeper
            deployer,               // strategist
            deployer,               // feeRecipient
            false,                  // harvestOnDeposit
            rewardTokens,           // rewards
            rewardPaths             // swap paths (reward -> native)
        );
        console.log("[5/10] Strategy initialized");

        // ---- Step 7: Set native->want swap path on strategy ----
        strategy.setSwapPath(WETH, wethToUsdc);
        console.log("[6/10] WETH->USDC.e swap path set");

        // ---- Step 8: Initialize Vault ----
        // NOTE: No worldIdSigner parameter -- the unified verifiedHumans mapping
        // is managed by onlyOwner (the deployer EOA). The deployer calls
        // vault.setVerified(addr, true) after World ID or AgentKit verification.
        vault.initialize(
            strategy,               // strategy (IStrategyV7-compatible)
            "Harvest USDC",         // name
            "harvestUSDC",          // symbol
            0                       // approvalDelay (no timelock)
        );
        console.log("[7/10] Vault initialized");

        // ---- Step 9: Set min amounts to prevent dust swaps ----
        strategy.setRewardMinAmount(WLD, 1e17);      // 0.1 WLD minimum
        strategy.setRewardMinAmount(WETH, 1e14);     // 0.0001 WETH minimum
        strategy.setRewardMinAmount(USDC_E, 1e5);    // 0.1 USDC minimum
        console.log("[8/10] Min amounts set");

        // ---- Step 10: Verify deployer as first human (for seed deposit) ----
        // The deployer is the owner, so it can call setVerified on itself.
        // This allows the seed deposit to prevent the first-depositor attack.
        vault.setVerified(deployer, true);
        console.log("[9/10] Deployer verified as human (for seed deposit)");

        // ---- Step 11: Seed deposit (MANDATORY -- prevents first-depositor share inflation) ----
        // Deployer MUST hold >= 1 USDC.e before running this script.
        uint256 deployerUsdcBal = IERC20(USDC_E).balanceOf(deployer);
        require(deployerUsdcBal >= 1e6, "Deployer must hold >= 1 USDC.e for seed deposit");

        // ERC-20 approve Permit2 to spend deployer's USDC.e (not needed in World App,
        // but required here because deploy script runs from an EOA, not World App)
        IERC20(USDC_E).approve(PERMIT2, 1e6);
        // Approve vault as spender via Permit2
        IPermit2(PERMIT2).approve(USDC_E, address(vault), uint160(1e6), uint48(block.timestamp + 3600));
        vault.deposit(1e6);
        console.log("[10/10] Seed deposit of 1 USDC.e complete");

        vm.stopBroadcast();

        // ---- Summary ----
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Vault:            ", address(vault));
        console.log("Strategy:         ", address(strategy));
        console.log("Factory:          ", address(factory));
        console.log("Vault Impl:       ", address(vaultImpl));
        console.log("");
        console.log("=== WHITELIST THESE IN DEVELOPER PORTAL ===");
        console.log("1. Vault:         ", address(vault));
        console.log("2. USDC.e:        ", USDC_E);
        console.log("3. Permit2:       ", PERMIT2);
        console.log("");
        console.log("=== OWNERSHIP ===");
        console.log("Vault owner (can call setVerified):", deployer);
        console.log("Post-hackathon: transfer ownership to a multisig");
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Whitelist above contracts in Developer Portal");
        console.log("2. Seed deposit already included (1 USDC.e)");
        console.log("3. Call vault.setVerified(testUser, true) after World ID verification");
        console.log("4. Test deposit + harvest flow on mainnet");
        console.log("5. Deploy x402 endpoint for AgentKit agent verification");
    }
}
```

### Deployment Commands

```bash
# World Chain Mainnet (chain ID 480)
# RPC: https://worldchain-mainnet.g.alchemy.com/v2/$ALCHEMY_KEY
# Alternative RPC: https://worldchain-mainnet.gateway.tenderly.co

# Dry run (simulation)
forge script script/Deploy.s.sol:DeployHarvest \
  --rpc-url https://worldchain-mainnet.g.alchemy.com/v2/$ALCHEMY_KEY \
  --chain-id 480 \
  -vvvv

# Live deployment
forge script script/Deploy.s.sol:DeployHarvest \
  --rpc-url https://worldchain-mainnet.g.alchemy.com/v2/$ALCHEMY_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $WORLDSCAN_API_KEY \
  --chain-id 480 \
  -vvvv

# Verify contracts on WorldScan (if auto-verify fails)
forge verify-contract \
  --chain-id 480 \
  --etherscan-api-key $WORLDSCAN_API_KEY \
  --watch \
  $VAULT_IMPL_ADDRESS \
  src/vaults/HarvestVault.sol:HarvestVault

forge verify-contract \
  --chain-id 480 \
  --etherscan-api-key $WORLDSCAN_API_KEY \
  --watch \
  $STRATEGY_ADDRESS \
  src/strategies/HarvestStrategyMorpho.sol:HarvestStrategyMorpho
```

### Post-Deployment Checklist

```
[x] Contracts deployed and verified on WorldScan
[x] Seed deposit of 1 USDC.e completed (prevents first-depositor attack)
[ ] Whitelist in Developer Portal:
    [ ] Vault clone address
    [ ] USDC.e token address
    [ ] Permit2 address
[ ] Test on mainnet:
    [ ] vault.setVerified(testUser, true) via owner wallet
    [ ] deposit() via Permit2 multicall with test USDC.e (verified user)
    [ ] deposit() from unverified user -> reverts "Harvest: humans only"
    [ ] getPricePerFullShare() returns 1e18
    [ ] withdraw() returns correct amount
    [ ] strategy.claim() with test Merkl data
    [ ] strategy.harvest() compounds correctly
[ ] AgentKit integration:
    [ ] Deploy x402 endpoint at POST /api/deposit/agent
    [ ] Test agent verification flow (AgentBook lookup)
    [ ] Test agent deposit after verification
[ ] Configure agent:
    [ ] Set STRATEGY_ADDRESS in agent env
    [ ] Set VAULT_ADDRESS in agent env
    [ ] Fund agent wallet with ETH for gas
    [ ] Test agent harvest() call
```

---

## Part 2.5: AgentKit Server-Side Integration (x402-Protected Deposit)

This section covers the server-side x402-protected endpoint that allows human-backed agents to deposit into the vault. This is **Path 2** from the deposit paths above.

### Why This Endpoint Exists

The vault rejects `deposit()` from any address where `verifiedHumans[addr]` is false. For human users, verification happens via World ID. For agents, verification happens via AgentKit: the agent proves it is backed by a real human (registered in AgentBook on-chain), and the server calls `vault.setVerified(agentAddress, true)`.

### x402 Resource Server Configuration

```typescript
// POST /api/deposit/agent -- x402-protected
import {
  createAgentkitHooks,
  createAgentBookVerifier,
  declareAgentkitExtension,
} from '@worldcoin/agentkit';

const agentBook = createAgentBookVerifier();
const storage = new InMemoryAgentKitStorage();
const hooks = createAgentkitHooks({
  storage,
  agentBook,
  mode: { type: 'free' }, // free access for verified human-backed agents
});

// x402 resource server configuration
const routes = {
  'POST /api/deposit/agent': {
    accepts: [
      {
        scheme: 'exact',
        price: '$0.00',
        network: 'eip155:480',
        payTo: VAULT_ADDRESS,
      },
    ],
    extensions: declareAgentkitExtension({
      statement:
        'Verify your agent is backed by a real human to deposit into Harvest vault',
      mode: { type: 'free' },
    }),
  },
};
```

### Endpoint Handler

```typescript
// app/api/deposit/agent/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { createPublicClient, http } from 'viem';
import { worldchain } from 'viem/chains';

export async function POST(req: NextRequest) {
  // x402 middleware has already verified:
  // 1. Agent signed the CAIP-122 challenge
  // 2. AgentBook confirms agent wallet maps to a verified human

  const { agentAddress, depositAmount } = await req.json();

  // Call vault.setVerified(agentAddress, true) via deployer/owner wallet
  const tx = await walletClient.writeContract({
    address: VAULT_ADDRESS,
    abi: HARVEST_VAULT_ABI,
    functionName: 'setVerified',
    args: [agentAddress, true],
  });

  return NextResponse.json({
    verified: true,
    tx,
    message: 'Agent verified. You may now call deposit() on the vault directly.',
    vault: VAULT_ADDRESS,
  });
}
```

### Agent-Side Flow (calling agent's perspective)

```typescript
// External agent deposits into Harvest vault
// 1. Hit the x402 endpoint to get verified
const response = await fetch('https://harvest.app/api/deposit/agent', {
  method: 'POST',
  headers: {
    // x402 payment/challenge headers (handled by agent's x402 client)
  },
  body: JSON.stringify({ agentAddress: myWallet.address }),
});

// 2. Now deposit directly on-chain (agent is verified)
const depositTx = await walletClient.writeContract({
  address: VAULT_ADDRESS,
  abi: HARVEST_VAULT_ABI,
  functionName: 'deposit',
  args: [amount],
});
```

### AgentBook Verification Details

AgentBook is an on-chain registry that maps agent wallet addresses to anonymous human IDs (via World ID). The server-side check:

```typescript
// Server verifies agent is human-backed:
const isHumanBacked = await agentBook.lookupHuman(agentAddress);
// Returns the anonymous human ID if registered, null otherwise
// One human can register multiple agent wallets -- all map to the same human
// The vault doesn't need to care about this -- the human is still unique
```

---

## Part 2.6: Why AgentKit -- Not Bolted On

AgentKit is not a checkbox integration. It is load-bearing infrastructure for the vault's core guarantee.

**The vault's promise: every depositor is a unique verified human.**

To enforce this promise, the vault needs TWO gates:

| Depositor | Gate | Without It |
|-----------|------|-----------|
| Human user | World ID | Bots create fake accounts, sybil farm yields |
| Agent | AgentKit | Bots pretend to be agents, sybil farm yields |

**Without AgentKit, the vault cannot guarantee "every depositor is a unique human."** A bot could simply call `deposit()` directly on the contract. World ID only covers the MiniKit path (users in World App). Agents interact directly with the contract -- they need their own proof-of-humanity.

**What AgentKit provides:**
- On-chain registry (AgentBook) mapping agent wallets to verified humans
- CAIP-122 challenge-response flow for agent authentication
- x402 protocol integration for resource-gated access

**What this protects against:**
- Sybil farming of vault yields (auto-compounded rewards)
- Gaming of Merkl reward distribution
- Future airdrop farming (vault share holders)
- Wash trading of vault shares

**The pitch line:** "This is what AgentKit was built for -- proving you're human to ACCESS yield, not just to log in."

---

## Part 3: FPS (Forge Proposal Simulator) Assessment

### What FPS Does

FPS (github.com/solidity-labs-io/forge-proposal-simulator) is a framework for:

1. **Standardized governance proposal creation** -- encode calldata for governor/multisig proposals
2. **Programmatic calldata generation** -- structured way to build complex transaction sequences
3. **Testing proposals against forked state** -- simulate governance actions before execution
4. **Safe multisig proposal simulation** -- verify transactions before signing

### Assessment: NOT Worth It for This Hackathon

**Score: 2/10 utility for Harvest.**

#### Detailed Evaluation

| Question | Answer |
|----------|--------|
| Is FPS useful for a hackathon yield aggregator? | **No.** FPS targets governance-heavy protocols with timelocks, multisigs, and governor contracts. Harvest has none of these. The "agent" is an EOA calling `harvest()`. |
| Could FPS help with harvest() call simulation? | **Marginally.** We can simulate `harvest()` with a standard Foundry fork test (`forge test --fork-url`). FPS adds a governance wrapper around this that provides no value for EOA calls. |
| Could FPS help generate/verify agent calldata? | **No.** The agent calldata is trivial: `strategy.claim(tokens, amounts, proofs)` then `strategy.harvest()`. Two function calls. Viem/ethers encode this in one line. FPS is for complex multicall proposals with dozens of actions. |
| Is the overhead worth it for 36 hours? | **Absolutely not.** FPS requires: installing the library, understanding the proposal abstraction, writing proposal contracts that extend `Proposal.sol`, configuring the governance model. This is 2-4 hours of setup for zero functional value. |
| Could FPS help if we add a multisig later? | **Yes, but "later" does not exist in a 36-hour hackathon.** If we ship to production with a Safe multisig, FPS would help simulate admin actions (pause, upgrade strategy, change fees). That is a post-hackathon concern. |

#### The Simpler Alternative

For calldata generation and testing, use what we already have:

**1. Fork tests (Foundry):**

```solidity
// test/HarvestFork.t.sol
function test_harvestFlow() public {
    vm.createSelectFork("https://worldchain-mainnet.g.alchemy.com/v2/KEY");
    // ... test against live World Chain state
}
```

**2. Agent calldata (TypeScript/viem):**

```typescript
import { encodeFunctionData } from "viem";

const claimData = encodeFunctionData({
  abi: strategyAbi,
  functionName: "claim",
  args: [tokens, amounts, proofs],
});

const harvestData = encodeFunctionData({
  abi: strategyAbi,
  functionName: "harvest",
});

// Send both via agent wallet
await walletClient.sendTransaction({ to: strategyAddress, data: claimData });
await walletClient.sendTransaction({ to: strategyAddress, data: harvestData });
```

**3. Dry-run simulation (cast):**

```bash
# Simulate harvest on forked state
cast call $STRATEGY_ADDRESS "harvest()" \
  --rpc-url $WORLD_CHAIN_RPC \
  --from $AGENT_ADDRESS

# Simulate with full trace
cast run $TX_HASH --rpc-url $WORLD_CHAIN_RPC -vvvv
```

**Verdict: Skip FPS. Use Foundry fork tests + viem calldata encoding. Save those 2-4 hours for integration testing.**

### Updated FPS Assessment (Post-Thesis Evolution)

With the "DeFi, for humans" framing and the unified `verifiedHumans` gate:

- **FPS is NOT used for hackathon** -- overhead too high for 36 hours
- **The "governance" model is simple:** deployer EOA owns the vault, agent EOA calls harvest(). There are no timelocks, governors, or multisig proposals to simulate.
- **Post-hackathon:** consider FPS for multisig governance proposals (e.g., transferring vault ownership to a Safe, proposing fee changes, upgrading strategies via governance vote)
- **For now:** fork tests against World Chain mainnet are sufficient. The `setVerified()` call is owner-only and trivially testable without a proposal framework.

---

## Part 4: Testing Strategy

### Test File: `test/HarvestFork.t.sol`

All tests run against a fork of World Chain mainnet to use real Morpho vaults, real Uniswap pools, and real token balances.

### Setup

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {HarvestVault} from "../src/vaults/HarvestVault.sol";
import {HarvestVaultFactory} from "../src/vaults/HarvestVaultFactory.sol";
import {HarvestStrategyMorpho} from "../src/strategies/HarvestStrategyMorpho.sol";
import {IPermit2} from "../src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract HarvestForkTest is Test {
    // World Chain addresses
    address constant USDC_E = 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WLD = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    address constant MORPHO_RE7_USDC = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    HarvestVault vault;
    HarvestStrategyMorpho strategy;

    address deployer = address(0xDEAD);
    address keeper = address(0xBEEF);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address unverifiedUser = address(0xBAD);

    /// @dev Helper: approve vault via Permit2 and deposit (mirrors MiniKit multicall)
    function _permit2ApproveAndDeposit(address user, uint256 amount) internal {
        // Step 1: User approves their tokens to Permit2 (simulates World App pre-approval)
        IERC20(USDC_E).approve(address(PERMIT2), amount);
        // Step 2: User approves vault as Permit2 spender (MiniKit multicall step 1)
        PERMIT2.approve(USDC_E, address(vault), uint160(amount), uint48(block.timestamp + 3600));
        // Step 3: Deposit (MiniKit multicall step 2)
        vault.deposit(amount);
    }

    function setUp() public {
        // Fork World Chain mainnet
        vm.createSelectFork(vm.envString("WORLD_CHAIN_RPC"));

        vm.startPrank(deployer);

        // Deploy
        HarvestVault vaultImpl = new HarvestVault();
        HarvestVaultFactory factory = new HarvestVaultFactory(address(vaultImpl));
        vault = factory.cloneVault();
        strategy = new HarvestStrategyMorpho();

        // Build swap paths
        bytes memory wldToWeth = abi.encodePacked(WLD, uint24(3000), WETH);
        bytes memory wethToUsdc = abi.encodePacked(WETH, uint24(500), USDC_E);

        address[] memory rewards = new address[](1);
        rewards[0] = WLD;
        bytes[] memory paths = new bytes[](1);
        paths[0] = wldToWeth;

        // Initialize strategy
        strategy.initialize(
            address(vault), USDC_E, WETH, MORPHO_RE7_USDC,
            MERKL_DISTRIBUTOR, keeper, deployer, deployer,
            false, rewards, paths
        );
        strategy.setSwapPath(WETH, wethToUsdc);
        strategy.setRewardMinAmount(WLD, 1e17);
        strategy.setRewardMinAmount(WETH, 1e14);
        strategy.setRewardMinAmount(USDC_E, 1e5);

        // Initialize vault
        vault.initialize(
            strategy, "Harvest USDC", "harvestUSDC", 0
        );

        // Verify alice and bob via World ID (off-chain sim)
        vault.setVerified(alice, true);
        vault.setVerified(bob, true);
        // unverifiedUser is NOT verified

        vm.stopPrank();

        // Fund test users with USDC.e (deal cheatcode)
        deal(USDC_E, alice, 10_000e6);   // 10,000 USDC
        deal(USDC_E, bob, 5_000e6);      // 5,000 USDC
    }
```

### Core Test Cases

```solidity
    // ================================================================
    // TEST 1: Deposit gives correct shares (via Permit2)
    // ================================================================
    function test_depositMintsCorrectShares() public {
        uint256 depositAmount = 1000e6; // 1000 USDC

        vm.startPrank(alice);
        _permit2ApproveAndDeposit(alice, depositAmount);
        vm.stopPrank();

        // First depositor: shares == amount (1:1)
        assertEq(vault.balanceOf(alice), depositAmount, "shares != deposit");
        assertEq(vault.getPricePerFullShare(), 1e18, "ppfs != 1e18");
        assertGt(vault.balance(), 0, "vault balance == 0");
    }

    // ================================================================
    // TEST 2: Two users deposit, shares proportional
    // ================================================================
    function test_proportionalShares() public {
        // Alice deposits 1000
        vm.startPrank(alice);
        _permit2ApproveAndDeposit(alice, 1000e6);
        vm.stopPrank();

        // Bob deposits 500
        vm.startPrank(bob);
        _permit2ApproveAndDeposit(bob, 500e6);
        vm.stopPrank();

        // Alice has 2x Bob's shares
        assertEq(vault.balanceOf(alice), 2 * vault.balanceOf(bob), "!proportional");
    }

    // ================================================================
    // TEST 3: Withdraw returns correct amount
    // ================================================================
    function test_withdrawReturnsCorrectAmount() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        _permit2ApproveAndDeposit(alice, depositAmount);

        uint256 shares = vault.balanceOf(alice);
        uint256 balBefore = IERC20(USDC_E).balanceOf(alice);
        vault.withdraw(shares);
        uint256 balAfter = IERC20(USDC_E).balanceOf(alice);
        vm.stopPrank();

        // Should get back approximately the deposit amount
        // (tiny rounding loss possible due to Morpho share math)
        assertApproxEqAbs(
            balAfter - balBefore,
            depositAmount,
            10, // 10 wei tolerance for rounding
            "withdraw amount wrong"
        );
        assertEq(vault.balanceOf(alice), 0, "shares not burned");
    }

    // ================================================================
    // TEST 4: Harvest increases share price (totalAssets)
    // ================================================================
    function test_harvestIncreasesSharePrice() public {
        // Alice deposits
        vm.startPrank(alice);
        _permit2ApproveAndDeposit(alice, 1000e6);
        vm.stopPrank();

        uint256 ppfsBefore = vault.getPricePerFullShare();

        // Simulate WLD rewards arriving at the strategy
        // (In reality, this happens via Merkl claim)
        deal(WLD, address(strategy), 100e18); // 100 WLD

        // Harvest
        vm.prank(keeper);
        strategy.harvest();

        // Wait for lock duration to expire
        vm.warp(block.timestamp + 1 days + 1);

        uint256 ppfsAfter = vault.getPricePerFullShare();

        assertGt(ppfsAfter, ppfsBefore, "ppfs did not increase after harvest");
    }

    // ================================================================
    // TEST 5: World ID gate blocks unverified user
    // ================================================================
    function test_worldIdGateBlocksUnverified() public {
        deal(USDC_E, unverifiedUser, 1000e6);

        vm.startPrank(unverifiedUser);
        // Even with Permit2 approval, unverified user cannot deposit
        IERC20(USDC_E).approve(address(PERMIT2), 1000e6);
        PERMIT2.approve(USDC_E, address(vault), uint160(1000e6), uint48(block.timestamp + 3600));

        vm.expectRevert("Harvest: humans only");
        vault.deposit(1000e6);
        vm.stopPrank();
    }

    // ================================================================
    // TEST 6: World ID gate allows verified user
    // ================================================================
    function test_worldIdGateAllowsVerified() public {
        vm.startPrank(alice); // alice is verified in setUp
        _permit2ApproveAndDeposit(alice, 100e6); // should not revert
        vm.stopPrank();

        assertGt(vault.balanceOf(alice), 0, "deposit failed for verified user");
    }

    // ================================================================
    // TEST 7: Harvest with zero rewards is a no-op
    // ================================================================
    function test_harvestWithZeroRewardsIsNoop() public {
        // Alice deposits
        vm.startPrank(alice);
        _permit2ApproveAndDeposit(alice, 1000e6);
        vm.stopPrank();

        uint256 ppfsBefore = vault.getPricePerFullShare();

        // Harvest with no rewards (no WLD in strategy)
        vm.prank(keeper);
        strategy.harvest(); // Should not revert

        uint256 ppfsAfter = vault.getPricePerFullShare();
        assertEq(ppfsAfter, ppfsBefore, "ppfs changed on empty harvest");
    }

    // ================================================================
    // TEST 8: Funds flow to Morpho vault (earn)
    // ================================================================
    function test_fundsFlowToMorpho() public {
        vm.startPrank(alice);
        _permit2ApproveAndDeposit(alice, 1000e6);
        vm.stopPrank();

        // After deposit, funds should be in Morpho (via earn -> strategy.deposit)
        assertGt(strategy.balanceOfPool(), 0, "no funds in Morpho");
        // Vault idle should be 0 (everything pushed to strategy)
        assertEq(vault.available(), 0, "vault has idle funds");
    }

    // ================================================================
    // TEST 9: Merkl claim integration
    // ================================================================
    function test_merklClaimAcceptsCorrectInterface() public {
        // This test verifies the claim() function compiles and
        // does not revert with empty arrays (no-op claim)
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        bytes32[][] memory proofs = new bytes32[][](0);

        // Should not revert (empty claim is a no-op)
        strategy.claim(tokens, amounts, proofs);
    }

    // ================================================================
    // TEST 10: Only vault can call strategy.withdraw
    // ================================================================
    function test_onlyVaultCanWithdraw() public {
        vm.expectRevert(); // NotVault error
        vm.prank(alice);
        strategy.withdraw(100e6);
    }

    // ================================================================
    // TEST 11: Panic withdraws everything from Morpho
    // ================================================================
    function test_panicWithdrawsAll() public {
        // Deposit
        vm.startPrank(alice);
        _permit2ApproveAndDeposit(alice, 1000e6);
        vm.stopPrank();

        uint256 morphoBefore = strategy.balanceOfPool();
        assertGt(morphoBefore, 0, "nothing in Morpho");

        // Panic
        vm.prank(deployer);
        strategy.panic();

        assertEq(strategy.balanceOfPool(), 0, "Morpho not empty after panic");
        assertTrue(strategy.paused(), "not paused after panic");
    }

    // ================================================================
    // TEST 12: setVerified only callable by owner
    // ================================================================
    function test_setVerifiedOnlyByOwner() public {
        vm.expectRevert(); // OwnableUnauthorizedAccount error
        vm.prank(alice);
        vault.setVerified(unverifiedUser, true);
    }

    // ================================================================
    // TEST 13: Agent deposit path (simulate AgentKit verification)
    // ================================================================
    function test_agentDepositAfterVerification() public {
        address agent = address(0xA6E47);
        deal(USDC_E, agent, 1000e6);

        // Before verification: deposit should revert even with Permit2 approval
        vm.startPrank(agent);
        IERC20(USDC_E).approve(address(PERMIT2), 1000e6);
        PERMIT2.approve(USDC_E, address(vault), uint160(500e6), uint48(block.timestamp + 3600));
        vm.expectRevert("Harvest: humans only");
        vault.deposit(500e6);
        vm.stopPrank();

        // Owner verifies agent (simulates backend calling setVerified after AgentKit check)
        vm.prank(deployer);
        vault.setVerified(agent, true);

        // After verification: deposit should succeed
        vm.startPrank(agent);
        // Permit2 approval was already set above, deposit directly
        vault.deposit(500e6);
        vm.stopPrank();

        assertGt(vault.balanceOf(agent), 0, "agent deposit failed after verification");
    }
}
```

### Gas Estimates

| Operation | Estimated Gas | Notes |
|-----------|--------------|-------|
| `deposit(uint256)` | ~180,000 - 250,000 | Includes earn() -> strategy.deposit() -> morphoVault.mint() |
| `withdraw(uint256)` | ~150,000 - 200,000 | Burns shares, pulls from Morpho |
| `strategy.claim()` | ~80,000 - 150,000 | Depends on number of tokens/proofs |
| `strategy.harvest()` | ~300,000 - 500,000 | Skim + swap + redeposit. Higher with more reward tokens. |
| `setVerified()` | ~46,000 | SSTORE for mapping update |
| `getPricePerFullShare()` | ~30,000 | View call, no state change |

**Gas costs at World Chain gas prices (~0.001 gwei):** All operations cost < $0.01 in gas. Gas is effectively free on World Chain for our purposes.

### Running Tests

```bash
# Run all fork tests
WORLD_CHAIN_RPC=https://worldchain-mainnet.g.alchemy.com/v2/$ALCHEMY_KEY \
  forge test --match-contract HarvestForkTest -vvv

# Run a specific test
WORLD_CHAIN_RPC=https://worldchain-mainnet.g.alchemy.com/v2/$ALCHEMY_KEY \
  forge test --match-test test_harvestIncreasesSharePrice -vvvv

# Gas report
WORLD_CHAIN_RPC=https://worldchain-mainnet.g.alchemy.com/v2/$ALCHEMY_KEY \
  forge test --match-contract HarvestForkTest --gas-report
```

---

## Part 5: Security Considerations

### 5.1 Reentrancy Risks in the Harvest Flow

**Risk Level: LOW**

| Entry Point | Reentrancy Guard? | External Calls | Risk |
|-------------|-------------------|----------------|------|
| `vault.deposit()` | Yes (`nonReentrant`) | `strategy.beforeDeposit()`, `PERMIT2.transferFrom()`, `strategy.deposit()` | Protected |
| `vault.withdraw()` | No (original Beefy has no guard) | `strategy.withdraw()`, `want.safeTransfer()` | **Medium** -- add `nonReentrant` |
| `strategy.harvest()` | No explicit guard | `morphoVault.redeem()`, Uniswap swap, `morphoVault.mint()` | Low -- all external calls are to trusted protocols |
| `strategy.claim()` | No guard | `claimer.claim()` (Merkl) | Low -- Merkl is a trusted contract |

**Recommendation:** Add `nonReentrant` to `vault.withdraw()`. The original Beefy code does not have it, but it is a cheap safety measure.

```solidity
// MODIFY in HarvestVault.sol:
function withdraw(uint256 _shares) public nonReentrant {  // ADD nonReentrant
    // ... existing logic
}
```

**Detailed harvest reentrancy analysis:**

The harvest flow makes external calls to:
1. `morphoVault.redeem()` -- Morpho is a trusted, audited protocol. No callback to our contract.
2. `IERC20.forceApprove()` + `SWAP_ROUTER.exactInput()` -- Uniswap V3 SwapRouter02 does not have callback mechanisms for `exactInput` (unlike `flash` or LP minting). Safe.
3. `morphoVault.mint()` -- Same as (1). No callback.

None of these can re-enter `harvest()` or `deposit()`. The risk is theoretical, not practical.

### 5.2 Slippage Protection on Swaps

**Risk Level: MEDIUM (hackathon) / HIGH (production)**

**Current state:** `amountOutMinimum = 0` in all swaps.

**Why this is acceptable for hackathon:**
- World Chain uses a sequencer with a private mempool
- No public mempool means no sandwich attack opportunity
- The agent is the only entity calling `harvest()`, so no competitive MEV
- Swap amounts are small (periodic harvest of reward tokens)

**Why this is NOT acceptable for production:**

Even without MEV, the swap could execute at a bad price due to:
- Low liquidity in the Uniswap pool
- Large reward accumulation before harvest (big swap moves price)
- Pool manipulation by a liquidity provider (not MEV, but price manipulation)

**Production fix:**

```solidity
// In _swap(), compute minimum output using an oracle:
uint256 expectedOut = _getExpectedOutput(_from, _to, _amount);
uint256 minOut = expectedOut * slippageBps / 10000; // e.g., 9900 = 1% max slippage

SWAP_ROUTER.exactInput(
    ISwapRouter02.ExactInputParams({
        path: path,
        recipient: address(this),
        amountIn: _amount,
        amountOutMinimum: minOut
    })
);
```

Or, more practically for the agent: compute `minAmountOut` off-chain using the QuoterV2, then pass it to a modified `harvest()` that accepts a `minAmountOut` parameter.

### 5.3 Empty Harvest (No Merkl Rewards to Claim)

**Risk Level: NONE**

What happens:
1. `strategy.claim()` is called separately. If there are no rewards, the Merkl distributor call is a no-op (or reverts -- the agent should check before calling).
2. `strategy.harvest()` is called. `_skimMorphoYield()` may skim a tiny amount of Morpho yield. `_swapRewardsToNative()` finds zero reward balances, does nothing. 
3. The `nativeBal > minAmounts[native]` check fails. The function returns early without emitting `StratHarvest`.
4. No state corruption, no revert (unless `minAmounts` thresholds are set correctly).

**Agent should handle this:**

```typescript
// In agent, check before calling:
const rewards = await fetchMerklRewards(strategyAddress);
if (rewards.totalUsdValue < MIN_HARVEST_THRESHOLD) {
  console.log("Rewards below threshold, skipping harvest");
  return;
}
```

### 5.4 Morpho Vault Paused

**Risk Level: LOW**

If the MetaMorpho vault is paused:
- `deposit()` on Morpho will revert -> `vault.deposit()` reverts -> user cannot deposit
- `withdraw()` on Morpho might revert (depends on MetaMorpho's pause implementation)
- `harvest()` will fail at the redeposit step

**Mitigation:**

1. The strategy has `panic()` which withdraws everything from Morpho and pauses the strategy
2. If Morpho pauses deposits but allows withdrawals, users can still withdraw from our vault (strategy pulls from Morpho)
3. If Morpho pauses everything, the owner calls `strategy.panic()` which:
   - Calls `_emergencyWithdraw()` (attempts full Morpho redemption)
   - Pauses the strategy
   - Users can withdraw idle want from the vault

**Edge case:** If Morpho pauses withdrawals, there is no mitigation. The funds are locked in Morpho until they unpause. This is an inherent risk of any yield protocol that deposits into Morpho. Document this for users.

### 5.5 Agent Key Compromise -- Blast Radius

**Risk Level: MEDIUM**

**What the agent (keeper) can do:**
- Call `harvest()` -- compounds yield. No theft vector.
- Call `claim()` -- claims Merkl rewards to the strategy contract. No theft vector (rewards go to strategy, not keeper).
- Call `pause()` / `unpause()` -- can DOS the protocol by pausing
- Call `panic()` -- can trigger emergency withdrawal (funds go to vault, not keeper)
- Modify `minAmounts` -- can set thresholds to prevent harvesting (DOS)
- Add/remove rewards -- can add a malicious "reward" token, but `_swap()` requires a swap path to be set by manager, and the swap sends output to the strategy, not the attacker

**What the agent CANNOT do:**
- Withdraw user funds (only vault can call `strategy.withdraw()`)
- Transfer tokens out of the strategy (no arbitrary transfer function)
- Change the vault address (no `setVault()` -- removed)
- Upgrade the strategy (no proxy upgrade function)
- Steal deposited funds in any way

**Blast radius of compromised keeper key:**
- **Worst case: DOS.** Attacker pauses the strategy. Owner can unpause.
- **No fund theft possible.** The keeper role cannot extract user funds.
- **Recovery:** Owner (deployer) calls `strategy.setKeeper(newKeeper)` and `strategy.unpause()`.

**Blast radius of compromised deployer (owner) key:**
- **Full control.** Owner can call `setStrategy()` to a malicious strategy that steals funds.
- **Mitigation for production:** Use a multisig (Safe) as owner. For hackathon, accept the risk.

### 5.5.1 setVerified() Owner Compromise

**Risk Level: MEDIUM**

`setVerified()` is `onlyOwner` -- if the owner key is compromised, the attacker can whitelist any address, bypassing the entire "DeFi, for humans" guarantee.

**What the attacker can do:**
- Call `vault.setVerified(attackerAddress, true)` to whitelist arbitrary wallets
- Deposit into the vault from those wallets (sybil farming)
- Cannot steal existing deposits (deposits belong to individual share holders)

**Mitigations:**
- **Hackathon:** Owner is the deployer EOA. Accept the risk. The deployer key is held by the team.
- **Production:** Transfer ownership to a multisig (Safe). Require 2-of-3 signatures to call `setVerified()`.
- **Future improvement:** Move verification on-chain (verify World ID proofs in the contract directly, read AgentBook state directly) to eliminate the trusted signer entirely.

### 5.5.2 World ID Nullifier Prevents Multi-Wallet Sybil

The `onlyHuman` modifier doesn't prevent a verified human from depositing via multiple wallets IF they somehow get multiple wallets verified. However, World ID's nullifier hash prevents this:

- Each World ID verification action produces a unique nullifier per human per action
- The backend tracks nullifiers: one human = one `setVerified()` call = one verified wallet
- If a human tries to verify a second wallet, the backend detects the duplicate nullifier and rejects

### 5.5.3 AgentBook Multi-Wallet Behavior

AgentBook maps agent wallets to anonymous human IDs. One human CAN register multiple agent wallets, but:

- All agent wallets map to the same anonymous human ID
- The vault doesn't need to care about this -- the human behind the agents is still unique
- Multiple agent wallets for one human does not constitute sybil farming (same human, same capital)
- The real protection is economic: one human's capital is finite regardless of how many wallets they use

### 5.6 Additional Security Notes

**Integer overflow/underflow:**
- Solidity 0.8.x has built-in overflow checks. Not a concern.

**Front-running deposits before harvest:**
- An attacker could deposit right before a harvest to capture yield they did not earn.
- The `lockedProfit()` mechanism mitigates this: harvested yield is released linearly over `lockDuration` (1 day), preventing flash-deposit attacks.
- `harvestOnDeposit` mode (if enabled) forces a harvest before any deposit, eliminating this vector entirely.

**Share inflation attack (ERC-4626 first-depositor attack):**
- If the vault is empty and an attacker deposits 1 wei, then donates a large amount directly to the strategy, the next depositor gets 0 shares.
- Beefy's vault uses `shares = _amount` for the first deposit (not `_amount * totalSupply / totalAssets`), which means the first depositor's shares are always exactly their deposit amount.
- **Mitigation:** Deploy and immediately deposit a small "seed" amount (e.g., 1 USDC) from the deployer. This prevents the first-depositor attack.

```solidity
// In deployment script, after vault initialization (MANDATORY):
IPermit2(PERMIT2).approve(USDC_E, address(vault), uint160(1e6), uint48(block.timestamp + 3600));
vault.deposit(1e6); // Seed deposit to prevent first-depositor attack
```

**Oracle manipulation:**
- We do not use oracles. Swap prices come from Uniswap V3 pool state.
- With `amountOutMinimum = 0`, a manipulated pool could cause bad swaps.
- Acceptable for hackathon. Production fix: Chainlink oracle + slippage check.

---

<!-- Interface verified against Permit2 source at lib/permit2/src/AllowanceTransfer.sol
     and lib/permit2/src/interfaces/IAllowanceTransfer.sol on 2026-04-03.
     - approve(): line 26 of AllowanceTransfer.sol
     - transferFrom(): line 59 of AllowanceTransfer.sol
     - allowance(): line 111 of IAllowanceTransfer.sol
     Signature-based PermitTransferFrom is NOT used and NOT included. -->
## Appendix A: Complete Interface Definitions

### IPermit2.sol (Allowance-Based Only)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Minimal subset of Permit2 used by HarvestVault (allowance-based only).
/// @dev The canonical Permit2 extends both ISignatureTransfer and IAllowanceTransfer.
///      We only use the allowance-based functions. No signature-based flow.
///      All signatures verified against lib/permit2/src/AllowanceTransfer.sol.
interface IPermit2 {
    /// @notice Approve a spender to use up to `amount` of the specified token until `expiration`
    /// @dev Called by the user in MiniKit multicall step 1 to authorize the vault.
    ///      Signature: AllowanceTransfer.sol line 26.
    /// @param token The ERC-20 token to approve
    /// @param spender The address to approve (our vault)
    /// @param amount The maximum amount the spender can transfer (uint160, not uint256)
    /// @param expiration Timestamp after which the approval expires
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    /// @notice Transfer tokens from `from` to `to` using stored Permit2 allowance
    /// @dev Called by the vault inside deposit(). Requires prior approve() from the user.
    ///      Signature: AllowanceTransfer.sol line 59.
    /// @param from The token owner (msg.sender of the MiniKit transaction)
    /// @param to The recipient (the vault)
    /// @param amount The amount to transfer (uint160, not uint256)
    /// @param token The ERC-20 token to transfer
    function transferFrom(address from, address to, uint160 amount, address token) external;

    /// @notice Read the current allowance for a (user, token, spender) triple
    /// @dev Useful for checking if the user has already approved the vault.
    ///      Signature: IAllowanceTransfer.sol line 111.
    /// @param user The token owner
    /// @param token The ERC-20 token
    /// @param spender The approved spender
    /// @return amount The remaining approved amount
    /// @return expiration The timestamp when the approval expires
    /// @return nonce The current nonce (incremented on signature-based permits)
    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce);
}
```

**ISignatureTransfer.sol is NOT needed.** The vault does not use signature-based Permit2 flows. Do not create this file.

<!-- Interface verified: SwapRouter02 ExactInputParams correctly omits `deadline` field
     (removed in SwapRouter02 vs original SwapRouter). Packed path encoding
     (abi.encodePacked(address, uint24, address, ...)) is standard Uniswap V3 format. -->
### ISwapRouter02.sol (Uniswap V3 SwapRouter02)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISwapRouter02 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
```

<!-- Interface verified: Merkl Distributor claim() signature matches the Angle/Merkl
     Distributor at 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae. The `amounts` parameter
     contains cumulative (lifetime) claimable amounts, not incremental amounts. -->
### IMerklClaimer.sol (Merkl Distributor)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMerklClaimer {
    /// @notice Claim accumulated rewards from Merkl distributor
    /// @param users Array of user addresses (strategy address)
    /// @param tokens Array of reward token addresses
    /// @param amounts Array of cumulative claimable amounts (NOT incremental)
    /// @param proofs Array of Merkle proofs per token
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
```

### IStrategyV7.sol (Vault-Strategy Interface)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategyV7 {
    function vault() external view returns (address);
    function want() external view returns (address);
    function beforeDeposit() external;
    function deposit() external;
    function withdraw(uint256) external;
    function balanceOf() external view returns (uint256);
    function balanceOfWant() external view returns (uint256);
    function balanceOfPool() external view returns (uint256);
    function harvest() external;
    function retireStrat() external;
    function panic() external;
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
```

---

## Appendix B: Contract Address Registry

### World Chain Mainnet (Chain ID: 480)

| Contract | Address | Source |
|----------|---------|--------|
| USDC.e (Bridged USDC) | `0x79A02482A880bCE3F13e09Da970dC34db4CD24d1` | Bridged |
| WLD Token | `0x2cFc85d8E48F8EAB294be644d9E25C3030863003` | Native |
| WETH | `0x4200000000000000000000000000000000000006` | OP Stack |
| MORPHO Token | `0xe2108e43dBD43c9Dc6E494F86c4C4D938Bd10f56` | Bridged |
| Morpho Blue (core) | `0xe741bc7c34758b4cae05062794e8ae24978af432` | Deployed |
| Morpho Re7 USDC Vault | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` | MetaMorpho |
| Merkl Distributor | `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae` | Angle |
| Uniswap V3 SwapRouter02 | `0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6` | Uniswap |
| Uniswap V3 QuoterV2 | `0x10158D43e6cc414deE1Bd1eB0EfC6a5cBCfF244c` | Uniswap |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | Uniswap |

### Harvest Contracts (to be filled after deployment)

| Contract | Address | Tx Hash |
|----------|---------|---------|
| HarvestVault Implementation | `TBD` | |
| HarvestVaultFactory | `TBD` | |
| HarvestVault (USDC clone) | `TBD` | |
| HarvestStrategyMorpho | `TBD` | |

### Swap Paths (Packed Bytes)

| Route | Packed Path |
|-------|-------------|
| WLD -> WETH | `0x2cFc85d8E48F8EAB294be644d9E25C3030863003 000bb8 4200000000000000000000000000000000000006` |
| WETH -> USDC.e | `0x4200000000000000000000000000000000000006 0001f4 79A02482A880bCE3F13e09Da970dC34db4CD24d1` |
| MORPHO -> WETH | `0xe2108e43dBD43c9Dc6E494F86c4C4D938Bd10f56 000bb8 4200000000000000000000000000000000000006` |

Fee tiers: `0x000bb8` = 3000 (0.3%), `0x0001f4` = 500 (0.05%)

---

## Appendix C: File Manifest

Final files to create:

```
contracts/
  foundry.toml                      # Foundry configuration (see below)
  remappings.txt                    # Import path remappings (see below)
  src/
    vaults/
      HarvestVault.sol              # Modified BeefyVaultV7 (Permit2 allowance + World ID)
      HarvestVaultFactory.sol       # BeefyVaultV7Factory (as-is, renamed)
    strategies/
      HarvestStrategyMorpho.sol     # Flattened StrategyMorpho + BaseAllToNative
    interfaces/
      IStrategyV7.sol               # Vault-strategy interface
      IMerklClaimer.sol             # Merkl distributor interface
      ISwapRouter02.sol             # Uniswap V3 swap router
      IPermit2.sol                  # Permit2 allowance-based interface (no signature types)
  script/
    Deploy.s.sol                    # Foundry deployment script
  test/
    HarvestFork.t.sol               # Fork tests against World Chain mainnet
  lib/
    permit2/                        # git submodule: github.com/Uniswap/permit2
    openzeppelin-contracts/         # git submodule: github.com/OpenZeppelin/openzeppelin-contracts
    forge-std/                      # git submodule: github.com/foundry-rs/forge-std
```

**Note:** `ISignatureTransfer.sol` is NOT included. We use allowance-based Permit2 only.

Total new Solidity files: 9 (3 source + 4 interfaces + 1 script + 1 test)
Estimated total lines: ~800 (contracts) + ~300 (tests) + ~150 (script)

---

## Appendix D: foundry.toml

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.28"
optimizer = true
optimizer_runs = 200
evm_version = "paris"

[rpc_endpoints]
worldchain = "${WORLD_CHAIN_RPC_URL}"
```

---

## Appendix E: remappings.txt

```
@permit2/=lib/permit2/src/
@openzeppelin/=lib/openzeppelin-contracts/
forge-std/=lib/forge-std/src/
```
