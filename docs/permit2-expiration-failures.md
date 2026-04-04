# Permit2 Expiration Failures: A History

**Date:** 2026-04-04
**Status:** Unresolved -- searching for a value that satisfies both Permit2 on-chain logic and World's MiniKit simulation backend
**Affected file:** `app/src/app/page.tsx` (the `expiration` arg to `Permit2.approve()`)

---

## Background

MiniKit requires all ERC-20 token transfers to go through Permit2 (`0x000000000022D473030F116dDEE9F6B43aC78BA3`). Standard `approve()` calls are blocked. Our deposit flow bundles two calls atomically in a single MiniKit `sendTransaction` UserOp:

1. `Permit2.approve(USDC, vault, amount, expiration)` -- set allowance
2. `HarvestVault.deposit(amount)` -- vault calls `Permit2.transferFrom()` to pull USDC

The `expiration` parameter to `Permit2.approve()` is a `uint48` Unix timestamp. The problem: every value we have tried either fails Permit2's on-chain check or gets rejected by World's simulation backend before the transaction is ever submitted.

---

## The Contradiction

**Permit2 on-chain** requires that the expiration has not passed at the time `transferFrom()` executes. The check in `AllowanceTransfer.sol` line 79 is:

```solidity
if (block.timestamp > allowed.expiration) revert AllowanceExpired(allowed.expiration);
```

This is a **strict greater-than** (`>`), meaning `block.timestamp == expiration` does NOT revert.

When `expiration == 0` is passed to `approve()`, Permit2 treats it as a sentinel value and stores `block.timestamp` instead (see `Allowance.sol` line 24):

```solidity
uint48 storedExpiration = expiration == BLOCK_TIMESTAMP_EXPIRATION
    ? uint48(block.timestamp)
    : expiration;
```

So `expiration=0` means "valid only for this block." In theory, if `approve()` and `transferFrom()` execute in the same block (which they do in a bundled UserOp), the stored value is `block.timestamp` and the check `block.timestamp > block.timestamp` is `false`, so it should pass.

**World's MiniKit backend** simulates transactions before submitting them. This simulation rejects:
- `expiration = 0`: simulation fails (the simulation environment apparently evaluates the sentinel differently, or runs approve and transferFrom at different simulated timestamps)
- Any future timestamp (even `now + 15`): `permit_deadline_too_long` error
- Current timestamp (`now + 0`): still fails simulation

The result is a **no-win scenario**: the on-chain contract needs a non-expired timestamp, but the simulation backend rejects anything that is not effectively "right now" and also rejects "right now."

---

## Full Timeline of Attempts

### Attempt 1: `expiration = 0` (initial)

