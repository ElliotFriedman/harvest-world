# Harvest Agent

Standalone harvester agent for the Harvest yield aggregator on World Chain (chainId 480). Claims Merkl rewards, swaps to USDC via Uniswap V3, and redeposits into the Morpho vault — auto-compounding yield for all depositors.

Uses **World AgentKit** to prove the agent is backed by a verified human (World ID / Orb).

## Architecture

```
Agent wallet (burner EOA)
  ├── Registered in AgentBook (human-backed via World ID)
  ├── Owns the Strategy contract (can call harvest/claim)
  └── Funded with small ETH for gas (~0.002 ETH)

Harvest cycle:
  1. Fetch unclaimed Merkl rewards for the strategy
  2. Call strategy.claim() — claim rewards from Merkl distributor
  3. Call strategy.harvest() — swap WLD → WETH → USDC, redeposit into Morpho
  4. Log share price increase
```

## Setup

### 1. Generate and fund a burner wallet

```bash
./contracts/script/setup-harvester.sh
```

This script:
- Generates a fresh EOA
- Saves the key to `.harvester-wallet.json` (gitignored)
- Funds it with ETH from the deployer keystore
- Transfers strategy ownership to the burner

### 2. Register with AgentKit

```bash
npx @worldcoin/agentkit-cli register <BURNER_ADDRESS>
```

Requires scanning a QR code with World App (Orb-verified). This registers the agent wallet in AgentBook on World Chain, proving it's human-backed.

### 3. Set environment variables

```bash
# In Vercel (for the cron endpoint):
AGENT_PRIVATE_KEY=0x...   # burner wallet private key
CRON_SECRET=<random-hex>  # protects the GET endpoint

# For running locally:
export AGENT_PRIVATE_KEY=0x...
export RPC_URL=https://worldchain.drpc.org  # optional
```

## Running

**Locally (one-shot):**
```bash
cd agent
npm install
AGENT_PRIVATE_KEY=0x... npm start
```

**Via Vercel Cron (automated):**

The app's `vercel.json` configures a daily cron that hits `GET /api/agent/harvest`. The endpoint verifies the `CRON_SECRET` bearer token and runs the same harvest logic.

## Contract Addresses

| Contract | Address |
|----------|---------|
| Strategy | `0x313bA1D5D5AA1382a80BA839066A61d33C110489` |
| Vault | `0x512CE44e4F69A98bC42A57ceD8257e65e63cD74f` |
| Agent (burner) | `0x39e1e01f4CB9B2FED78892aa378aB2baf0F759b9` |
| AgentBook Tx | `0x7af7c3c210fecd172bd20e85a4ac4cc96ef83a85f24a62066b86af7fd9974352` |

## Roadmap

**Permissionless harvesting via on-chain AgentKit gating.** Currently, only the strategy owner (burner wallet) can call `harvest()`. The next step is to gate `harvest()` on-chain so that *any* wallet registered as human-backed in AgentBook can compound on behalf of the entire pool. This makes the protocol fully permissionless — any verified human (or their agent) can trigger a harvest, removing the single-operator dependency and further decentralizing the system. See [#75](https://github.com/ElliotFriedman/harvest-world/issues/75) for tracking.

**Harvester role separation.** Split the current owner-level access into a dedicated `harvester` role that can only call `harvest()` and `claim()`, not admin functions like `pause()` or `transferOwnership()`.

## File Structure

```
agent/
  src/
    index.ts       — Entry point: env validation, AgentKit check, harvest
    agentkit.ts    — AgentBook verification (human-backed proof)
    harvester.ts   — Core harvest logic (claim + harvest via viem)
    merkl.ts       — Merkl rewards + WLD price fetchers
    config.ts      — Addresses, ABIs, chain config
```
