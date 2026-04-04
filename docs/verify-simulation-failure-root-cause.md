# Root Cause Analysis: `verifyHuman` Simulation Failure

**Date:** 2026-04-04
**Status:** Root cause confirmed via on-chain investigation
**Symptom:** `MiniKit.sendTransaction()` returns `simulation_failed` → on-chain revert: `NonExistentRoot()`

---

## TL;DR

The vault's `verifyHuman()` calls `WorldIDRouter.verifyProof()`. That router reverts with `NonExistentRoot()` because the Merkle root in the IDKit proof is not registered in the World Chain WorldIDRouter.

The root in the proof is from the **V3 Merkle tree** (requested via `orbLegacy()`). The World Chain WorldIDRouter has been updated for World ID 4.0 and only maintains **V4 Merkle roots**. The V3 root was never registered and never will be.

---

## On-Chain Evidence

### WorldIDRouter (`0x17B354dD...`)
- UUPS proxy pointing to implementation `0x4055b6D4018e92e4d000865E61E87b57A4E5aB49`
- Routes group 1 (Orb) to verifier at `0xdFCa0A882eF7793485B3d052142B60647E82009E`
- `groupCount() = 4` (4 credential groups)

### Orb Verifier (`0xdFCa0A882...`)
- Root history expiry: 604,800 seconds = **7 days**
- `latestRoot()` = `0x082d67a49632e280e08b7fa2c1d10c0d798510fd08ea94108f855a2ab0f29f46`
- This root was registered at **2026-04-04T07:36:19 UTC** (today)
- Root expires: **2026-04-11T07:36:19 UTC**

### Revert behavior (cast probing)
| Input | Error selector | Error name |
|-------|---------------|-----------|
| Any root not in history | `0xddae3b71` | `NonExistentRoot()` |
| Correct root + fake proof | `0x7fcdd1f4` | `ProofInvalid()` |

**Proof the root is the blocker:** Using `0x082d67...` (the real registered root) with a fake `[1,2,3,4,5,6,7,8]` proof gives `ProofInvalid()` — a DIFFERENT error. This means the root check PASSES when the correct root is used. The simulation fails with `NonExistentRoot()` because IDKit's proof uses a root that isn't `0x082d67...`.

---

## Why `orbLegacy()` Produces an Unrecognized Root

### What `orbLegacy()` + `allow_legacy_proofs: true` does

`orbLegacy()` requests a **World ID V3 format proof** — 8-element uncompressed Groth16 with a separate `merkle_root` field. `allow_legacy_proofs: true` tells the protocol the client accepts both V3 and V4 responses.

### What the V3 Merkle root is

World ID V3 maintains an Ethereum-based Merkle tree (the Semaphore identity tree). Its roots are bridged to other chains via a state bridge. The V3 Merkle root in the proof was valid on Ethereum mainnet at proof-generation time.

### What the World Chain WorldIDRouter knows

The World Chain WorldIDRouter has undergone the **World ID 4.0 migration**. The V4 system uses a new Merkle tree. The verifier only maintains V4 roots in its `rootHistory`.

The V3 root from the IDKit proof was **never registered** in this verifier's `rootHistory`. It doesn't appear (timestamp = 0), hence `NonExistentRoot()`.

This is not a timing issue — the V3 root will NEVER appear in the V4 verifier's history because it's from a different Merkle tree entirely.

---

## What Was Previously Investigated and Why It Didn't Help

### `decodeAbiParameters` fix (claimed root cause, disproved)

**Claim:** IDKit V3 returns proof with a 32-byte ABI offset prefix; manual slicing reads the offset as proof[0], corrupting all 8 values.

**Empirical disproof:** `decodeAbiParameters([{type:'uint256[8]'}])` is **byte-for-byte identical** to 64-char manual slicing for `uint256[8]` (a static ABI type). Both methods read from position 0. This was verified in Node.js:
```
512-char input: OLD == NEW (both correct)
576-char input: OLD == NEW (both equally wrong)
```

The fix cannot change the output for any standard encoding of `uint256[8]`. Even if there were an offset issue, for V3 proofs the root comes from `v3.merkle_root` (a separate field), NOT from `decodeProof()`. So even a broken `decodeProof()` wouldn't affect the root value.

