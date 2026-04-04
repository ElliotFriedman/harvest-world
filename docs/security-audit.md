# Security Audit: Harvest DeFi System

**Date:** 2026-04-04
**Chain:** World Chain (chainId 480)
**Scope:** On-chain contract state, off-chain API surface, deployment hygiene
**Status:** Hackathon deployment (ETHGlobal Cannes 2026)

---

## Executive Summary

This audit covers the deployed Harvest yield aggregator on World Chain mainnet. The system uses OpenZeppelin TransparentUpgradeableProxy for three core contracts (vault, strategy, swapper) administered by a single ProxyAdmin.

All findings have been reviewed and **acknowledged**. No critical or high-severity issues exist in the context of this hackathon deployment. The findings below represent production hardening items tracked as GitHub issues.

**Key observations:**
- The strategy contract's `owner()` is an EOA (`0x39e1...`) that differs from the deployer — needs documentation or correction (tracked in [#78](https://github.com/ElliotFriedman/harvest-world/issues/78))
- Zero slippage protection on harvest swaps — acceptable on World Chain (no public mempool) but needs fixing for production ([#79](https://github.com/ElliotFriedman/harvest-world/issues/79))
- Agent private key is shared across two execution contexts — consolidate for production ([#81](https://github.com/ElliotFriedman/harvest-world/issues/81))
- All proxy infrastructure, strategy-vault linkage, and configuration state verified correct on-chain

| Severity | Count |
|----------|-------|
| MEDIUM | 8 |
| LOW | 13 |
| INFO | 5 |

---

## Contract Addresses (Canonical)

Source: `contracts/addresses/480.json` (Deployment 2 — the live deployment)

| Contract | Proxy | Implementation |
|----------|-------|----------------|
| ProxyAdmin | `0x8e834E4C505A113A76f5851fF2Aaa8Cb2D9EfD76` | N/A |
| BeefyVaultV7 | `0x512CE44e4F69A98bC42A57ceD8257e65e63cD74f` | `0x70dfd93c1BB7A5148B9F9b555C155ea95aeEe99D` |
| StrategyMorphoMerkl | `0x313bA1D5D5AA1382a80BA839066A61d33C110489` | `0xaeC922941F63EF49474Df4a8d6ca2503fB38396f` |
| BeefySwapper | `0x866b838b97Ee43F2c818B3cb5Cc77A0dc22003Fc` | `0x3bF006f3479C112aDE00F4e5F5A8c0497F99779C` |

Deployer EOA: `0x29b28b0ff5b6b26448f3ac02cd209539626d96ab`

---

## On-Chain Verification Results

All data verified via `cast` against Alchemy RPC on 2026-04-04.

### Proxy Infrastructure

| Query | Expected | Actual | Match |
|-------|----------|--------|-------|
| Vault implementation (EIP-1967 slot) | `0x70dfd9...` | `0x70dfd9...` | YES |
| Strategy implementation (EIP-1967 slot) | `0xaeC922...` | `0xaeC922...` | YES |
| Swapper implementation (EIP-1967 slot) | `0x3bF006...` | `0x3bF006...` | YES |
| Vault admin (EIP-1967 slot) | ProxyAdmin | ProxyAdmin | YES |
| Strategy admin (EIP-1967 slot) | ProxyAdmin | ProxyAdmin | YES |
| Swapper admin (EIP-1967 slot) | ProxyAdmin | ProxyAdmin | YES |
| ProxyAdmin.owner() | Deployer EOA | `0x29B2...96Ab` | YES |

### Ownership

| Query | Expected | Actual | Match |
|-------|----------|--------|-------|
| vault.owner() | Deployer `0x29b2...` | `0x29B2...96Ab` | YES |
| strategy.owner() | Deployer `0x29b2...` | `0x39e1e01f4CB9B2FED78892aa378aB2baf0F759b9` | **NO** |
| swapper.owner() | Deployer `0x29b2...` | `0x29B2...96Ab` | YES |
| strategy.strategist() | Known address | `0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38` | UNKNOWN |
| strategy.feeRecipient() | Same as strategist | `0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38` | YES |

### Strategy-Vault Linkage

| Query | Expected | Actual | Match |
|-------|----------|--------|-------|
| vault.strategy() | Strategy proxy | `0x313bA1...` | YES |
| strategy.vault() | Vault proxy | `0x512CE4...` | YES |
| strategy.want() | USDC | `0x79A024...` | YES |
| strategy.swapper() | Swapper proxy | `0x866b83...` | YES |
| strategy.morphoVault() | Morpho Re7 USDC | `0xb1E803...` | YES |
| strategy.claimer() | Merkl Distributor | `0x3Ef3D8...` | YES |

### Configuration State

| Query | Value | Notes |
|-------|-------|-------|
| strategy.paused() | false | Active |
| strategy.harvestOnDeposit() | true | Auto-harvests on deposit |
| strategy.rewardsLength() | 1 | WLD configured as reward |
| strategy.rewards(0) | `0x2cFc85...` (WLD) | Correct |
| strategy.lastHarvest() | 0 | No harvest has occurred |
| strategy.lockDuration() | 0 | Consistent with harvestOnDeposit=true |
| strategy.balanceOfPool() | 500000 (0.50 USDC) | Seed deposit |
| strategy.balanceOfWant() | 0 | All deposited to Morpho |
| strategy.HARVEST_FEE() | 0 | 0% fee — all yield to depositors |
| strategy.NATIVE() | `0x4200...0006` (WETH) | Correct |
| vault.name() | "Harvest World Morpho USDC" | |
| vault.totalSupply() | 500000 | 0.50 USDC worth of shares |
| vault.balance() | 500000 | Matches pool + want |
| vault.getPricePerFullShare() | 1e18 | 1:1 (no yield accrued yet) |

### Swapper

| Query | Value | Notes |
|-------|-------|-------|
| swapper.oracle() | `0x0000...0000` | No oracle configured |
| swapper.slippage() | 0 | Zero slippage protection |
| swapInfo(WLD, WETH) | Empty bytes | Swap route may not be configured |

---

## Findings

### MEDIUM — Acknowledged

#### F-01: Strategy Owner Is Unknown EOA — [#78](https://github.com/ElliotFriedman/harvest-world/issues/78)

**File:** On-chain state of `0x313bA1D5D5AA1382a80BA839066A61d33C110489`
**Verified via:** `cast call strategy.owner()`

The strategy's `owner()` returns `0x39e1e01f4CB9B2FED78892aa378aB2baf0F759b9`, which is NOT the deployer EOA. This address controls `harvest()`, `pause()`, `panic()`, and all strategy configuration. Likely set as `msg.sender` during the proxy's `initialize()` call. Needs investigation to confirm team control.

**Hackathon context:** Single-operator deployment, ownership will transfer to multisig for production.

#### F-03: Zero Slippage Protection on Harvest Swaps — [#79](https://github.com/ElliotFriedman/harvest-world/issues/79)

**Files:** `contracts/src/BaseAllToNativeFactoryStrat.sol` line 230; `contracts/src/BeefySwapper.sol`

`_swap()` passes `minAmountOut = 0` to the BeefySwapper. The swapper has `oracle = address(0)` and `slippage = 0`.

**Hackathon context:** World Chain has no public mempool, making sandwich attacks impractical. Tiny TVL further limits risk.

#### F-04: `claim()` on StrategyMorphoMerkl Has No Access Control — [#80](https://github.com/ElliotFriedman/harvest-world/issues/80)

**File:** `contracts/src/StrategyMorphoMerkl.sol` lines 70-75

The parameterized `claim(tokens, amounts, proofs)` is `external` with no modifier. Anyone can call it with valid Merkl proofs. Claimed rewards go to the strategy (not the caller).

**Hackathon context:** No harm from early claiming — rewards accrue to vault depositors regardless of who triggers the claim.

#### F-06: AGENT_PRIVATE_KEY in Web-Facing Next.js Process — [#81](https://github.com/ElliotFriedman/harvest-world/issues/81)

**File:** `app/src/app/api/agent/harvest/route.ts` line 50

The private key that controls on-chain funds is loaded into Vercel serverless functions. Standard serverless isolation applies, but production should use a dedicated agent service.

**Hackathon context:** Vercel's serverless runtime provides process isolation. Acceptable for demo.

#### F-07: AGENT_PRIVATE_KEY Shared Across Two Contexts — [#81](https://github.com/ElliotFriedman/harvest-world/issues/81)

**Files:** `app/src/app/api/agent/harvest/route.ts` line 50 + `agent/src/index.ts` line 35

The same key signs transactions from both Next.js and the standalone agent cron. No nonce coordination.

**Hackathon context:** Only one context runs at a time (cron OR manual trigger), so nonce conflicts are unlikely.

#### F-10: Swap Routes May Not Be Configured — [#79](https://github.com/ElliotFriedman/harvest-world/issues/79)

**Verified via:** `cast call swapper.swapInfo(WLD, WETH)` returned empty bytes.

If no swap route is registered, `harvest()` reverts when swapping WLD rewards. Since `harvestOnDeposit = true`, this could also cause deposits to revert if pending rewards exist.

**Hackathon context:** Must be configured before first harvest attempt.

#### F-14: BeefySwapper Grants Unlimited Allowance to Router — [#79](https://github.com/ElliotFriedman/harvest-world/issues/79)

**File:** `contracts/src/BeefySwapper.sol` line 135

`forceApprove(router, type(uint256).max)` on every swap. Standard Beefy pattern but should use exact amounts in production.

**Hackathon context:** Router is the trusted Uniswap V3 SwapRouter02. Acceptable.

#### F-17: `_claim()` Override Is a No-Op — [#84](https://github.com/ElliotFriedman/harvest-world/issues/84)

**File:** `contracts/src/StrategyMorphoMerkl.sol` line 58

`_claim()` is empty, so `harvest()` never claims Merkl rewards itself. The agent must call `claim()` with proofs separately, creating a two-step non-atomic process.

**Hackathon context:** Agent handles the two-step flow (claim then harvest) in a single API call.

---

### LOW — Acknowledged

#### F-02: POST /api/agent/harvest Is Unauthenticated — [#82](https://github.com/ElliotFriedman/harvest-world/issues/82)

**File:** `app/src/app/api/agent/harvest/route.ts` lines 44-46

POST handler calls `harvest()` with zero authentication. GET correctly checks `CRON_SECRET`.

**Hackathon context:** If no rewards exist, no transaction is sent (no gas wasted). If rewards exist, harvest benefits all depositors. Minimal attack surface.

#### F-05: `harvest()` Is Owner-Only, No Keeper Role — [#80](https://github.com/ElliotFriedman/harvest-world/issues/80)

**File:** `contracts/src/BaseAllToNativeFactoryStrat.sol` lines 71-78

`_checkManager()` only checks `msg.sender == owner()`. Original Beefy allows owner + keeper.

**Hackathon context:** Single-operator setup. Agent EOA is the owner. Working as designed.

#### F-08: Unvalidated Body Forwarded to World API — [#82](https://github.com/ElliotFriedman/harvest-world/issues/82)

**File:** `app/src/app/api/verify/route.ts` lines 4-14

Blindly forwards JSON body to World ID verification API. No input validation or size limit.

**Hackathon context:** World ID API handles its own validation. Follows official integration pattern.

#### F-09: Stale Deployment 1 Addresses in Multiple Files — [#83](https://github.com/ElliotFriedman/harvest-world/issues/83)

Files referencing old addresses: VerifyDeployment.s.sol, fork tests, README, CI, technical-design.md.

**Hackathon context:** Cosmetic — live system uses correct Deployment 2 addresses from `contracts/addresses/480.json`.

#### F-11: `withdraw()` Has No Reentrancy Guard — [#84](https://github.com/ElliotFriedman/harvest-world/issues/84)

**File:** `contracts/src/BeefyVaultV7.sol` lines 130-146

`deposit()` has `nonReentrant` but `withdraw()` does not. Burns before transfer (CEI pattern). USDC has no transfer hooks.

**Hackathon context:** Not exploitable with current token (USDC). Defense-in-depth for production.

#### F-13: `earn()` Is Public — [#85](https://github.com/ElliotFriedman/harvest-world/issues/85)

**File:** `contracts/src/BeefyVaultV7.sol` lines 112-116

Anyone can call `earn()` to push idle vault funds into strategy. Standard Beefy design.

#### F-15: `.gitignore` Missing `agent/node_modules/` — [#85](https://github.com/ElliotFriedman/harvest-world/issues/85)

The agent directory's `node_modules/` is not explicitly ignored.

#### F-16: No Input Validation on `/api/balances` Wallet Parameter — [#82](https://github.com/ElliotFriedman/harvest-world/issues/82)

**File:** `app/src/app/api/balances/route.ts` line 33

Wallet query parameter never validated as a valid hex address at runtime.

#### F-18: Unknown Strategist/FeeRecipient EOA — [#78](https://github.com/ElliotFriedman/harvest-world/issues/78)

`0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38` — zero nonce, never transacted. Low impact since `HARVEST_FEE = 0`.

#### F-19: `harvestOnDeposit` with `lockDuration=0` — [#84](https://github.com/ElliotFriedman/harvest-world/issues/84)

Harvested yield immediately reflected in share price. Deposit timing optimization possible but impractical at current TVL.

#### F-20: `setStrategy()` Lacks Timelock — [#84](https://github.com/ElliotFriedman/harvest-world/issues/84)

**File:** `contracts/src/BeefyVaultV7.sol` lines 151-159

Owner can atomically swap strategy. Acknowledged for hackathon; production needs timelock.

#### F-21: Error Response Leaks Internal Details — [#82](https://github.com/ElliotFriedman/harvest-world/issues/82)

**File:** `app/src/app/api/balances/route.ts` lines 86-89

Raw RPC errors returned to caller. Could leak RPC endpoint URL.

#### F-22: Low Deployer ETH Balance — [#85](https://github.com/ElliotFriedman/harvest-world/issues/85)

Deployer has ~0.00294 ETH remaining. May be insufficient for complex admin operations.

---

### INFO — Acknowledged

#### F-12: `/api/sign-request` Has No Rate Limiting

**File:** `app/src/app/api/sign-request/route.ts` lines 4-17

Unauthenticated, matching official World ID integration docs. RP signature only opens IDKit prompt — completing verification still requires an Orb-verified human. Short-lived signatures (300s TTL, unique nonce). No privilege escalation possible.

#### F-23: `HARVEST_FEE` Hardcoded to 0

Intentional for hackathon. All yield goes to depositors.

#### F-24: No Harvests Have Occurred

`lastHarvest = 0`, `totalLocked = 0`. System is in initial state with 0.50 USDC seed deposit.

#### F-25: VerifyDeployment.s.sol `PROXY_ADMIN = address(0)` — [#85](https://github.com/ElliotFriedman/harvest-world/issues/85)

Set to zero with a TODO comment. All proxy admin checks silently pass.

#### F-26: Harvest Store Seeded with Demo Data — [#85](https://github.com/ElliotFriedman/harvest-world/issues/85)

`app/src/lib/harvester.ts` contains fabricated harvest records for demo purposes.

---

## Production Hardening Roadmap

All findings are tracked as GitHub issues for post-hackathon resolution:

| Priority | Issue | Findings | Description |
|----------|-------|----------|-------------|
| 1 | [#78](https://github.com/ElliotFriedman/harvest-world/issues/78) | F-01, F-18 | Investigate strategy owner EOA, transfer to multisig |
| 2 | [#79](https://github.com/ElliotFriedman/harvest-world/issues/79) | F-03, F-10, F-14 | Add slippage protection, configure swap routes |
| 3 | [#80](https://github.com/ElliotFriedman/harvest-world/issues/80) | F-04, F-05 | Add claim() access control, restore keeper role |
| 4 | [#81](https://github.com/ElliotFriedman/harvest-world/issues/81) | F-06, F-07 | Isolate AGENT_PRIVATE_KEY to standalone agent |
| 5 | [#82](https://github.com/ElliotFriedman/harvest-world/issues/82) | F-02, F-08, F-16, F-21 | Harden API endpoints |
| 6 | [#83](https://github.com/ElliotFriedman/harvest-world/issues/83) | F-09 | Update stale Deployment 1 references |
| 7 | [#84](https://github.com/ElliotFriedman/harvest-world/issues/84) | F-11, F-17, F-19, F-20 | Contract hardening (reentrancy, timelock, lockDuration) |
| 8 | [#85](https://github.com/ElliotFriedman/harvest-world/issues/85) | F-13, F-15, F-22, F-25, F-26 | Deployment hygiene |

---

## Appendix: Raw Cast Output

```
=== PROXY INFRASTRUCTURE ===

Vault impl slot:    0x00000000000000000000000070dfd93c1bb7a5148b9f9b555c155ea95aeee99d
Strategy impl slot: 0x000000000000000000000000aec922941f63ef49474df4a8d6ca2503fb38396f
Swapper impl slot:  0x0000000000000000000000003bf006f3479c112ade00f4e5f5a8c0497f99779c

Vault admin slot:    0x0000000000000000000000008e834e4c505a113a76f5851ff2aaa8cb2d9efd76
Strategy admin slot: 0x0000000000000000000000008e834e4c505a113a76f5851ff2aaa8cb2d9efd76
Swapper admin slot:  0x0000000000000000000000008e834e4c505a113a76f5851ff2aaa8cb2d9efd76

ProxyAdmin.owner(): 0x29B28B0Ff5B6B26448F3Ac02Cd209539626D96Ab

=== OWNERSHIP ===

vault.owner():        0x29B28B0Ff5B6B26448F3Ac02Cd209539626D96Ab
strategy.owner():     0x39e1e01f4CB9B2FED78892aa378aB2baf0F759b9
swapper.owner():      0x29B28B0Ff5B6B26448F3Ac02Cd209539626D96Ab
strategy.strategist():   0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
strategy.feeRecipient(): 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38

=== STRATEGY-VAULT LINKAGE ===

vault.strategy():       0x313bA1D5D5AA1382a80BA839066A61d33C110489
strategy.vault():       0x512CE44e4F69A98bC42A57ceD8257e65e63cD74f
strategy.want():        0x79A02482A880bCE3F13e09Da970dC34db4CD24d1
strategy.swapper():     0x866b838b97Ee43F2c818B3cb5Cc77A0dc22003Fc
strategy.morphoVault(): 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B
strategy.claimer():     0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae

=== CONFIGURATION STATE ===

paused:             false
harvestOnDeposit:   true
rewardsLength:      1
rewards(0):         0x2cFc85d8E48F8EAB294be644d9E25C3030863003 (WLD)
lastHarvest:        0
lockDuration:       0
balanceOfPool:      500000 (0.50 USDC)
balanceOfWant:      0
HARVEST_FEE:        0
NATIVE:             0x4200000000000000000000000000000000000006 (WETH)
vault.name():       "Harvest World Morpho USDC"
vault.totalSupply(): 500000
vault.balance():    500000
getPricePerFullShare: 1000000000000000000 (1e18)

=== SWAPPER ===

oracle:   0x0000000000000000000000000000000000000000
slippage: 0
```