| Field | Value |
|-------|-------|
| **Commit** | `4418702` feat: functional mini app with deposit, withdraw, portfolio |
| **PR** | [#34](https://github.com/ElliotFriedman/harvest-world/pull/34) (merged 2026-04-03) |
| **Value** | `0` (hardcoded) |
| **Rationale** | World docs say to use 0 for atomic bundled txs. Permit2 treats 0 as sentinel for `block.timestamp`. |
| **Result** | **Simulation failure** -- MiniKit returns `simulation_failed` before the tx reaches chain. The simulation environment does not handle the `0` sentinel the same way as the on-chain EVM. |

### Attempt 2: `now + 86400` (24 hours)

| Field | Value |
|-------|-------|
| **Commit** | `c8afe92` fix: set Permit2 allowance expiration to 24h instead of 0 |
| **PR** | [#54](https://github.com/ElliotFriedman/harvest-world/pull/54) (merged 2026-04-04 04:08 UTC) |
| **Value** | `Math.floor(Date.now() / 1000) + 86400` |
| **Rationale** | Assumed 0 literally meant "already expired." 24h gives ample window. |
| **Result** | **`permit_deadline_too_long`** -- World's backend rejects expirations too far in the future. The 24h window was flagged as excessive. |

### Attempt 3: `expiration = 0` (reverted back)

| Field | Value |
|-------|-------|
| **Commit** | `a29b254` fix: revert Permit2 expiration to 0 per World docs |
| **PR** | [#56](https://github.com/ElliotFriedman/harvest-world/pull/56) (merged 2026-04-04 04:22 UTC) |
| **Value** | `0` |
| **Rationale** | World docs explicitly say expiration should be 0 for atomic bundled ops. Assumed the 24h rejection means they enforce 0. |
| **Result** | **Simulation failure again** -- same as attempt 1. The docs say 0 but the simulation rejects 0. |

### Attempt 4: `now + 60` (1 minute)

| Field | Value |
|-------|-------|
| **Commit** | `eef311a` fix(app): set Permit2 expiration to 1min future timestamp, bump v1.6 |
| **PR** | [#59](https://github.com/ElliotFriedman/harvest-world/pull/59) (merged 2026-04-04 04:35 UTC) |
| **Value** | `Math.floor(Date.now() / 1000) + 60` |
| **Rationale** | Try a small future window. Not too long to trigger deadline rejection, not zero. |
| **Result** | **`permit_deadline_too_long`** -- even 60 seconds is considered "too long" by the World backend. |

### Attempt 5: `now + 15` (15 seconds)

| Field | Value |
|-------|-------|
| **Commit** | `96727b8` fix(app): reduce Permit2 expiration to 15s, bump v1.7 |
| **PR** | [#60](https://github.com/ElliotFriedman/harvest-world/pull/60) (merged 2026-04-04 04:43 UTC) |
| **Value** | `Math.floor(Date.now() / 1000) + 15` |
| **Rationale** | Tighten the window further. 15s should be enough for bundler submission. |
| **Result** | **`permit_deadline_too_long`** -- World's backend still rejects it. The threshold appears to be very aggressive. |

### Attempt 6: `now + 0` (current timestamp, no padding)

| Field | Value |
|-------|-------|
| **Commit** | `6533101` fix(app): use current timestamp for Permit2 expiration, bump v1.8 |
| **PR** | [#62](https://github.com/ElliotFriedman/harvest-world/pull/62) (merged 2026-04-04 04:53 UTC) |
| **Value** | `Math.floor(Date.now() / 1000)` |
| **Rationale** | The strict `>` check means `block.timestamp == expiration` passes. Using current timestamp avoids "too long" rejection while still being non-zero. |
| **Result** | **Simulation failure** -- World's simulation apparently runs at a timestamp slightly in the future of the client's `Date.now()`, causing `block.timestamp > expiration` to be true in simulation. |

### Attempt 7: `now + 2` (2 seconds, current)

| Field | Value |
|-------|-------|
| **Commit** | `0407597` fix(app): set Permit2 expiration to now+2s, bump v1.9 |
| **Branch** | `fix/permit2-expiration-2s` (current HEAD) |
| **Value** | `Math.floor(Date.now() / 1000) + 2` |
| **Rationale** | Split the difference -- 2s padding might survive both the "too long" check and the simulation clock skew. |
| **Result** | **Pending** -- about to test. |

---

## Permit2 Source Code Analysis

The relevant code lives in `contracts/lib/permit2/src/libraries/Allowance.sol` and `contracts/lib/permit2/src/AllowanceTransfer.sol`.

### Allowance.sol (lines 7-30): The `0` sentinel

```solidity
// note if the expiration passed is 0, then it the approval set to the block.timestamp
uint256 private constant BLOCK_TIMESTAMP_EXPIRATION = 0;

function updateAll(..., uint48 expiration, ...) internal {
    uint48 storedExpiration = expiration == BLOCK_TIMESTAMP_EXPIRATION
        ? uint48(block.timestamp)
        : expiration;
    // ... pack and store
}
```

When you call `approve(..., 0)`, Permit2 does NOT store `0`. It stores `block.timestamp`. This is designed for single-block allowances.

### AllowanceTransfer.sol (line 79): The expiry check

```solidity
if (block.timestamp > allowed.expiration) revert AllowanceExpired(allowed.expiration);
```

The check is **strict greater-than** (`>`). This means:
- `block.timestamp == expiration`: PASSES (not expired)
- `block.timestamp > expiration`: REVERTS

So if `approve()` and `transferFrom()` execute in the same block (which they do in a UserOp bundle), `expiration = 0` should work because:
1. `approve()` stores `block.timestamp` (e.g., `1712233200`)
2. `transferFrom()` checks `1712233200 > 1712233200` which is `false`
3. Check passes, transfer succeeds

### Why it fails in simulation

World's MiniKit simulation environment does not behave identically to the on-chain EVM for this case. Possible explanations:

1. **Simulation runs calls at different simulated timestamps.** If the simulation engine advances `block.timestamp` between the `approve()` and `transferFrom()` calls within the same UserOp, the stored value from step 1 would be stale by step 2.

2. **Simulation uses `block.timestamp = 0` or some default.** If the simulation does not set a realistic `block.timestamp`, then `approve(..., 0)` stores `0`, and ANY nonzero simulated timestamp for `transferFrom()` would cause `0 > 0` ... no, that still passes. But if `block.timestamp` were `1` at transferFrom time, `1 > 0` reverts.

3. **Client-server clock skew.** For non-zero values like `now + 0`, the client's `Date.now()` may be a few seconds behind the simulation server's clock. If the server simulates at `client_now + 3`, then `client_now + 0` is already expired.

4. **The simulation rejects the expiration value itself before simulating.** World's backend may have a validation layer that checks `expiration` independently of Permit2's on-chain logic, applying its own rules about acceptable ranges.

Explanation 4 is the most consistent with the observed behavior: a pre-simulation validation that rejects `0` (because it looks like "no expiration" or "invalid") AND rejects anything more than a few seconds in the future (because "deadline too long"). This would mean the acceptable window is something like `now + 1` to `now + N` where N is very small and undocumented.

---

## Summary of the Constraint Space

```
Value              On-chain result         World simulation result
-----------------  ----------------------  --------------------------
0                  PASS (same-block)       FAIL: simulation_failed
now + 0            PASS (strict > check)   FAIL: simulation_failed
now + 2            PASS                    PENDING (attempt 7)
now + 15           PASS                    FAIL: permit_deadline_too_long
now + 60           PASS                    FAIL: permit_deadline_too_long
now + 86400        PASS                    FAIL: permit_deadline_too_long
```

The on-chain Permit2 contract would accept any of these values. The constraint is entirely from World's simulation/validation layer, which appears to enforce an undocumented acceptable range.

---

## Branches and PRs (quick reference)

| Branch | PR | Commit | Expiration | Merged |
|--------|----|--------|-----------|--------|
| `feat/mini-app-functional` | [#34](https://github.com/ElliotFriedman/harvest-world/pull/34) | `4418702` | `0` | Yes |
| `fix/permit2-expiration` | [#54](https://github.com/ElliotFriedman/harvest-world/pull/54) | `c8afe92` | `now + 86400` | Yes |
| `fix/permit2-expiration-zero` | [#56](https://github.com/ElliotFriedman/harvest-world/pull/56) | `a29b254` | `0` | Yes |
| `fix/permit2-expiration-timestamp` | [#59](https://github.com/ElliotFriedman/harvest-world/pull/59) | `eef311a` | `now + 60` | Yes |
| `fix/permit2-expiration-15s` | [#60](https://github.com/ElliotFriedman/harvest-world/pull/60) | `96727b8` | `now + 15` | Yes |
| `fix/permit2-current-timestamp` | [#62](https://github.com/ElliotFriedman/harvest-world/pull/62) | `6533101` | `now + 0` | Yes |
| `fix/permit2-expiration-2s` | -- | `0407597` | `now + 2` | Pending |

---

## Key Source Files

| File | Relevance |
|------|-----------|
| `contracts/lib/permit2/src/libraries/Allowance.sol` (lines 7-30) | Sentinel value logic: `0` maps to `block.timestamp` |
| `contracts/lib/permit2/src/libraries/Allowance.sol` (lines 34-41) | `updateAmountAndExpiration`: same sentinel logic |
| `contracts/lib/permit2/src/AllowanceTransfer.sol` (line 79) | Expiry check: strict `>` (not `>=`) |
| `contracts/lib/permit2/src/interfaces/IAllowanceTransfer.sol` (line 12) | `AllowanceExpired(uint256 deadline)` error definition |
| `app/src/app/page.tsx` (~line 374) | Where expiration is set in the frontend deposit flow |

---

## What Would Fix This

1. **World documents the actual acceptable range.** The docs say `0` but the backend rejects it. If the acceptable range is, say, `now + 1` to `now + 5`, that should be documented.

2. **World's simulation handles the `0` sentinel correctly.** If the simulation engine stored `block.timestamp` for `expiration=0` (matching on-chain behavior), the docs would be correct and `0` would work.

3. **World's simulation uses a consistent `block.timestamp`.** If both `approve()` and `transferFrom()` within the same UserOp see the same `block.timestamp` in simulation (as they would on-chain), any of the near-current values would pass.