### Signal staleness fix (PR #44, correct but insufficient)

Fixed the signal being null/stale when IDKit opens. This was a real bug that would cause `ProofInvalid()`. It is correctly fixed. But `NonExistentRoot()` happens BEFORE proof validation — no signal value can fix a missing root.

### externalNullifierHash (confirmed correct, not the bug)

Deployed hash: `343046634147760258897983793882990161868366126787275247337448342868706970111`
Computed from `app_4e0a09224d5cc08fca4cd09ef101f966` + `"verify-human"`: exact match ✓

---

## Why There's Only One Root in the Verifier

The verifier at `0xdFCa0A882...` has:
- Slot 0: `604800` (rootHistoryExpiry)
- Slot 1: `0x082d67...` (current root, registered 07:36 UTC today)
- Slots 2+: zero

This strongly suggests the verifier was recently deployed or recently migrated for V4, and has only received **one root insertion** since deployment. Older V3 roots were never imported into this V4 verifier.

---

## Fix Options for Hackathon

### Option A: Remove on-chain World ID verification (RECOMMENDED for hackathon)

Remove the `verifyHuman()` on-chain call entirely. Trust the backend `/api/verify` response instead.

Flow:
1. IDKit opens → user verifies → `handleVerify()` succeeds against World's API
2. Backend returns `200 OK` → frontend sets `isVerified = true` locally
3. Remove `verifyHuman()` from vault's `deposit()` or make it optional (owner-bypassed)
4. The World ID verification story still holds for judges: proof is validated server-side

**Pros:** Works immediately. Backend `/api/verify` already succeeds.
**Cons:** Loses trustless on-chain verification.

### Option B: Update vault to accept V4 proofs via WorldIDVerifier

Replace `WorldIDRouter.verifyProof(uint256[8])` with `WorldIDVerifier.verify(uint256[5])`.

**Blocker:** Per World ID docs, `WorldIDVerifier` is **testnet preview only** — not deployed to World Chain mainnet.

### Option C: Backend-signed attestation

Backend verifies via `/api/v4/verify/{rp_id}`, then signs an EIP-712 attestation. Vault accepts `deposit(amount, attestation)` where attestation is the backend signature.

**Pros:** Works with V4, trustless on vault side (verifies backend signature), no on-chain World ID needed.
**Cons:** Introduces backend trust assumption.

### Option D: Use V4 proof + hope WorldIDRouter supports it

Try V4 proofs (drop `orbLegacy()`, set `allow_legacy_proofs: false`). V4 proofs use `uint256[5]` format, but the vault contract expects `uint256[8]`. Would require contract redeployment AND WorldIDVerifier on mainnet.

**Blocker:** WorldIDVerifier not on mainnet. Would require significant rework.

---

## Recommended Next Step

**Option A is the right call for the hackathon.**

The World ID verification story remains strong:
- IDKit proves the user is Orb-verified
- Backend validates proof via World's `/api/v4/verify/{rp_id}` (already implemented)
- On-chain, skip `verifyHuman()` — either remove the `onlyHuman` modifier for the demo OR whitelist the demo wallet directly
- Judges care that World ID is integrated, not that it's enforced on-chain

The on-chain trustless path can be revisited once `WorldIDVerifier` is mainnet-deployed (expected soon given it's in preview).

---

## Files Summary

| File | Role | Issue |
|------|------|-------|
| `contracts/src/BeefyVaultV7.sol:186-196` | `verifyHuman()` — calls WorldIDRouter | Calls a verifier that won't recognize V3 roots |
| `contracts/src/interfaces/IWorldID.sol` | `uint256[8]` interface | Only compatible with V3 uncompressed proof |
| `app/src/app/page.tsx:439-457` | `openIdkit()` with `orbLegacy()` | Requests V3 proof whose root won't exist on-chain |
| `app/src/app/api/verify/route.ts` | Backend World ID verify | Works correctly — not the issue |
| `app/src/app/api/sign-request/route.ts` | RP signing | Works correctly — not the issue |
