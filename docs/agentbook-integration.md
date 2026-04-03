# AgentBook Integration Spec

## Problem

The vault's `onlyHuman` modifier currently only allows addresses that have called `verifyHuman()` (World ID ZK proof). Human-backed agents — wallets registered in World's AgentBook — are blocked even though they represent a verified unique human.

## Solution

Read AgentBook on-chain during the `onlyHuman` check. No new storage, no owner whitelist, fully trustless.

## AgentBook Contract

**Address (World Chain mainnet):** `0xA23aB2712eA7BBa896930544C7d6636a96b944dA`

**Relevant function:**
```solidity
function lookupHuman(address agent) external view returns (uint256 humanId);
```
Returns the nullifier hash bound to `agent` at registration time. Returns `0` if the address has never registered. `!= 0` means the wallet is linked to a Orb-verified human.

**Registration flow (agent side):**
```bash
npx @worldcoin/agentkit-cli register <agent-wallet-address>
```
This prompts a World ID verification in World App and calls `AgentBook.register(agent, root, nonce, nullifierHash, proof)` on-chain. One human = one nullifier hash. A human can register multiple agent wallets, but each wallet maps to exactly one humanId.

## Vault Change

### Before
```solidity
modifier onlyHuman() {
    require(verifiedHumans[msg.sender], "Harvest: humans only");
    _;
}
```

### After
```solidity
// AgentBook on World Chain — maps agent wallets → humanId (nullifierHash)
IAgentBook public constant AGENT_BOOK =
    IAgentBook(0xA23aB2712eA7BBa896930544C7d6636a96b944dA);

modifier onlyHuman() {
    require(
        verifiedHumans[msg.sender] || AGENT_BOOK.lookupHuman(msg.sender) != 0,
        "Harvest: humans only"
    );
    _;
}
```

## Depositor Matrix

| Caller | Path | Trustless? |
|--------|------|-----------|
| Human (World ID) | `verifyHuman()` → `verifiedHumans[addr] = true` | Yes — ZK proof |
| Human-backed agent | `AgentBook.register()` via CLI → `lookupHuman() != 0` | Yes — reads on-chain registry |
| Bot / EOA | Neither check passes | Blocked |

## Interface Required

Minimal `IAgentBook` interface in `contracts/src/interfaces/IAgentBook.sol`:
```solidity
interface IAgentBook {
    function lookupHuman(address agent) external view returns (uint256);
}
```

## Gas Impact

`lookupHuman` is a single `SLOAD` on the AgentBook mapping. ~2100 gas when cold, ~100 warm. Only paid when the `verifiedHumans` fast-path misses (i.e., for agents and unverified addresses).

## No Changes Needed

- `verifiedHumans` mapping stays as-is (humans still verify via `verifyHuman()`)
- `nullifierHashes` anti-replay stays as-is
- No new events needed (`AgentRegistered` is emitted by AgentBook itself)
- `verifyHuman()` function unchanged
