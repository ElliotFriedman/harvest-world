# Harvest World — Certora Formal Verification

This directory contains formal verification specs for the Harvest World smart contracts using the [Certora Prover](https://www.certora.com/). Specs are written in CVL2 (Certora Verification Language, version 2).

---

## What Is Formal Verification?

Formal verification uses mathematical proof to check that a smart contract satisfies a specification — for every possible input, in every possible state. Unlike fuzzing or unit testing, which can only find bugs in the cases they happen to test, formal verification proves (or disproves) correctness exhaustively.

For DeFi protocols, formal verification is especially valuable because:

- **Assets are at stake.** A single logic bug can drain millions of dollars.
- **State spaces are large.** Contracts interact across token pairs, user accounts, and time, making it impractical to test every combination manually.
- **Invariants are load-bearing.** Properties like "shares always have backing" or "slippage is always applied" must hold for every transaction, not just the ones developers thought to test.

The Certora Prover models EVM bytecode symbolically, treating function inputs and storage as mathematical variables rather than concrete values. Rules written in CVL2 assert properties that the Prover attempts to falsify; if it cannot find a counterexample, the property is proven.

---

## Contracts Under Verification

| Contract | Source File | Harness |
|---|---|---|
| `BeefyVaultV7` | `src/BeefyVaultV7.sol` | `certora/harness/BeefyVaultV7Harness.sol` |
| `BaseAllToNativeFactoryStrat` | `src/BaseAllToNativeFactoryStrat.sol` | `certora/harness/StrategyMorphoMerklHarness.sol` |
| `StrategyMorphoMerkl` | `src/StrategyMorphoMerkl.sol` | `certora/harness/StrategyMorphoMerklHarness.sol` |
| `BeefySwapper` | `src/BeefySwapper.sol` | `certora/harness/BeefySwapperHarness.sol` |

---

## Verified Properties Summary

### BeefyVaultV7 (`certora/specs/BeefyVaultV7.spec`)

| ID | Name | Category | Description |
|---|---|---|---|
| I-1 | `totalSupplyZeroIffBalanceZero` | Invariant | Shares exist iff assets exist — prevents minting shares from nothing |
| I-2 | `availableNeverExceedsBalance` | Invariant | Vault's idle balance is always a subset of total balance |
| I-3 | `balanceNeverNegative` | Invariant | Total balance is non-negative by construction |
| R-1 | `depositMintsCorrectShares` | Share arithmetic | Minted shares are proportional to deposit amount and existing supply |
| R-2 | `withdrawReturnsCorrectTokens` | Share arithmetic | Redeemed tokens are proportional to burned shares |
| R-3 | `depositWithdrawRoundTrip` | Round-trip safety | Deposit then immediate withdraw never returns more than deposited |
| R-4 | `onlyOwnerCanSetStrategy` | Access control | `setStrategy()` reverts for non-owner callers |
| R-5 | `ownerCanSetStrategy` | Access control | Owner can successfully change the strategy |
| R-6 | `inCaseTokensGetStuckOnlyOwner` | Access control | Token rescue function restricted to owner |
| R-7 | `earnZerosAvailable` | Earn flow | After `earn()`, vault holds no idle tokens |
| R-8 | `pricePerSharePositiveWhenSupplyPositive` | Price integrity | Price-per-share is positive whenever supply is positive |
| R-9 | `pricePerShareNonDecreasingAfterYield` | Price integrity | Yield accrual cannot decrease share price |
| R-10 | `withdrawAllBurnsAllShares` | Share arithmetic | `withdrawAll()` burns all caller shares |
| R-11 | `depositAllDepositsEntireBalance` | Deposit flow | `depositAll()` consumes entire caller balance |
| R-12 | `noSharesFromZeroDeposit` | Share arithmetic | Depositing 0 tokens mints 0 shares |
| R-13 | `balanceEqualsComponentSum` | Accounting identity | `balance()` always equals vault balance + strategy balance |
| R-14 | `strategyBalanceContributes` | Accounting identity | `balance()` is always >= the vault's own token holdings |
| R-15 | `setStrategyUpdatesStorage` | Storage integrity | `setStrategy()` updates the stored strategy address |
| R-16 | `getPricePerFullShareReturnsSentinelWhenEmpty` | Price integrity | `getPricePerFullShare()` returns `1e18` when no shares exist |
| R-17 | `withdrawDoesNotAffectOtherDepositors` | Isolation | One user's withdrawal cannot change another user's share balance |

---

### BaseAllToNativeFactoryStrat (`certora/specs/BaseStrategy.spec`)

| ID | Name | Category | Description |
|---|---|---|---|
| I-1 | `lockedProfitNonNegative` | Invariant | `lockedProfit()` is always >= 0 |
| I-2 | `lockedProfitNeverExceedsTotalLocked` | Invariant | Decayed profit never exceeds the cap set at harvest time |
| I-3 | `lastHarvestNotInFuture` | Invariant | `lastHarvest` timestamp is never in the future |
| R-1 | `lockedProfitDecaysToZero` | Locked profit | After one full `lockDuration`, locked profit is 0 |
| R-2 | `lockedProfitNonIncreasing` | Locked profit | Profit only shrinks as time passes (no spontaneous increase) |
| R-3 | `balanceOfCorrect` | Accounting | `balanceOf()` = want balance + pool balance - locked profit |
| R-4 | `onlyVaultCanWithdraw` | Access control | `withdraw()` reverts for non-vault callers |
| R-5 | `onlyVaultCanRetire` | Access control | `retireStrat()` reverts for non-vault callers |
| R-6 | `onlyManagerCanAddReward` | Access control | `addReward()` reverts for non-manager callers |
| R-7 | `onlyManagerCanSetHarvestOnDeposit` | Access control | `setHarvestOnDeposit()` reverts for non-manager callers |
| R-8 | `onlyManagerCanSetLockDuration` | Access control | `setLockDuration()` reverts for non-manager callers |
| R-9 | `onlyManagerCanClaim` | Access control | `claim()` reverts for non-manager callers |
| R-10 | `onlyManagerCanPause` | Access control | `pause()` reverts for non-manager callers |
| R-11 | `onlyManagerCanUnpause` | Access control | `unpause()` reverts for non-manager callers |
| R-12 | `onlyManagerCanPanic` | Access control | `panic()` reverts for non-manager callers |
| R-13 | `pausedPreventsDeposit` | Pause effects | `deposit()` reverts when contract is paused |
| R-14 | `panicPausesContract` | Pause effects | `panic()` results in `paused() == true` |
| R-15 | `panicWithdrawsAll` | Pause effects | `panic()` drains the Morpho pool to 0 |
| R-16 | `harvestUpdatesLastHarvest` | Harvest | `lastHarvest` is set to `block.timestamp` after harvest |

---

### StrategyMorphoMerkl (`certora/specs/StrategyMorphoMerkl.spec`)

| ID | Name | Category | Description |
|---|---|---|---|
| I-1 | `morphoPoolNonNegative` | Invariant | `balanceOfPool()` is always >= 0 |
| I-2 | `sharesImplyAssets` | Invariant | Morpho shares > 0 implies pool balance > 0 |
| R-1 | `balanceOfPoolMatchesMorpho` | Morpho accounting | Pool balance equals `morphoVault.convertToAssets(sharesHeld)` |
| R-2 | `depositIncreasesPool` | Morpho accounting | Internal `_deposit` never decreases the pool balance |
| R-3 | `withdrawDecreasesPool` | Morpho accounting | Internal `_withdraw` never increases the pool balance |
| R-4 | `emergencyWithdrawEmptiesPool` | Morpho accounting | `_emergencyWithdraw` redeems all Morpho shares |
| R-5 | `depositTransfersWantToMorpho` | Atomicity | After deposit, want tokens move from strategy to Morpho |
| R-6 | `withdrawReturnsWantToStrategy` | Atomicity | After withdraw, strategy's want balance increases |
| R-7 | `publicClaimCallsClaimer` | Merkl integration | Public `claim()` invokes the claimer contract |
| R-8 | `setClaimerUpdatesStorage` | Storage integrity | `setClaimer()` updates the stored claimer address |
| R-9 | `cannotAddMorphoVaultAsReward` | Reward safety | Morpho vault shares cannot be added as a reward token |
| R-10 | `cannotAddWantAsReward` | Reward safety | Want token cannot be added as a regular reward token |
| R-11 | `cannotAddNativeAsReward` | Reward safety | Native (WETH) cannot be added as a reward token |

---

### BeefySwapper (`certora/specs/BeefySwapper.spec`)

| ID | Name | Category | Description |
|---|---|---|---|
| I-1 | `slippageNeverExceedsDivisor` | Invariant | `slippage` storage variable is always <= `1e18` in every reachable state |
| R-1 | `swapRevertsIfNoSwapData` | Swap safety | `swap()` reverts when no route is configured for a token pair |
| R-2 | `slippageAlwaysApplied` | Swap safety | `swap()` reverts when oracle-adjusted output would fall below minimum |
| R-3 | `swapDoesNotChangeCallerBalanceOnRevert` | Swap safety | A reverted swap leaves the caller's fromToken balance unchanged |
| R-4 | `slippageMax100Percent` | Slippage config | `setSlippage(> 1e18)` clamps stored slippage to exactly `1e18` |
| R-5 | `setSlippageUpdatesStorage` | Slippage config | `setSlippage(val)` stores `val` when `val <= 1e18` |
| R-6 | `slippageZeroAllowed` | Slippage config | `setSlippage(0)` succeeds and stores 0 |
| R-7 | `onlyOwnerCanSetOracle` | Access control | `setOracle()` reverts for non-owner callers |
| R-8 | `setOracleUpdatesStorage` | Storage integrity | After `setOracle(addr)`, `getOracleAddr()` returns `addr` |
| R-9 | `onlyOwnerCanSetSwapInfo` | Access control | `setSwapInfo()` reverts for non-owner callers |
| R-10 | `setSwapInfoUpdatesStorage` | Storage integrity | After `setSwapInfo(a, b, info)`, `getSwapInfoRouter(a, b)` returns `info.router` |
| R-11 | `onlyOwnerCanSetSlippage` | Access control | `setSlippage()` reverts for non-owner callers |
| R-12 | `explicitSwapRevertsWhenOutputBelowMin` | Swap safety | Explicit-min swap reverts whenever final toToken balance < `minAmountOut` |
| R-13 | `setSwapInfoRouterZeroAllowed` | Swap info config | Zero-router `setSwapInfo()` succeeds — enables route deletion |
| R-14 | `setOracleToZeroAllowed` | Oracle config | `setOracle(0)` is not blocked (documents absence of zero-address check) |
| R-15 | `getAmountOutDoesNotChangeSlippage` | View purity | `getAmountOut()` does not modify the `slippage` storage variable |

---

## Harness Design Pattern

The Certora Prover verifies a single deployed contract. It cannot directly instrument or summarise internal calls to `private` functions or access `private` state variables. The harness pattern solves this:

1. **Harness inherits the real contract.** This means all production logic is verified — no reimplementation, no "for testing only" overrides of business logic.

2. **Harness adds view helpers.** Methods like `getSwapInfoRouter(from, to)` expose internal storage slots as external `view` functions that specs can call in `envfree` context (no environment needed, meaning they are stateless lookups).

3. **Harness overrides specific platform integrations.** For example, `BeefyVaultV7Harness` replaces the Permit2 `transferFrom` with a standard ERC-20 `transferFrom`. This lets the prover track token balances precisely without modelling the Permit2 singleton contract (which would require a full separate spec).

4. **Mock contracts provide concrete models.** `MockOracle`, `MockERC20Swappable`, `MockMorphoVault`, and `MockMerklClaimer` are concrete Solidity implementations linked to the harness via the `link` directive in the `.conf` file. The prover uses these to reason precisely about return values and state changes, rather than treating every external call as returning an arbitrary value.

5. **NONDET summaries for adversarial externals.** Contracts like the router (in `BeefySwapper`) are summarised as `NONDET` — the prover assumes they can do anything. This is the most conservative model: a property that holds against a NONDET external holds against any real implementation.

---

## Prerequisites

| Tool | Notes |
|---|---|
| **Certora Prover license** | Request at [certora.com](https://www.certora.com/). Free licenses available for open-source and academic projects. |
| **`CERTORAKEY` env variable** | Set to your Certora API key: `export CERTORAKEY=<your_key>` |
| **`solc`** | Solidity compiler 0.8.28. Install via `svm` or `solc-select`: `solc-select install 0.8.28 && solc-select use 0.8.28` |
| **`certoraRun` CLI** | Install via pip: `pip install certora-cli` |
| **Foundry dependencies** | Run `forge install` in `contracts/` to materialise `lib/` submodules before verification. |

---

## Running Verification

Each `.conf` file specifies a single verification job. Run them individually with `certoraRun`:

```bash
# Vault share arithmetic, access control, round-trip safety
certoraRun certora/confs/BeefyVaultV7.conf

# Base strategy locked-profit decay, access control, pause safety
certoraRun certora/confs/BaseStrategy.conf

# Morpho + Merkl accounting, reward safety, pool monotonicity
certoraRun certora/confs/StrategyMorphoMerkl.conf

# Swapper slippage protection, access control, route integrity
certoraRun certora/confs/BeefySwapper.conf
```

Or run all jobs sequentially using the provided script:

```bash
bash certora/run_all.sh
```

Each job is submitted to the Certora cloud. The CLI will print a link to the verification report, e.g.:

```
Verification results: https://prover.certora.com/output/<job-id>/
```

### Interpreting Results

- **Green (VERIFIED):** The rule holds in all reachable states. No counterexample exists.
- **Red (VIOLATED):** The prover found a counterexample. The report shows the exact transaction sequence and state values that trigger the violation.
- **Yellow (SANITY FAILED):** `rule_sanity: basic` is enabled — rules that can never be satisfied (vacuously true due to unsatisfiable preconditions) are flagged. Investigate and tighten `require` statements.
- **Timeout:** The rule's state space was too large to fully explore within the time limit. Consider tightening preconditions or splitting the rule.

---

## Configuration Details

| Setting | Value | Rationale |
|---|---|---|
| `rule_sanity: basic` | enabled | Catches rules that pass vacuously — where preconditions are always false |
| `optimistic_loop: true` | enabled | Assumes loops terminate (no unbounded iteration proofs needed) |
| `loop_iter: 3` | 3 iterations | Unrolls loops up to 3 times; sufficient for array bounds used in these contracts |
| `multi_assert_check: true` | enabled | Each `assert` in a rule is checked independently for finer-grained counterexamples |
| `process: emv` | EMV | Uses the Ethereum model checker (most complete EVM model available) |
| `optimistic_fallback: true` | enabled in BeefySwapper | Treats the router's low-level `fallback()` call as succeeding (returns true), which is more realistic than always-reverting |
