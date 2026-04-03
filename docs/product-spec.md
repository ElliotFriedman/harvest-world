# Harvest: Product Specification v2.0

> The first yield aggregator on World Chain. Deposit tokens, let an AI agent auto-compound your yield.

**Status:** Final spec — replaces all prior claims-aggregator documents  
**Date:** April 3, 2026  
**Team:** 3-4 engineers, 36-hour hackathon build  
**Target:** World Chain hackathon — $20K in prizes (AgentKit $8K + World ID $8K + MiniKit $4K)

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Design Principles and Constraints](#2-design-principles-and-constraints)
3. [System Architecture](#3-system-architecture)
4. [Smart Contracts](#4-smart-contracts)
5. [AI Strategist Agent](#5-ai-strategist-agent)
6. [Frontend — World Mini App](#6-frontend--world-mini-app)
7. [Authentication and Authorization](#7-authentication-and-authorization)
8. [Database Schema](#8-database-schema)
9. [API Routes](#9-api-routes)
10. [Terminal Interface and Commands](#10-terminal-interface-and-commands)
11. [Environment Variables](#11-environment-variables)
12. [Repository Structure](#12-repository-structure)
13. [Deployment](#13-deployment)
14. [Build Schedule](#14-build-schedule)
15. [Demo Script](#15-demo-script)
16. [Prize Alignment](#16-prize-alignment)
17. [Risk Mitigation](#17-risk-mitigation)
18. [Cut Order](#18-cut-order)
19. [Competitive Edge](#19-competitive-edge)
20. [Appendix: Contract Addresses](#20-appendix-contract-addresses)

---

## 1. Product Overview

### What Harvest Is

Harvest is the first yield aggregator on World Chain. It is a shared vault system — modeled on Beefy Finance — where users deposit tokens (USDC, WLD), and an AI-powered strategist agent automatically compounds Morpho vault yield and Merkl reward distributions on their behalf.

The core value proposition: **one agent transaction replaces thousands of individual user claims.** Users deposit and forget. The agent does the rest.

### What Harvest Is NOT

- NOT a chatbot or conversational AI product. The terminal accepts structured commands, not natural language. The agent works silently in the background.
- NOT a swap aggregator or DEX. Users deposit the token the vault accepts.
- NOT per-user strategy contracts. All users share a single vault per asset.
- NOT a governance platform. No timelocks, no voting, no DAO.

### The Problem

There is $42 million in DeFi on World Chain. Users deposit into Morpho vaults and earn yield. But:

1. Merkl rewards pile up unclaimed. Users must manually claim from the Merkl distributor.
2. Nobody auto-compounds. Claimed rewards sit in wallets instead of being redeposited.
3. There is no Beefy, no Yearn, no yield aggregator of any kind on World Chain. DeFiLlama confirms zero exist.
4. World App has 40 million users. Most will never learn what a Morpho vault is or how to claim Merkl rewards.

### The Solution

Harvest wraps Morpho vaults in a Beefy-style auto-compounding layer. Users deposit USDC (or WLD) via a one-tap transaction in the World Mini App. The AI strategist agent:

1. Monitors Morpho vault APYs and Merkl reward distributions
2. Claims accumulated Merkl rewards on behalf of the vault
3. Swaps reward tokens to the vault's want token (e.g., WLD -> USDC)
4. Redeposits into the Morpho vault, increasing the share price for all depositors

One agent transaction compounds for every depositor simultaneously. Your yield earns yield, automatically.

### Mental Model

```
Beefy Finance  +  AgentKit  +  World Mini App  =  Harvest
(vault model)    (AI agent)    (40M users)
```

---

## 2. Design Principles and Constraints

These are non-negotiable. Do not deviate.

### D1: Shared Vault Model (ERC-4626-like via Beefy)

All users deposit into the same vault per asset. The vault mints proportional shares (mooTokens). When the agent compounds, the share price increases — all holders benefit equally. There are NO per-user strategy contracts, NO per-user accounting in the smart contracts.

### D2: Fork Beefy's Contracts

MIT-licensed, battle-tested, audited. Do not reinvent the vault primitive. Fork from `github.com/beefyfinance/beefy-contracts`. Strip governance, treasury, and timelocks for hackathon speed. Keep the core vault + strategy architecture.

### D3: No Natural Language / AI Chat

The agent is invisible to the user. There is no chat interface, no natural language prompt, no conversational UI. The terminal accepts structured commands (`vaults`, `deposit 50 usdc`, `agent status`) -- not free-form text. Users see what the agent DID (harvest history, amounts compounded, gas costs) via the `agent status` command. The agent's intelligence is in strategy selection and timing, not conversation.

### D4: No Swap Routing in MVP

Users deposit the token the vault accepts. The USDC vault accepts USDC. The WLD vault accepts WLD. There is no zap-in, no swap routing, no multi-token deposit. This is a stretch goal only.

### D5: AgentKit Is Core, Not Stretch

The agent IS the product. AgentKit is not bolted on for prize eligibility — it is the mechanism by which the strategist operates. The agent uses AgentKit credentials to prove it is human-backed, uses x402 micropayments for premium data, and calls on-chain functions (harvest, rebalance) autonomously. If the agent does not work, the product does not work.

### D6: World ID Gates Deposits

Only World ID-verified humans can deposit into vaults. This prevents sybil farming of vault yields and Merkl rewards. Verification happens once at session start and is stored as a hashed nullifier in the database.

### D7: Terminal-First Interface

One screen. Commands, not clicks. Tappable shortcuts for mobile. The entire app is a single retro terminal with a green-on-black monospace aesthetic. There is no navigation, no separate screens, no routing. Users type commands or tap shortcut buttons to interact with the protocol. This is faster to build, more memorable to demo, and more engaging to watch.

---

## 3. System Architecture

### High-Level Diagram

```
+---------------------------------------------+
|              World App (Client)              |
|  +---------------------------------------+  |
|  |        Harvest Mini App (Next.js)     |  |
|  |  - MiniKit walletAuth (SIWE)          |  |
|  |  - MiniKit verify (World ID)          |  |
|  |  - MiniKit sendTransaction            |  |
|  |    (approve + deposit multicall)      |  |
|  +---------------------------------------+  |
+---------------------+----+------------------+
                      |    |
            REST API  |    |  sendTransaction
                      v    v
+---------------------+----+------------------+
|          Next.js API Routes (Vercel)         |
|  - /api/auth/session                         |
|  - /api/vaults                               |
|  - /api/vaults/[address]/history             |
|  - /api/user/deposits                        |
|  - /api/agent/activity                       |
+-----------+---------+--------+--------------+
            |                  |
   Supabase |                  | Read-only RPC
            v                  v
+---------------------+  +--------------------+
|  Supabase Postgres   |  | World Chain (480)  |
|  - users             |  |                    |
|  - deposits          |  | BeefyVaultV7       |
|  - withdrawals       |  | StrategyMorpho     |
|  - harvests          |  | BeefySwapper       |
|  - vault_snapshots   |  |                    |
+----------------------+  | MetaMorpho Vaults  |
                          | Merkl Distributor  |
                          | Uniswap V3 Router  |
+----------------------+  +--------+-----------+
|   AI Strategist Agent |          |
|   (Node.js, cron)     |----------+
|                        |  harvest() / rebalance()
|  - AgentKit creds      |
|  - x402 micropayments  |
|  - Merkl API polling   |
|  - Morpho API polling  |
|  - Logs to Supabase    |
+------------------------+
```

### Component Ownership

| Component | Tech | Owner | Priority |
|-----------|------|-------|----------|
| Smart Contracts | Solidity, Foundry | Contracts person | P0 |
| AI Strategist Agent | Node.js, TypeScript, AgentKit | Backend person | P0 |
| Frontend Mini App | Next.js 15, MiniKit, Tailwind | Frontend person | P0 |
| Database + API | Supabase, Next.js API routes | Backend person | P0 |
| Integration | End-to-end wiring | All | P0 |

---

## 4. Smart Contracts

### 4.1 Contract Source

All contracts are forked from `github.com/beefyfinance/beefy-contracts` (MIT license).

### 4.2 Contracts to Fork

#### BeefyVaultV7.sol — User-Facing Vault

The main entry point for users. Implements ERC-4626-like share accounting.

**Key functions:**
- `deposit(uint256 _amount)` — User deposits want token, receives mooToken shares
- `withdraw(uint256 _shares)` — User burns mooToken shares, receives want token
- `balance()` — Total want token balance (vault + strategy)
- `getPricePerFullShare()` — Current share price (increases as agent compounds)
- `earn()` — Sends idle vault funds to the strategy

**Modifications from Beefy upstream:**
- Remove `owner()` governance functions (or set to deployer EOA)
- Remove treasury fee split (set fees to 0 or hardcode minimal fee)
- Add World ID verification modifier on `deposit()`:
  ```solidity
  modifier onlyVerifiedHuman(address _user) {
      require(worldIdVerified[_user], "!verified");
      _;
  }
  ```
- Add `setVerified(address _user, bool _status)` callable by the backend signer (verified off-chain via World ID proof, then whitelisted on-chain)
- Alternatively: accept the World ID proof on-chain using the WorldID contract (more trustless, more gas)

**Design decision on World ID enforcement:**

Option A (recommended for hackathon): Off-chain verification, on-chain whitelist. The backend verifies the World ID proof, then calls `setVerified(user, true)` from a trusted signer. Simpler, cheaper gas.

Option B (stretch): On-chain verification. The vault calls the World ID contract directly to verify the proof in the deposit transaction. More trustless but more complex and more gas.

Go with Option A for the hackathon.

#### BeefyVaultV7Factory.sol — Vault Factory

Uses EIP-1167 minimal proxy clones to deploy new vaults cheaply.

**Modifications:**
- Strip governance, keep factory pattern
- Hardcode initialization parameters for World Chain vaults

#### StrategyMorpho.sol — The Core Strategy

This is where yield generation happens. The strategy:

1. Holds the vault's funds in a MetaMorpho ERC-4626 vault (e.g., Re7 USDC)
2. Earns base lending yield from Morpho
3. Earns Merkl reward distributions (WLD tokens)
4. On `harvest()`: claims Merkl rewards, swaps to want token, redeposits

**Key functions:**
- `deposit()` — Deposits want token into the MetaMorpho vault
- `withdraw(uint256 _amount)` — Withdraws from MetaMorpho back to the Beefy vault
- `harvest()` — The money function. Called by the keeper (agent). Claims Merkl, swaps, redeposits.
- `balanceOf()` — Returns total strategy balance in the MetaMorpho vault
- `balanceOfWant()` — Returns want token balance held idle in the strategy
- `balanceOfPool()` — Returns balance deposited in MetaMorpho

**harvest() flow in detail:**

```
harvest() [only callable by keeper/agent]
  |
  +-- 1. Claim Merkl rewards
  |      Call MerklDistributor.claim(
  |        address[] users = [strategyAddress],
  |        address[] tokens = [WLD],
  |        uint256[] amounts,
  |        bytes32[][] proofs
  |      )
  |
  +-- 2. Swap rewards to want token
  |      If vault is USDC: swap WLD -> USDC via Uniswap V3
  |      If vault is WLD: no swap needed, rewards are already WLD
  |      Uses BeefySwapper for the swap
  |
  +-- 3. Charge performance fee (optional, 0% for hackathon)
  |
  +-- 4. Redeposit into MetaMorpho
  |      Call MetaMorphoVault.deposit(wantBalance, strategyAddress)
  |
  +-- 5. Emit Harvested(wantBalance) event
```

**Modifications from Beefy upstream:**
- Hardcode the MetaMorpho vault address per strategy deployment
- Hardcode the Merkl distributor address
- Remove complex fee splitting (strategist fee, call fee, beefy fee)
- Set harvest caller fee to 0 (agent pays gas, no bounty needed)
- Add Merkl claiming logic directly in `harvest()` (Beefy's StrategyMorpho may already have this — check upstream)
- Simplify reward token handling (only WLD rewards on World Chain)

<!-- Merged from claimall-spec.md -->

**Merkl Distributor Claim Details (used in harvest() flow):**

Address: `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae` on World Chain (480). The function is permissionless -- anyone can call it on behalf of a user. The `amounts` are cumulative totals, NOT incremental (the contract tracks what has already been claimed).

```solidity
// Merkl Distributor claim signature
function claim(
    address[] calldata users,
    address[] calldata tokens,
    uint256[] calldata amounts,   // cumulative, NOT incremental
    bytes32[][] calldata proofs
) external;
```

Encoding the call in TypeScript:

```typescript
import { encodeFunctionData } from "viem";

const merklClaimData = encodeFunctionData({
  abi: [{
    inputs: [
      { name: "users", type: "address[]" },
      { name: "tokens", type: "address[]" },
      { name: "amounts", type: "uint256[]" },
      { name: "proofs", type: "bytes32[][]" }
    ],
    name: "claim",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  }],
  functionName: "claim",
  args: [
    [strategyAddress],           // users array
    [wldTokenAddress],           // tokens array
    [cumulativeAmount],          // amounts array (cumulative!)
    [proof],                     // merkle proofs array
  ],
});
```

#### StrategyFactory.sol — Strategy Factory

Beacon proxy pattern for deploying strategy instances.

**Modifications:**
- Minimal — just ensure it works with the modified StrategyMorpho

#### BeefySwapper.sol — Token Swap Router

Handles swapping reward tokens to want tokens during harvest.

**Modifications (significant simplification):**
- Remove multi-DEX routing, oracle validation, slippage curves
- Hardcode Uniswap V3 swap paths for World Chain:
  - WLD -> USDC: `WLD/USDC 0.3% pool` on Uniswap V3
  - WLD -> WETH: `WLD/WETH 0.3% pool` (if needed)
- Use SwapRouter02 at `0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6`
- Hardcode 1% max slippage (acceptable for hackathon)

```solidity
// Simplified swap function
function swap(
    address _fromToken,
    address _toToken,
    uint256 _amountIn
) external returns (uint256 amountOut) {
    IERC20(_fromToken).approve(UNISWAP_ROUTER, _amountIn);
    
    ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02
        .ExactInputSingleParams({
            tokenIn: _fromToken,
            tokenOut: _toToken,
            fee: 3000, // 0.3%
            recipient: msg.sender,
            amountIn: _amountIn,
            amountOutMinimum: 0, // TODO: add slippage protection
            sqrtPriceLimitX96: 0
        });
    
    amountOut = ISwapRouter02(UNISWAP_ROUTER).exactInputSingle(params);
}
```

#### BeefyOracle.sol — Price Oracle (Optional)

Used by Beefy for slippage protection on swaps.

**Modifications:**
- Simplify to use Chainlink price feeds if available on World Chain
- Or hardcode a reasonable slippage tolerance and skip oracle entirely for hackathon
- This is a CUT candidate if time is short

### 4.3 Contract Deployment Plan

**Network:** World Chain Sepolia (testnet) for development, World Chain mainnet (480) for demo

**Tooling:** Foundry (forge, cast, anvil)

**Deployment sequence:**

```
1. Deploy BeefySwapper (hardcoded paths)
2. Deploy BeefyVaultV7 implementation
3. Deploy BeefyVaultV7Factory (pointing to implementation)
4. Deploy StrategyMorpho implementation
5. Deploy StrategyFactory (pointing to implementation)
6. Create USDC Vault:
   a. Factory.createVault() -> vault address
   b. Factory.createStrategy() -> strategy address
   c. vault.initialize(strategy, "mooMorphoUSDC", "mooMorphoUSDC")
   d. strategy.initialize(vault, morphoUSDCVault, merklDistributor, swapper)
7. Create WLD Vault (same pattern)
8. Set agent address as keeper on each strategy
9. Set backend signer for World ID whitelist on each vault
```

**Deployment script:** `script/Deploy.s.sol`

```solidity
// script/Deploy.s.sol
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/BeefyVaultV7.sol";
import "../src/strategies/StrategyMorpho.sol";
import "../src/infra/BeefySwapper.sol";

contract DeployHarvest is Script {
    // World Chain addresses
    address constant MORPHO_USDC = 0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B;
    address constant MORPHO_WLD = 0x348831b46876d3dF2Db98BdEc5E3B4083329Ab9f;
    address constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address constant WLD = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    address constant UNISWAP_ROUTER = 0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address keeper = vm.envAddress("KEEPER_ADDRESS");
        
        vm.startBroadcast(deployerKey);
        
        // 1. Deploy swapper
        BeefySwapper swapper = new BeefySwapper(UNISWAP_ROUTER);
        
        // 2. Deploy USDC vault + strategy
        BeefyVaultV7 usdcVault = new BeefyVaultV7();
        StrategyMorpho usdcStrategy = new StrategyMorpho();
        usdcStrategy.initialize(
            address(usdcVault),
            MORPHO_USDC,
            MERKL_DISTRIBUTOR,
            address(swapper),
            keeper
        );
        usdcVault.initialize(
            address(usdcStrategy),
            "mooHarvestUSDC",
            "mooHarvestUSDC"
        );
        
        // 3. Deploy WLD vault + strategy
        BeefyVaultV7 wldVault = new BeefyVaultV7();
        StrategyMorpho wldStrategy = new StrategyMorpho();
        wldStrategy.initialize(
            address(wldVault),
            MORPHO_WLD,
            MERKL_DISTRIBUTOR,
            address(swapper),
            keeper
        );
        wldVault.initialize(
            address(wldStrategy),
            "mooHarvestWLD",
            "mooHarvestWLD"
        );
        
        vm.stopBroadcast();
        
        // Log addresses
        console.log("Swapper:", address(swapper));
        console.log("USDC Vault:", address(usdcVault));
        console.log("USDC Strategy:", address(usdcStrategy));
        console.log("WLD Vault:", address(wldVault));
        console.log("WLD Strategy:", address(wldStrategy));
    }
}
```

### 4.4 Testing Strategy

**Local testing with Foundry:**
```bash
# Fork World Chain mainnet for realistic testing
forge test --fork-url $WORLD_CHAIN_RPC_URL

# Key test scenarios:
# 1. deposit() -> shares minted correctly
# 2. withdraw() -> correct amount returned
# 3. harvest() -> share price increases
# 4. World ID gate -> unverified user cannot deposit
# 5. Only keeper can call harvest()
```

**Test file:** `test/HarvestVault.t.sol`

Core test cases:
1. User deposits 100 USDC, receives correct shares
2. Two users deposit, shares proportional
3. Harvest compounds, share price increases
4. User withdraws after harvest, receives more than deposited
5. Unverified user blocked from depositing
6. Non-keeper blocked from calling harvest()
7. Harvest with zero rewards is a no-op (does not revert)

### 4.5 Gas Estimates

| Operation | Estimated Gas | Estimated Cost (World Chain) |
|-----------|--------------|------------------------------|
| deposit() | ~150K | ~$0.02 |
| withdraw() | ~120K | ~$0.01 |
| harvest() | ~350K | ~$0.05 |
| setVerified() | ~45K | ~$0.005 |

Harvest gas is paid by the agent. This is amortized across ALL depositors — one of the key value propositions.

---

## 5. AI Strategist Agent

### 5.1 Overview

The agent is a server-side Node.js/TypeScript process that acts as the vault's "keeper." It runs on a schedule, monitors yield opportunities, claims rewards, and compounds them back into the vault. It uses AgentKit for identity/credentials and x402 for micropayments to access premium data APIs.

The agent is NOT a chatbot. It has no user-facing interface. Users see the RESULTS of the agent's actions via the `agent status` command in the terminal (harvest history, amounts compounded).

### 5.2 Agent Runtime

```
Runtime: Node.js 20+ (TypeScript)
Framework: @coinbase/agentkit
Schedule: Cron job every 4 hours (or event-driven via Merkl webhook if available)
Host: Railway / Render / Vercel Cron (any long-running process host)
Wallet: Dedicated EOA registered as "keeper" on each strategy contract
```

### 5.3 Agent Loop (Pseudocode)

```typescript
// agent/src/strategist.ts

import { AgentKit } from "@coinbase/agentkit";
import { createPublicClient, createWalletClient, http } from "viem";
import { worldchain } from "viem/chains";
import { supabase } from "./db";

const HARVEST_INTERVAL_MS = 4 * 60 * 60 * 1000; // 4 hours
const MIN_REWARD_USD = 5; // Don't harvest if rewards < $5 (gas not worth it)

interface VaultConfig {
  vaultAddress: `0x${string}`;
  strategyAddress: `0x${string}`;
  wantToken: `0x${string}`;
  morphoVault: `0x${string}`;
  name: string;
}

const VAULTS: VaultConfig[] = [
  {
    vaultAddress: "0x...", // deployed BeefyVaultV7 for USDC
    strategyAddress: "0x...", // deployed StrategyMorpho for USDC
    wantToken: "USDC_ADDRESS",
    morphoVault: "0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B",
    name: "Harvest USDC",
  },
  {
    vaultAddress: "0x...", // deployed BeefyVaultV7 for WLD
    strategyAddress: "0x...", // deployed StrategyMorpho for WLD
    wantToken: "0x2cFc85d8E48F8EAB294be644d9E25C3030863003",
    morphoVault: "0x348831b46876d3dF2Db98BdEc5E3B4083329Ab9f",
    name: "Harvest WLD",
  },
];

async function runHarvestLoop() {
  const agentkit = await AgentKit.from({
    cdpApiKeyId: process.env.CDP_API_KEY_ID!,
    cdpApiKeySecret: process.env.CDP_API_KEY_SECRET!,
    networkId: "worldchain-mainnet",
  });

  const walletClient = createWalletClient({
    chain: worldchain,
    transport: http(process.env.WORLD_CHAIN_RPC_URL),
    account: agentkit.getAccount(),
  });

  const publicClient = createPublicClient({
    chain: worldchain,
    transport: http(process.env.WORLD_CHAIN_RPC_URL),
  });

  for (const vault of VAULTS) {
    try {
      console.log(`[Agent] Checking ${vault.name}...`);

      // 1. Check pending Merkl rewards for the strategy address
      const rewards = await fetchMerklRewards(
        vault.strategyAddress,
        agentkit
      );

      if (rewards.totalUsd < MIN_REWARD_USD) {
        console.log(
          `[Agent] ${vault.name}: Rewards $${rewards.totalUsd} < $${MIN_REWARD_USD}, skipping`
        );
        continue;
      }

      // 2. Build Merkl claim proof
      const claimData = await buildMerklClaimData(
        vault.strategyAddress,
        rewards
      );

      // 3. Call harvest() on the strategy contract
      const txHash = await walletClient.writeContract({
        address: vault.strategyAddress,
        abi: STRATEGY_ABI,
        functionName: "harvest",
        args: [claimData.tokens, claimData.amounts, claimData.proofs],
      });

      console.log(`[Agent] ${vault.name}: Harvest tx ${txHash}`);

      // 4. Wait for confirmation
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: txHash,
      });

      // 5. Log to Supabase
      await supabase.from("harvests").insert({
        vault_address: vault.vaultAddress,
        strategy_address: vault.strategyAddress,
        rewards_claimed: JSON.stringify(rewards.breakdown),
        rewards_compounded_usd: rewards.totalUsd,
        gas_cost: receipt.gasUsed.toString(),
        tx_hash: txHash,
        timestamp: new Date().toISOString(),
      });

      // 6. Snapshot vault state
      const sharePrice = await publicClient.readContract({
        address: vault.vaultAddress,
        abi: VAULT_ABI,
        functionName: "getPricePerFullShare",
      });

      const totalAssets = await publicClient.readContract({
        address: vault.vaultAddress,
        abi: VAULT_ABI,
        functionName: "balance",
      });

      await supabase.from("vault_snapshots").insert({
        vault_address: vault.vaultAddress,
        total_assets: totalAssets.toString(),
        share_price: sharePrice.toString(),
        apy_current: rewards.apy,
        timestamp: new Date().toISOString(),
      });

      console.log(
        `[Agent] ${vault.name}: Compounded $${rewards.totalUsd}, ` +
        `new share price: ${sharePrice}`
      );
    } catch (error) {
      console.error(`[Agent] ${vault.name}: Error:`, error);
      // Log error but continue to next vault
    }
  }
}

async function fetchMerklRewards(
  strategyAddress: string,
  agentkit: AgentKit
): Promise<MerklRewards> {
  // Use x402 micropayment for premium yield data
  const x402Header = await agentkit.signX402Payment({
    amount: "0.001", // $0.001 per API call
    recipient: "yield-data-provider.eth",
  });

  // Fetch from Merkl API
  const response = await fetch(
    `https://api.merkl.xyz/v4/users/${strategyAddress}/rewards?chainId=480`,
    {
      headers: {
        "X-402-Payment": x402Header,
      },
    }
  );

  const data = await response.json();
  return parseMerklRewards(data);
}

async function buildMerklClaimData(
  strategyAddress: string,
  rewards: MerklRewards
): Promise<ClaimData> {
  // Fetch Merkl proofs for each reward token
  const proofResponse = await fetch(
    `https://api.merkl.xyz/v4/users/${strategyAddress}/claims?chainId=480`
  );
  const proofData = await proofResponse.json();
  
  return {
    tokens: proofData.tokens,
    amounts: proofData.amounts,
    proofs: proofData.proofs,
  };
}

// Entry point
async function main() {
  console.log("[Agent] Harvest strategist starting...");
  
  // Run immediately on startup
  await runHarvestLoop();
  
  // Then run on interval
  setInterval(runHarvestLoop, HARVEST_INTERVAL_MS);
}

main().catch(console.error);
```

### 5.4 AgentKit Integration Details

AgentKit provides the agent with:

1. **Wallet management** — The agent's keeper EOA is managed via AgentKit's CDP wallet infrastructure. Private keys never touch application code.

2. **Human-backed identity** — The agent can prove it is operated by a verified entity, not an anonymous bot. This matters for:
   - Trust with the Merkl API (rate limiting)
   - x402 payment channels (payment reputation)
   - On-chain identity (the keeper address is linked to a CDP identity)

3. **x402 micropayments** — The agent pays for premium yield data feeds using x402 protocol. This demonstrates the x402 use case: an autonomous agent that needs to pay for services as it operates.

**AgentKit setup:**

```typescript
import { AgentKit } from "@coinbase/agentkit";

const agentkit = await AgentKit.from({
  cdpApiKeyId: process.env.CDP_API_KEY_ID!,
  cdpApiKeySecret: process.env.CDP_API_KEY_SECRET!,
  networkId: "worldchain-mainnet",
});

// Get the agent's wallet address (this is the keeper)
const keeperAddress = agentkit.getAddress();

// Sign transactions through AgentKit
const tx = await agentkit.sendTransaction({
  to: strategyAddress,
  data: harvestCalldata,
  gasLimit: 500000n,
});
```

### 5.5 x402 Integration

The agent uses x402 to pay for premium yield data. This is a key differentiator for the AgentKit prize.

**What the agent pays for:**
- Real-time Morpho vault APY data (beyond what the free Merkl API provides)
- Historical yield curves for strategy optimization
- Gas price predictions for optimal harvest timing

**x402 flow:**
```
Agent wants yield data
  -> Agent signs x402 payment header (SIWE signature + payment amount)
  -> Sends request with X-402-Payment header
  -> Data provider verifies payment, returns data
  -> Agent uses data to decide: harvest now, or wait?
```

**Fallback:** If x402 integration is too complex, implement manual SIWE header construction — x402 is fundamentally just a signed payment authorization. The agent signs a message saying "I authorize $0.001 to provider X for request Y" and the provider verifies the signature.

### 5.6 Agent Decision Logic

The agent is not just a dumb cron. It makes decisions:

```
IF pending_rewards_usd > MIN_HARVEST_THRESHOLD ($5)
  AND gas_cost_usd < pending_rewards_usd * 0.1  (gas < 10% of rewards)
  AND time_since_last_harvest > MIN_HARVEST_INTERVAL (1 hour)
THEN
  harvest()
  
IF vault_a_apy > vault_b_apy + REBALANCE_THRESHOLD (2%)
  AND time_since_last_rebalance > MIN_REBALANCE_INTERVAL (24 hours)
THEN
  rebalance(from: vault_b, to: vault_a)  [STRETCH GOAL]
```

### 5.7 Agent Monitoring

All agent activity is logged to Supabase and exposed via the API:

```typescript
// After each harvest
await supabase.from("harvests").insert({
  vault_address: vault.vaultAddress,
  rewards_claimed: rewardsJson,
  rewards_compounded_usd: totalUsd,
  gas_cost: gasCostWei,
  tx_hash: txHash,
  timestamp: new Date().toISOString(),
});
```

The frontend reads this table to render the `agent status` command output in the terminal.

---

## 6. Frontend -- World Mini App

### 6.1 Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 15 (App Router) |
| Scaffold | `@worldcoin/create-mini-app` |
| Styling | Tailwind CSS 4 (green-on-black terminal theme, monospace font) |
| State | React hooks (no external state library) |
| Chain interaction | viem + wagmi (bundled in MiniKit) |
| Auth | MiniKit walletAuth (SIWE) + MiniKit verify (World ID) |
| Transactions | MiniKit sendTransaction |
| Hosting | Vercel |

### 6.2 MiniKit Integration

MiniKit is the SDK for building World Mini Apps. It provides:

**walletAuth** — SIWE-based wallet authentication. Returns a signed message proving the user controls their World App wallet.

```typescript
import { MiniKit } from "@worldcoin/minikit-js";

const { finalPayload } = await MiniKit.commandsAsync.walletAuth({
  nonce: generatedNonce,
  statement: "Sign in to Harvest",
  expirationTime: new Date(Date.now() + 15 * 60 * 1000), // 15 min
});
// finalPayload contains: address, signature, message
```

**verify** — World ID verification. Returns a zero-knowledge proof that the user is a unique, verified human.

```typescript
const { finalPayload } = await MiniKit.commandsAsync.verify({
  action: "harvest-deposit",
  verification_level: "orb", // or "device"
});
// finalPayload contains: merkle_root, nullifier_hash, proof
```

**sendTransaction** — Sends transactions through the World App wallet. Supports multicall for atomic approve + deposit.

```typescript
const { finalPayload } = await MiniKit.commandsAsync.sendTransaction({
  transaction: [
    {
      address: USDC_ADDRESS,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [VAULT_ADDRESS, depositAmount],
    },
    {
      address: VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: "deposit",
      args: [depositAmount],
    },
  ],
});
```

This multicall is atomic — both approve and deposit happen in a single user tap. This is critical for UX.

<!-- Merged from claimall-spec.md -->

> **Important MiniKit sendTransaction format:** MiniKit `sendTransaction` accepts raw `{ to, data }` objects, NOT `{ abi, functionName, args }`. Always encode calldata with viem's `encodeFunctionData` first, then pass the hex string as `data`. The backend's prepare endpoints return pre-encoded calldata, so the frontend just forwards the array to MiniKit.

**Important constraints:**
- All target contracts must be whitelisted in the World Developer Portal
- Maximum transactions per batch: unknown exact limit, test with 5-10
- Each user gets 500 free (gas-sponsored) transactions per day
- Biometric confirmation is required for each batch (one Face ID / fingerprint)
- `sendTransaction` returns `userOpHash`, not a tx hash -- must poll `developer.worldcoin.org/api/v2/minikit/userop/{hash}` for the final transaction hash

### 6.3 Developer Portal Whitelisting

MiniKit sendTransaction requires the contract addresses to be whitelisted in the World Developer Portal. This must be done BEFORE demo day.

**Whitelisting checklist:**
- [ ] Register app in World Developer Portal
- [ ] Add vault contract addresses to allowed list
- [ ] Add USDC token address for approve calls
- [ ] Add WLD token address for approve calls
- [ ] Test sendTransaction on World Chain Sepolia first
- [ ] Switch to mainnet and re-whitelist

**Risk:** If whitelisting fails or takes too long, fallback to direct contract interaction via `cast` for the demo, and show the mini app UI separately.

### 6.4 Page Structure

The entire app is a single page — the terminal. There is no routing, no navigation, no separate screens.

```
app/
  layout.tsx          # Root layout, MiniKit provider, monospace font loading
  page.tsx            # The terminal — only page in the app
```

The terminal handles auth inline. On first load, if the user is not authenticated, the terminal prints a welcome message and prompts World ID verification. After verification, it drops into command mode. There is no splash screen, no redirect — everything happens inside the terminal output.

---

## 7. Authentication and Authorization

### 7.1 Auth Flow (Step by Step)

<!-- Merged from claimall-spec.md -->

```
1. User opens Harvest in World App
   -> Rendered as a Mini App inside World App
   
2. Terminal prints: "Verifying World ID..."
   -> Auto-triggers MiniKit.verify({ action: "harvest-deposit", verification_level: "orb" })
   -> World App shows biometric verification
   -> Returns: merkle_root, nullifier_hash, proof
   
3. Backend verifies the World ID proof:
   POST /api/auth/verify
   Body: { merkle_root, nullifier_hash, proof }
   -> Calls World ID smart contract or API to verify proof
   -> Stores hashed nullifier in users table (sybil prevention)
   -> Returns: { verified: true }

3a. Backend checks PROOF FRESHNESS: reject if proof is older than 5 minutes.
    Compare the proof's timestamp against server time. This prevents replay
    attacks where a captured proof is resubmitted later.
    ```typescript
    const PROOF_MAX_AGE_MS = 5 * 60 * 1000; // 5 minutes
    const proofAge = Date.now() - proofTimestamp;
    if (proofAge > PROOF_MAX_AGE_MS) {
      return new Response("Proof expired", { status: 400 });
    }
    ```

4. Wallet authentication:
   -> MiniKit.walletAuth({ nonce, statement, expirationTime })
   -> User signs SIWE message in World App
   -> Returns: address, signature, message
   
5. Backend creates session:
   POST /api/auth/session
   Body: { address, signature, message, nullifier_hash }
   -> Verifies SIWE signature
   -> Checks nullifier_hash exists in users table (verified)
   -> Creates HttpOnly session cookie (15-min TTL)
   -> Returns: { user: { address, verified: true } }

6. All subsequent API calls include session cookie
   -> Middleware checks cookie validity
   -> Extracts wallet_address from session
   -> Passes to API route handlers
```

### 7.2 Session Cookie and HMAC Nullifier Hashing

<!-- Merged from claimall-spec.md -->

```typescript
// Secure session cookie configuration
const SESSION_CONFIG = {
  name: "harvest_session",
  httpOnly: true,
  secure: true,          // HTTPS only
  sameSite: "strict",    // No cross-site
  maxAge: 15 * 60,       // 15 minutes
  path: "/",
};
```

**HMAC Nullifier Hashing:** The raw World ID nullifier hash is never stored directly. It is hashed server-side using HMAC-SHA256 with a dedicated secret, separate from the JWT secret. This ensures that even if the database is compromised, raw nullifiers cannot be recovered.

```typescript
import { createHmac } from "crypto";

function hashNullifier(nullifierHash: string): string {
  return createHmac("sha256", process.env.NULLIFIER_HMAC_SECRET!)
    .update(nullifierHash)
    .digest("hex");
}
// Env var required: NULLIFIER_HMAC_SECRET (generate with: openssl rand -base64 32)
```

**Session JWT:** The session token contains the wallet address and the HMAC'd nullifier:

```typescript
import { SignJWT, jwtVerify } from "jose";

const JWT_SECRET = new TextEncoder().encode(process.env.JWT_SECRET);

export async function createSession(walletAddress: string, nullifierHash: string) {
  const token = await new SignJWT({
    wallet: walletAddress,
    nullifier: hashNullifier(nullifierHash),
  })
    .setProtectedHeader({ alg: "HS256" })
    .setExpirationTime("15m")
    .sign(JWT_SECRET);

  cookies().set("harvest_session", token, {
    httpOnly: true,
    secure: true,
    sameSite: "strict",
    maxAge: 900,
  });
}
```

### 7.3 CSRF Protection

<!-- Merged from claimall-spec.md -->

All state-changing API routes (POST, PUT, DELETE) are protected by the session cookie with `SameSite=Strict`, which provides baseline CSRF protection by preventing the browser from sending the cookie on cross-origin requests. Combined with `httpOnly: true` and `secure: true`:

- The cookie is never readable by client-side JavaScript
- The cookie is only sent over HTTPS
- The cookie is never sent on cross-site requests (strict same-site policy)

No additional CSRF token mechanism is needed for this hackathon build. For production, add a double-submit cookie or synchronizer token pattern as defense-in-depth.

### 7.4 Per-Wallet Authorization Pattern

<!-- Merged from claimall-spec.md -->

**CRITICAL:** Every protected API route MUST verify that the session wallet matches the wallet address in the request. This prevents a user from manipulating requests to access or act on behalf of another user's wallet.

```typescript
// lib/auth.ts -- shared middleware for all protected routes
export async function requireAuth(req: Request): Promise<string> {
  const sessionCookie = cookies().get("harvest_session")?.value;
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

**Usage in every protected route:**

```typescript
const sessionWallet = await requireAuth(req);
const { wallet } = await req.json();
assertWalletMatch(sessionWallet, wallet);
```

### 7.5 On-Chain World ID Gating

After backend verification, the backend's signer EOA calls `setVerified(userAddress, true)` on the vault contract. This whitelists the user for deposits.

```typescript
// Backend signer (after World ID proof verified)
const tx = await signerWallet.writeContract({
  address: VAULT_ADDRESS,
  abi: VAULT_ABI,
  functionName: "setVerified",
  args: [userAddress, true],
});
```

This only needs to happen once per user per vault.

---

## 8. Database Schema

### 8.1 Supabase Setup

Create a new Supabase project. Enable Row Level Security (RLS) on all tables.

### 8.2 Tables

```sql
-- Users table
-- <!-- Merged from claimall-spec.md: notification dedup columns -->
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_address TEXT NOT NULL UNIQUE,
  hashed_nullifier TEXT NOT NULL UNIQUE,       -- HMAC'd nullifier for privacy
  verification_level TEXT NOT NULL DEFAULT 'orb', -- 'orb' | 'device'
  notification_enabled BOOLEAN DEFAULT FALSE,
  notification_threshold_usd DECIMAL(10, 2) DEFAULT 1.00,
  last_notified_at TIMESTAMPTZ,                -- when we last sent a notification (dedup)
  last_claimable_usd DECIMAL(10, 2),           -- USD value at time of last notification (dedup)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_wallet ON users(wallet_address);
CREATE INDEX idx_users_nullifier ON users(hashed_nullifier);
CREATE INDEX idx_users_notif ON users(notification_enabled) WHERE notification_enabled = TRUE;

-- Deposits table
CREATE TABLE deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  vault_address TEXT NOT NULL,
  amount NUMERIC NOT NULL,           -- raw amount in token decimals
  amount_usd NUMERIC,                -- USD value at time of deposit
  shares_received NUMERIC NOT NULL,  -- mooToken shares received
  tx_hash TEXT NOT NULL UNIQUE,
  block_number BIGINT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_deposits_user ON deposits(user_id);
CREATE INDEX idx_deposits_vault ON deposits(vault_address);
CREATE INDEX idx_deposits_time ON deposits(timestamp DESC);

-- Withdrawals table
CREATE TABLE withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  vault_address TEXT NOT NULL,
  shares_burned NUMERIC NOT NULL,    -- mooToken shares burned
  amount_received NUMERIC NOT NULL,  -- want token received
  amount_usd NUMERIC,               -- USD value at time of withdrawal
  tx_hash TEXT NOT NULL UNIQUE,
  block_number BIGINT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_withdrawals_user ON withdrawals(user_id);
CREATE INDEX idx_withdrawals_vault ON withdrawals(vault_address);

-- Harvests table (agent activity)
CREATE TABLE harvests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_address TEXT NOT NULL,
  strategy_address TEXT NOT NULL,
  rewards_claimed JSONB NOT NULL,     -- { "WLD": "42.5", "USDC": "0" }
  rewards_compounded_usd NUMERIC NOT NULL,
  gas_cost TEXT NOT NULL,             -- gas in wei
  gas_cost_usd NUMERIC,
  tx_hash TEXT NOT NULL UNIQUE,
  block_number BIGINT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_harvests_vault ON harvests(vault_address);
CREATE INDEX idx_harvests_time ON harvests(timestamp DESC);

-- Vault snapshots (for charting share price over time)
CREATE TABLE vault_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_address TEXT NOT NULL,
  total_assets NUMERIC NOT NULL,     -- total want token in vault + strategy
  share_price NUMERIC NOT NULL,      -- getPricePerFullShare()
  apy_current NUMERIC,               -- current APY estimate
  total_depositors INTEGER,          -- count of unique depositors
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_snapshots_vault_time ON vault_snapshots(vault_address, timestamp DESC);

-- <!-- Merged from claimall-spec.md -->
-- Notification log (for tracking open rates and dedup)
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,                 -- 'harvest_complete', 'yield_update'
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  sent_at TIMESTAMPTZ DEFAULT now(),
  opened_at TIMESTAMPTZ,             -- tracked if we get open callbacks
  deep_link TEXT
);

CREATE INDEX idx_notifications_user_sent ON notifications(user_id, sent_at);

-- Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE withdrawals ENABLE ROW LEVEL SECURITY;
ALTER TABLE harvests ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Public read for vault data (no auth needed to view vaults)
CREATE POLICY "Public read vault_snapshots" ON vault_snapshots
  FOR SELECT USING (true);

CREATE POLICY "Public read harvests" ON harvests
  FOR SELECT USING (true);

-- Authenticated read for user-specific data
-- (enforced at API layer since we use service role key)
```

### 8.3 Supabase Client

```typescript
// lib/supabase.ts
import { createClient } from "@supabase/supabase-js";

// Server-side (API routes, agent)
export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY! // Service role for server-side
);

// Client-side (frontend, read-only public data)
export const supabasePublic = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! // Anon key for client-side
);
```

<!-- Merged from claimall-spec.md -->

> **SECURITY WARNING: Supabase Key Usage**
>
> - **`SUPABASE_SERVICE_ROLE_KEY`** -- This key bypasses ALL Row Level Security policies. It MUST be used **SERVER-SIDE ONLY** (API routes, cron jobs). NEVER expose to the frontend/client. Never prefix with `NEXT_PUBLIC_`. If this key leaks, anyone can read/write all database tables.
>
> - **`NEXT_PUBLIC_SUPABASE_URL`** -- Safe to expose to the client (public URL).
>
> - **`SUPABASE_ANON_KEY`** (if used) -- ONLY key safe for client-side usage. It respects RLS policies.
>
> For the hackathon: all Supabase queries go through Next.js API routes (server-side), so only `SUPABASE_SERVICE_ROLE_KEY` is used, and it never touches the client bundle. This is safe as long as no `NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY` variable is ever created.

---

## 9. API Routes

All API routes are Next.js App Router route handlers (`app/api/*/route.ts`).

### 9.1 Auth Routes

#### POST /api/auth/verify

Verify World ID proof and create/update user record.

```typescript
// app/api/auth/verify/route.ts
import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";

export async function POST(req: NextRequest) {
  const { merkle_root, nullifier_hash, proof, verification_level } =
    await req.json();

  // Verify proof with World ID API
  const verifyRes = await fetch(
    `https://developer.worldcoin.org/api/v2/verify/${process.env.WORLD_APP_ID}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        merkle_root,
        nullifier_hash,
        proof,
        action: "harvest-deposit",
        verification_level,
      }),
    }
  );

  if (!verifyRes.ok) {
    return NextResponse.json(
      { error: "World ID verification failed" },
      { status: 401 }
    );
  }

  // Hash the nullifier for storage (privacy)
  const hashedNullifier = hashNullifier(nullifier_hash);

  // Check if user already exists (re-verification)
  const { data: existingUser } = await supabase
    .from("users")
    .select("id")
    .eq("hashed_nullifier", hashedNullifier)
    .single();

  if (!existingUser) {
    // Will be fully created when wallet auth completes
    // Store nullifier temporarily in session
  }

  return NextResponse.json({
    verified: true,
    nullifier_hash: hashedNullifier,
  });
}
```

#### POST /api/auth/session

Create session from SIWE wallet authentication.

```typescript
// app/api/auth/session/route.ts
export async function POST(req: NextRequest) {
  const { address, signature, message, nullifier_hash } = await req.json();

  // 1. Verify SIWE signature
  const isValid = await verifySiweMessage({ address, signature, message });
  if (!isValid) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }

  // 2. Upsert user record
  const { data: user } = await supabase
    .from("users")
    .upsert(
      {
        wallet_address: address.toLowerCase(),
        hashed_nullifier: nullifier_hash,
        verification_level: "orb",
      },
      { onConflict: "wallet_address" }
    )
    .select("id")
    .single();

  // 3. Create session cookie
  const session = await createSession(user!.id, address);
  const response = NextResponse.json({
    user: { address, verified: true },
  });

  response.cookies.set("harvest_session", session.token, {
    httpOnly: true,
    secure: true,
    sameSite: "strict",
    maxAge: 15 * 60, // 15 minutes
    path: "/",
  });

  // 4. Whitelist on-chain (if not already)
  await whitelistOnChain(address);

  return response;
}
```

#### GET /api/auth/session

Check current session validity.

```typescript
export async function GET(req: NextRequest) {
  const session = await getSession(req);
  if (!session) {
    return NextResponse.json({ authenticated: false }, { status: 401 });
  }
  return NextResponse.json({
    authenticated: true,
    user: { address: session.address, verified: true },
  });
}
```

#### POST /api/auth/logout

Destroy session.

```typescript
export async function POST(req: NextRequest) {
  const response = NextResponse.json({ success: true });
  response.cookies.delete("harvest_session");
  return response;
}
```

### 9.2 Vault Routes

#### GET /api/vaults

List all available vaults with current stats.

```typescript
// app/api/vaults/route.ts
export async function GET() {
  // Fetch latest snapshot for each vault
  const { data: snapshots } = await supabase
    .from("vault_snapshots")
    .select("*")
    .order("timestamp", { ascending: false });

  // Deduplicate to latest per vault
  const latestByVault = new Map();
  for (const snap of snapshots || []) {
    if (!latestByVault.has(snap.vault_address)) {
      latestByVault.set(snap.vault_address, snap);
    }
  }

  const vaults = VAULT_CONFIGS.map((config) => {
    const snapshot = latestByVault.get(config.address);
    return {
      ...config,
      totalAssets: snapshot?.total_assets || "0",
      sharePrice: snapshot?.share_price || "1000000000000000000",
      apyCurrent: snapshot?.apy_current || config.baseApy,
      totalDepositors: snapshot?.total_depositors || 0,
    };
  });

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
      "wantToken": "USDC",
      "wantTokenAddress": "0x...",
      "morphoVault": "0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B",
      "morphoVaultName": "Re7 USDC",
      "totalAssets": "125000000000",
      "sharePrice": "1002500000000000000",
      "apyCurrent": 4.15,
      "totalDepositors": 47,
      "baseApy": 4.15
    }
  ]
}
```

#### GET /api/vaults/[address]/history

Vault snapshot history for charting.

```typescript
// app/api/vaults/[address]/history/route.ts
export async function GET(
  req: NextRequest,
  { params }: { params: { address: string } }
) {
  const { data: snapshots } = await supabase
    .from("vault_snapshots")
    .select("share_price, total_assets, apy_current, timestamp")
    .eq("vault_address", params.address)
    .order("timestamp", { ascending: true })
    .limit(168); // 7 days * 24 hours (hourly snapshots)

  return NextResponse.json({ snapshots });
}
```

#### GET /api/vaults/[address]/harvests

Harvest history for a specific vault.

```typescript
// app/api/vaults/[address]/harvests/route.ts
export async function GET(
  req: NextRequest,
  { params }: { params: { address: string } }
) {
  const { data: harvests } = await supabase
    .from("harvests")
    .select("*")
    .eq("vault_address", params.address)
    .order("timestamp", { ascending: false })
    .limit(20);

  return NextResponse.json({ harvests });
}
```

### 9.3 User Routes

#### GET /api/user/deposits

Get current user's deposit positions.

```typescript
// app/api/user/deposits/route.ts
export async function GET(req: NextRequest) {
  const session = await requireSession(req);

  const { data: user } = await supabase
    .from("users")
    .select("id")
    .eq("wallet_address", session.address.toLowerCase())
    .single();

  if (!user) {
    return NextResponse.json({ deposits: [] });
  }

  // Get all deposits and withdrawals to compute net position
  const { data: deposits } = await supabase
    .from("deposits")
    .select("*")
    .eq("user_id", user.id)
    .order("timestamp", { ascending: false });

  const { data: withdrawals } = await supabase
    .from("withdrawals")
    .select("*")
    .eq("user_id", user.id)
    .order("timestamp", { ascending: false });

  return NextResponse.json({ deposits, withdrawals });
}
```

#### POST /api/user/deposits

Record a new deposit (called after on-chain tx confirms).

```typescript
// app/api/user/deposits/route.ts
export async function POST(req: NextRequest) {
  const session = await requireSession(req);
  const { vault_address, amount, shares_received, tx_hash } = await req.json();

  const { data: user } = await supabase
    .from("users")
    .select("id")
    .eq("wallet_address", session.address.toLowerCase())
    .single();

  const { data, error } = await supabase.from("deposits").insert({
    user_id: user!.id,
    vault_address,
    amount,
    shares_received,
    tx_hash,
    timestamp: new Date().toISOString(),
  });

  return NextResponse.json({ success: !error, data });
}
```

#### POST /api/user/withdrawals

Record a new withdrawal.

```typescript
export async function POST(req: NextRequest) {
  const session = await requireSession(req);
  const { vault_address, shares_burned, amount_received, tx_hash } =
    await req.json();

  const { data: user } = await supabase
    .from("users")
    .select("id")
    .eq("wallet_address", session.address.toLowerCase())
    .single();

  const { data, error } = await supabase.from("withdrawals").insert({
    user_id: user!.id,
    vault_address,
    shares_burned,
    amount_received,
    tx_hash,
    timestamp: new Date().toISOString(),
  });

  return NextResponse.json({ success: !error, data });
}
```

### 9.4 Agent Routes

#### GET /api/agent/activity

Public endpoint: recent agent harvest activity across all vaults.

```typescript
// app/api/agent/activity/route.ts
export async function GET() {
  const { data: harvests } = await supabase
    .from("harvests")
    .select("*")
    .order("timestamp", { ascending: false })
    .limit(10);

  return NextResponse.json({ harvests });
}
```

### 9.5 Notification Routes

<!-- Merged from claimall-spec.md -->

#### POST /api/notifications/enable

Enables push notifications for the authenticated user.

| Aspect | Detail |
|--------|--------|
| Auth required | Yes (session cookie) |
| Request body | None (wallet from session) |
| Success (200) | `{ enabled: true }` |
| Error (401) | `{ error: "Not authenticated", code: "UNAUTHORIZED" }` |
| Error (500) | `{ error: "Failed to update notification preferences", code: "DB_ERROR" }` |

**IMPORTANT:** Do NOT accept a wallet address from the request body -- use the session wallet exclusively to prevent subscribing other users.

```typescript
// /api/notifications/enable/route.ts
export async function POST(req: Request) {
  const sessionWallet = await requireAuth(req);

  await supabase
    .from("users")
    .update({ notification_enabled: true })
    .eq("wallet_address", sessionWallet);

  return Response.json({ enabled: true });
}
```

#### GET /api/cron/check-rewards

Cron-triggered endpoint that checks vault yields and sends notifications.

| Aspect | Detail |
|--------|--------|
| Auth required | `Authorization: Bearer {CRON_SECRET}` header |
| Request body | None |
| Success (200) | `{ checked: number, notified: number }` |
| Error (401) | `{ error: "Unauthorized", code: "INVALID_CRON_SECRET" }` |
| Error (500) | `{ error: "Cron job failed", code: "CRON_ERROR" }` |

### 9.6 Push Notification System (Stretch Goal)

<!-- Merged from claimall-spec.md -->

#### Architecture

```
+------------------+     +-------------------+     +------------------+
|                  |     |                   |     |                  |
| Cron (Vercel)    |---->| Check yields      |---->| World Dev API    |
| Every 4 hours    |     | For all users     |     | Send notif       |
|                  |     |                   |     |                  |
+------------------+     +-------------------+     +------------------+
```

#### Notification API

```
POST https://developer.worldcoin.org/api/v2/minikit/send-notification

Headers:
  Authorization: Bearer {APP_SECRET}
  Content-Type: application/json

Body:
{
  "app_id": "app_harvest_xyz",
  "wallets": ["0x..."],
  "title": "Yield compounded!",
  "message": "The agent just compounded $42.50 for all depositors",
  "mini_app_path": "/"
}
```

#### Notification Deduplication

To avoid spamming users, track `last_notified_at` and `last_claimable_usd` on the users table.

**Rule:** Only send a notification if the claimable/compounded amount has INCREASED since the last notification.

- User gets notified when a harvest compounds $50.
- Next cron cycle: no new harvest. No notification.
- Agent harvests again: now $35 more compounded. New notification sent.

#### Notification Quality Rules

World's notification system has a quality threshold:
- **Minimum 10% open rate required** -- if open rate drops below 10%, notifications are paused for 1 week
- Max 1 notification per user per 4-hour cycle
- Do NOT notify for trivial amounts (respect the threshold setting)
- Deduplication via `last_claimable_usd` prevents re-notifying for the same amount

#### MiniKit Notification Permission

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

#### Cron Job Implementation

```typescript
// /api/cron/check-rewards.ts
export async function GET(req: Request) {
  const authHeader = req.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { data: users } = await supabase
    .from("users")
    .select("*")
    .eq("notification_enabled", true);

  let notifiedCount = 0;

  for (const user of users) {
    try {
      // Check if there's been a new harvest since last notification
      const shouldNotify =
        totalUsd >= user.notification_threshold_usd &&
        (user.last_claimable_usd === null || totalUsd > user.last_claimable_usd);

      if (shouldNotify) {
        await sendNotification(user, totalUsd);

        await supabase
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

  return Response.json({ checked: users.length, notified: notifiedCount });
}
```

#### Vercel Cron Configuration

```json
// vercel.json
{
  "crons": [
    {
      "path": "/api/cron/check-rewards",
      "schedule": "0 */4 * * *"
    }
  ]
}
```

### 9.7 Error Handling Summary

<!-- Merged from claimall-spec.md -->

| Scenario | Behavior | HTTP Status |
|----------|----------|-------------|
| Merkl API timeout (5s) | Return cached data with `cached: true` | 200 |
| Merkl API down | Return cached data or empty with error message | 200 (degraded) |
| Invalid session / expired JWT | Reject request | 401 |
| Wallet address mismatch (body vs session) | Reject request | 403 |
| Transaction preparation fails (encoding, proofs) | Descriptive error | 500 |
| Supabase unreachable | Descriptive error, log to console | 500 |
| Agent/LLM timeout | Return timeout error, frontend shows fallback | 504 |
| No claimable rewards on harvest | Informative error | 400 |
| Cron secret mismatch | Reject request | 401 |

---

## 10. Terminal Interface and Commands

### 10.1 Overview

The entire app is a single terminal screen. There is no navigation, no separate screens, no routing. Users type commands (or tap shortcut buttons on mobile) and see responses rendered as monospace terminal output. This is faster to build, more memorable to demo, and more engaging to watch.

### 10.2 ASCII Mockup

```
+-------------------------------------------+
|  HARVEST v1.0       World Chain (480)      |
|  =========================================|
|                                            |
|  > Initializing...                         |
|  > Connected: 0x1a2B...9fC4               |
|  > World ID: VERIFIED (orb)               |
|  > Session active. Type 'help' to begin.  |
|                                            |
|  > vaults                                  |
|                                            |
|  AVAILABLE VAULTS                          |
|  ┌────────────┬────────┬──────────┐       |
|  │ Vault      │ APY    │ TVL      │       |
|  ├────────────┼────────┼──────────┤       |
|  │ Re7 USDC   │ 4.15%  │ $125.0K  │       |
|  │ Re7 WLD    │ 2.58%  │ $89.2K   │       |
|  └────────────┴────────┴──────────┘       |
|                                            |
|  > deposit 50 usdc                         |
|                                            |
|  DEPOSIT 50.00 USDC -> Re7 USDC Vault     |
|  Shares: ~49.88 mooHarvestUSDC             |
|  Confirm in World App...                   |
|  TX: 0xabc...def (confirmed, block 12345) |
|  OK. Deposited 50.00 USDC.                |
|                                            |
|  > _                                       |
|                                            |
+-------------------------------------------+
| [portfolio] [vaults] [deposit] [withdraw] |
| [agent status]                             |
+-------------------------------------------+
| > _                                        |
+-------------------------------------------+
```

**Layout anatomy:**
- **Top bar:** App name + chain identifier (static)
- **Scrollable output area:** All command responses and agent activity render here. Green monospace text on black background. Auto-scrolls to bottom on new output.
- **Shortcut buttons row:** Tappable buttons above the input for mobile UX. Each button inserts its command into the input. For `deposit` and `withdraw`, tapping the button inserts the command prefix and the user types the amount/token.
- **Command input:** Fixed at the bottom. Single-line text input with a `>` prompt character. Submit on Enter (or tap the send button on mobile).

### 10.3 Terminal Commands

| Command | Action | Auth Required |
|---|---|---|
| `portfolio` | Show user's deposits, current values, earnings, APY per vault | Yes |
| `vaults` | List available vaults with APY, TVL, depositor count | No |
| `deposit <amount> <token>` | Deposit into the best vault for that token (triggers MiniKit sendTransaction with atomic approve + deposit) | Yes |
| `withdraw <amount> <token>` | Withdraw from the vault for that token (triggers MiniKit sendTransaction) | Yes |
| `agent status` | Show recent agent activity: last 5 harvests, amounts compounded, gas costs | No |
| `agent harvest` | Trigger a manual harvest via API (for demo purposes) | Yes |
| `help` | List all available commands with descriptions | No |

### 10.4 Command Output Formats

**`help` output:**
```
HARVEST COMMANDS
  portfolio              Show your deposits, values, earnings
  vaults                 List available vaults (APY, TVL)
  deposit <amt> <token>  Deposit into vault (e.g. deposit 50 usdc)
  withdraw <amt> <token> Withdraw from vault (e.g. withdraw 25 usdc)
  agent status           Show recent agent harvests
  agent harvest          Trigger manual harvest (demo)
  help                   Show this message
```

**`portfolio` output:**
```
YOUR PORTFOLIO
  Total Value:     $1,250.40
  Total Earnings:  +$12.80

  ┌────────────┬────────────┬──────────┬────────┐
  │ Vault      │ Deposited  │ Value    │ Earned │
  ├────────────┼────────────┼──────────┼────────┤
  │ Re7 USDC   │ 500.00     │ $503.20  │ +$3.20 │
  │ Re7 WLD    │ 300.00     │ $747.20  │ +$9.60 │
  └────────────┴────────────┴──────────┴────────┘
```

**`vaults` output:**
```
AVAILABLE VAULTS
  ┌────────────┬────────┬──────────┬─────────────┐
  │ Vault      │ APY    │ TVL      │ Depositors  │
  ├────────────┼────────┼──────────┼─────────────┤
  │ Re7 USDC   │ 4.15%  │ $125.0K  │ 47          │
  │ Re7 WLD    │ 2.58%  │ $89.2K   │ 23          │
  └────────────┴────────┴──────────┴─────────────┘
```

**`deposit 50 usdc` output:**
```
DEPOSIT 50.00 USDC -> Re7 USDC Vault
  Estimated shares: ~49.88 mooHarvestUSDC
  Estimated annual yield: ~$2.07 at current APY
  Confirm in World App...
  TX: 0xabc...def (confirmed, block 12345)
  OK. Deposited 50.00 USDC. Shares received: 49.88
```

**`withdraw 25 usdc` output:**
```
WITHDRAW 25 shares from Re7 USDC Vault
  Estimated receive: ~25.12 USDC
  That includes +$0.12 in auto-compounded yield.
  Confirm in World App...
  TX: 0xfed...cba (confirmed, block 12350)
  OK. Withdrew 25.12 USDC.
```

**`agent status` output:**
```
AGENT STATUS
  Mode: Autonomous | Interval: 4h | Keeper: 0x7B3...
  Last harvest: 2h ago

  RECENT HARVESTS
  ┌─────────────────┬─────────────┬──────────┬──────┐
  │ Time            │ Vault       │ Claimed  │ Gas  │
  ├─────────────────┼─────────────┼──────────┼──────┤
  │ Apr 3, 2:00 PM  │ Re7 USDC    │ 42 WLD   │ $0.04│
  │ Apr 3, 10:00 AM │ Re7 WLD     │ 28 WLD   │ $0.03│
  │ Apr 2, 6:00 PM  │ Re7 USDC    │ 35 WLD   │ $0.04│
  └─────────────────┴─────────────┴──────────┴──────┘
  Total compounded (24h): $95.40 for 70 depositors
```

**`agent harvest` output:**
```
MANUAL HARVEST TRIGGERED
  Checking pending rewards...
  Re7 USDC: 18.5 WLD ($16.65) pending
  Claiming from Merkl distributor...
  Swapping 18.5 WLD -> 16.61 USDC via Uniswap V3...
  Redepositing 16.61 USDC into MetaMorpho vault...
  TX: 0x123...789 (confirmed, block 12360)
  OK. Compounded $16.61 for 47 depositors. Share price updated.
```

### 10.5 Auth Flow in Terminal

On first load (no session), the terminal prints:

```
HARVEST - The first yield aggregator on World Chain
====================================================

Deposit tokens. The AI agent auto-compounds your yield.
Only verified humans. No bots. No sybils.

Verifying World ID...
> World App biometric verification (orb)
> VERIFIED. Nullifier stored.

Connecting wallet...
> SIWE signature requested.
> Connected: 0x1a2B...9fC4
> Session active (15 min TTL).

Type 'help' to see available commands.
> _
```

If the user is a returning user with a valid session, skip directly to:

```
HARVEST v1.0
> Reconnected: 0x1a2B...9fC4
> World ID: VERIFIED
> Type 'help' to begin.
> _
```

### 10.6 Mobile UX: Tappable Shortcut Buttons

The tappable shortcut buttons above the command input solve the "typing on phone" problem. The buttons are:

- **`portfolio`** -- Inserts `portfolio` and auto-submits
- **`vaults`** -- Inserts `vaults` and auto-submits
- **`deposit`** -- Inserts `deposit ` (with trailing space) into the input. The user then types the amount and token (e.g., `50 usdc`). On mobile, a simple numeric prompt could appear instead.
- **`withdraw`** -- Same pattern as deposit: inserts `withdraw ` and waits for amount/token.
- **`agent status`** -- Inserts `agent status` and auto-submits

For `deposit` and `withdraw`, if the user taps the button without typing arguments, the terminal prompts inline:

```
> deposit
  Amount? _
> 50
  Token? (usdc / wld) _
> usdc
  DEPOSIT 50.00 USDC -> Re7 USDC Vault...
```

This guided prompt flow means users never have to remember command syntax on mobile.

---

## 11. Environment Variables

### 11.1 Frontend (.env.local)

```bash
# ── World / MiniKit ──────────────────────────────────
NEXT_PUBLIC_WORLD_APP_ID=app_harvest_xyz           # From World Developer Portal
NEXT_PUBLIC_WORLD_ACTION_ID=harvest-deposit         # World ID action identifier
WORLD_APP_SECRET=sk_...                             # Server-side World ID secret

# ── Supabase ─────────────────────────────────────────
NEXT_PUBLIC_SUPABASE_URL=https://xyz.supabase.co    # Supabase project URL
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...                # Supabase anonymous (public) key
SUPABASE_SERVICE_ROLE_KEY=eyJ...                    # Supabase service role (server only)

# ── Chain / RPC ──────────────────────────────────────
NEXT_PUBLIC_CHAIN_ID=480                            # World Chain mainnet
NEXT_PUBLIC_RPC_URL=https://worldchain-mainnet.g.alchemy.com/v2/KEY
                                                    # or Infura, QuickNode, etc.

# ── Contract Addresses (set after deployment) ───────
NEXT_PUBLIC_USDC_VAULT_ADDRESS=0x...                # Deployed BeefyVaultV7 for USDC
NEXT_PUBLIC_WLD_VAULT_ADDRESS=0x...                 # Deployed BeefyVaultV7 for WLD
NEXT_PUBLIC_USDC_TOKEN_ADDRESS=0x...                # USDC.e on World Chain
NEXT_PUBLIC_WLD_TOKEN_ADDRESS=0x2cFc85d8E48F8EAB294be644d9E25C3030863003

# ── Backend Signer ───────────────────────────────────
SIGNER_PRIVATE_KEY=0x...                            # EOA that calls setVerified()
                                                    # NEVER expose client-side

# ── Session ──────────────────────────────────────────
SESSION_SECRET=random-32-byte-hex-string            # For signing session cookies
NULLIFIER_HMAC_SECRET=random-32-byte-string          # For HMAC'ing nullifier hashes (openssl rand -base64 32)
```

### 11.2 Agent (.env)

```bash
# ── AgentKit / CDP ───────────────────────────────────
CDP_API_KEY_ID=org_...                              # Coinbase Developer Platform key ID
CDP_API_KEY_SECRET=-----BEGIN EC PRIVATE KEY-----   # CDP key secret (multiline)

# ── Chain / RPC ──────────────────────────────────────
WORLD_CHAIN_RPC_URL=https://worldchain-mainnet.g.alchemy.com/v2/KEY
CHAIN_ID=480

# ── Contract Addresses ──────────────────────────────
USDC_VAULT_ADDRESS=0x...
USDC_STRATEGY_ADDRESS=0x...
WLD_VAULT_ADDRESS=0x...
WLD_STRATEGY_ADDRESS=0x...
MERKL_DISTRIBUTOR_ADDRESS=0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae
UNISWAP_ROUTER_ADDRESS=0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6
WLD_TOKEN_ADDRESS=0x2cFc85d8E48F8EAB294be644d9E25C3030863003

# ── Supabase ─────────────────────────────────────────
SUPABASE_URL=https://xyz.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...

# ── Agent Config ─────────────────────────────────────
HARVEST_INTERVAL_MS=14400000                        # 4 hours in milliseconds
MIN_REWARD_USD=5                                    # Min reward threshold for harvest
MAX_GAS_GWEI=50                                     # Max gas price to execute harvest

# ── Cron ──────────────────────────────────────────────
CRON_SECRET=random-32-byte-string                    # Vercel cron auth (openssl rand -base64 32)

# ── x402 ─────────────────────────────────────────────
X402_PROVIDER_URL=https://yield-data.example.com    # Premium yield data API
X402_MAX_PAYMENT_USD=0.01                           # Max per-request payment
```

### 11.3 Contracts (.env)

```bash
# ── Foundry Deployment ───────────────────────────────
DEPLOYER_PRIVATE_KEY=0x...                          # Deployer EOA private key
KEEPER_ADDRESS=0x...                                # Agent's keeper EOA address
SIGNER_ADDRESS=0x...                                # Backend signer for setVerified()
WORLD_CHAIN_RPC_URL=https://worldchain-mainnet.g.alchemy.com/v2/KEY
ETHERSCAN_API_KEY=...                               # For contract verification (if supported)
```

---

## 12. Repository Structure

```
harvest/
├── README.md
├── .gitignore
├── .env.example
│
├── contracts/                        # Foundry project
│   ├── foundry.toml
│   ├── .env
│   ├── lib/
│   │   ├── forge-std/
│   │   ├── openzeppelin-contracts/
│   │   └── solmate/
│   ├── src/
│   │   ├── vaults/
│   │   │   ├── BeefyVaultV7.sol       # User-facing vault (forked)
│   │   │   └── BeefyVaultV7Factory.sol # Vault factory (forked)
│   │   ├── strategies/
│   │   │   ├── StrategyMorpho.sol     # Core strategy (forked + modified)
│   │   │   └── StrategyFactory.sol    # Strategy factory (forked)
│   │   ├── infra/
│   │   │   ├── BeefySwapper.sol       # Simplified swap router
│   │   │   └── BeefyOracle.sol        # Price oracle (optional)
│   │   └── interfaces/
│   │       ├── IMetaMorpho.sol        # MetaMorpho ERC-4626 interface
│   │       ├── IMerklDistributor.sol  # Merkl claim interface
│   │       ├── ISwapRouter02.sol      # Uniswap V3 router interface
│   │       └── IWorldID.sol           # World ID verifier interface
│   ├── test/
│   │   ├── HarvestVault.t.sol         # Core vault tests
│   │   ├── StrategyMorpho.t.sol       # Strategy tests
│   │   └── Integration.t.sol          # End-to-end fork tests
│   └── script/
│       ├── Deploy.s.sol               # Main deployment script
│       └── SeedData.s.sol             # Seed demo data (deposits, harvests)
│
├── app/                               # Next.js 15 App Router (Mini App)
│   ├── next.config.ts
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   ├── package.json
│   ├── .env.local
│   ├── public/
│   │   ├── harvest-logo.svg
│   │   └── favicon.ico
│   ├── src/
│   │   ├── app/
│   │   │   ├── layout.tsx             # Root layout, MiniKit provider, monospace font
│   │   │   ├── page.tsx               # The terminal — only page in the app
│   │   │   ├── providers.tsx          # MiniKit, wagmi, query providers
│   │   │   ├── globals.css            # Green-on-black terminal theme
│   │   │   └── api/
│   │   │       ├── auth/
│   │   │       │   ├── verify/
│   │   │       │   │   └── route.ts   # World ID proof verification
│   │   │       │   ├── session/
│   │   │       │   │   └── route.ts   # SIWE session create/check
│   │   │       │   └── logout/
│   │   │       │       └── route.ts   # Session destroy
│   │   │       ├── vaults/
│   │   │       │   ├── route.ts       # List all vaults
│   │   │       │   └── [address]/
│   │   │       │       ├── history/
│   │   │       │       │   └── route.ts   # Vault snapshot history
│   │   │       │       └── harvests/
│   │   │       │           └── route.ts   # Vault harvest history
│   │   │       ├── user/
│   │   │       │   ├── deposits/
│   │   │       │   │   └── route.ts   # User deposit positions
│   │   │       │   └── withdrawals/
│   │   │       │       └── route.ts   # User withdrawal history
│   │   │       └── agent/
│   │   │           ├── activity/
│   │   │           │   └── route.ts   # Agent activity feed
│   │   │           └── harvest/
│   │   │               └── route.ts   # Manual harvest trigger (demo)
│   │   ├── components/
│   │   │   ├── Terminal.tsx           # Main terminal component (output + input + shortcuts)
│   │   │   ├── TerminalOutput.tsx     # Scrollable output area (green-on-black)
│   │   │   └── CommandInput.tsx       # Input field + tappable shortcut buttons
│   │   └── lib/
│   │       ├── supabase.ts            # Supabase client setup
│   │       ├── session.ts             # Session cookie helpers
│   │       ├── contracts.ts           # Contract addresses + ABIs
│   │       ├── vaults.ts              # Vault configuration constants
│   │       ├── format.ts              # Number/address formatting helpers
│   │       ├── commands/              # One file per command handler
│   │       │   ├── portfolio.ts       # portfolio command — fetch + format positions
│   │       │   ├── vaults.ts          # vaults command — fetch + format vault list
│   │       │   ├── deposit.ts         # deposit command — validate, trigger MiniKit tx
│   │       │   ├── withdraw.ts        # withdraw command — validate, trigger MiniKit tx
│   │       │   ├── agent.ts           # agent status / agent harvest commands
│   │       │   └── help.ts            # help command — print command list
│   │       └── hooks/
│   │           ├── useTerminal.ts     # Terminal state: history, output lines, dispatch
│   │           ├── useVaults.ts       # Fetch vault data
│   │           ├── useUserPosition.ts # Fetch user positions
│   │           └── useAgentActivity.ts # Fetch agent activity
│   └── abis/
│       ├── BeefyVaultV7.json          # Vault ABI
│       ├── StrategyMorpho.json        # Strategy ABI
│       └── ERC20.json                 # Standard ERC20 ABI
│
├── agent/                             # AI Strategist Agent
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env
│   ├── src/
│   │   ├── index.ts                   # Entry point, cron setup
│   │   ├── strategist.ts             # Main harvest loop
│   │   ├── merkl.ts                  # Merkl API client (fetch rewards, proofs)
│   │   ├── morpho.ts                 # Morpho API client (fetch APYs)
│   │   ├── agentkit.ts              # AgentKit setup and helpers
│   │   ├── x402.ts                  # x402 payment header construction
│   │   ├── contracts.ts             # Contract interaction helpers (viem)
│   │   ├── db.ts                    # Supabase client
│   │   ├── config.ts                # Vault configs, addresses, thresholds
│   │   └── types.ts                 # TypeScript type definitions
│   └── Dockerfile                    # For Railway/Render deployment
│
├── supabase/                          # Supabase config
│   ├── config.toml
│   └── migrations/
│       └── 001_initial_schema.sql     # Database schema (from Section 8)
│
└── docs/                              # Internal docs (not user-facing)
    └── harvest-v2-spec.md             # This document
```

---

## 13. Deployment

### 13.1 Contract Deployment (Foundry)

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and setup
cd contracts
forge install

# Build
forge build

# Test on fork
forge test --fork-url $WORLD_CHAIN_RPC_URL -vvv

# Deploy to World Chain Sepolia (testnet)
forge script script/Deploy.s.sol:DeployHarvest \
  --rpc-url $WORLD_CHAIN_SEPOLIA_RPC \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --verify

# Deploy to World Chain mainnet
forge script script/Deploy.s.sol:DeployHarvest \
  --rpc-url $WORLD_CHAIN_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --verify
```

### 13.2 Frontend Deployment (Vercel)

```bash
# From the app/ directory
cd app

# Install
npm install

# Dev
npm run dev

# Deploy to Vercel
vercel --prod
```

**Vercel configuration:**
- Framework: Next.js
- Root directory: `app/`
- Node version: 20
- Environment variables: All from Section 11.1

**Vercel-specific settings:**
```json
// vercel.json (in app/ directory)
{
  "framework": "nextjs",
  "buildCommand": "next build",
  "outputDirectory": ".next"
}
```

### 13.3 Agent Deployment (Railway)

```bash
# From the agent/ directory
cd agent

# Build
npm run build

# Test locally
npm start

# Deploy to Railway
railway up
```

**Railway configuration:**
- Dockerfile-based deployment
- Environment variables: All from Section 11.2
- Health check: HTTP GET /health (add a simple health endpoint)
- Restart policy: Always

**Agent Dockerfile:**

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY dist/ ./dist/
CMD ["node", "dist/index.js"]
```

### 13.4 Supabase Setup

```bash
# Install Supabase CLI
npm install -g supabase

# Login
supabase login

# Link to project
supabase link --project-ref YOUR_PROJECT_REF

# Run migrations
supabase db push

# Verify
supabase db diff
```

### 13.5 World Developer Portal Setup

1. Go to https://developer.worldcoin.org
2. Create a new app: "Harvest"
3. Set app type: "Mini App"
4. Configure:
   - Action: "harvest-deposit" (for World ID verification)
   - Verification level: "Orb" (recommended) or "Device"
   - Allowed contract addresses: Add all deployed vault + token addresses
   - Callback URL: Your Vercel deployment URL
5. Copy App ID and Secret to environment variables

---

## 14. Build Schedule

### 36-Hour Hackathon Timeline

All times are local. Team of 3-4 people.

**Time allocation (estimated productive hours):**

| Role | Hours | Notes |
|------|-------|-------|
| Contracts | 12-14h | Unchanged from prior plan |
| Frontend (Terminal UI) | 4-5h | Reduced from 8-10h — terminal is one component, no routing, no multi-screen layout |
| Backend / Agent | 12-14h | Gains 3-5h reallocated from frontend savings — use for AgentKit polish, x402 integration, agent decision logic |
| Integration + Demo | 4-6h | Unchanged |

The terminal interface eliminates page routing, navigation components, vault detail screens, deposit/withdraw form screens, and share price charts. The entire frontend is three components (`Terminal.tsx`, `TerminalOutput.tsx`, `CommandInput.tsx`) plus command handler files. This frees substantial time for contracts and agent work.

#### FRIDAY, APRIL 3

**9:00 - 9:30 PM | Team Sync (All)**
- Review this spec together
- Assign roles: Contracts, Frontend, Backend/Agent
- Set up shared repo, Discord channel, env vars

**9:30 - 11:00 PM | Scaffolding (Parallel)**

| Person | Task |
|--------|------|
| Contracts | `forge init contracts`, fork Beefy contracts, add interfaces |
| Frontend | `npx @worldcoin/create-mini-app app`, setup Tailwind with green-on-black terminal theme, load monospace font |
| Backend | Create Supabase project, run migrations, scaffold agent package |

**11:00 PM - 2:00 AM | Core Build Phase 1 (Parallel)**

| Person | Task |
|--------|------|
| Contracts | Strip Beefy contracts: remove governance, treasury, timelocks. Configure StrategyMorpho for World Chain Morpho vaults. Simplify BeefySwapper. Add World ID gate to vault. Write core tests. |
| Frontend | Build Terminal.tsx, TerminalOutput.tsx, CommandInput.tsx. Build auth flow inline in terminal (World ID verify, SIWE wallet auth). Build command dispatcher + `help` and `vaults` commands. Build API route stubs. |
| Backend | Build Merkl API client (fetch rewards, fetch proofs). Build agent harvest loop skeleton. Test Merkl API responses with real World Chain data. |

#### SATURDAY, APRIL 4

**2:00 - 5:00 AM | Sleep** (or continue if energized)

**9:00 AM - 1:00 PM | Core Build Phase 2 (Parallel)**

| Person | Task |
|--------|------|
| Contracts | Deploy to World Chain Sepolia. Test deposit/withdraw with cast. Whitelist contracts in Developer Portal. Fix any deployment issues. |
| Frontend | Build remaining command handlers: `portfolio`, `deposit`, `withdraw`, `agent status`, `agent harvest`. Wire commands to API routes. Add tappable shortcut buttons for mobile. |
| Backend | Complete agent harvest loop: fetch Merkl -> build claim data -> call harvest() on contract -> log to Supabase. Test with deployed Sepolia contracts. Set up AgentKit credentials. |

**1:00 - 5:00 PM | Integration Phase (All)**

Primary focus: **End-to-end flow must work.**

| Task | Owner |
|------|-------|
| Connect `deposit` / `withdraw` commands to MiniKit sendTransaction | Frontend + Contracts |
| Wire terminal commands to real API data (not mocks) | Frontend + Backend |
| Test: deposit -> agent harvests -> share price increases -> withdraw more than deposited | All |
| AgentKit integration: agent uses AgentKit wallet, signs x402 headers | Backend |

The end-to-end flow is the demo. If this works, everything else is polish.

**5:00 - 8:00 PM | Polish Phase (Parallel)**

| Person | Task |
|--------|------|
| Contracts | Deploy to World Chain mainnet (if Sepolia works). Seed demo data: pre-deposit funds, trigger several harvests so there is history. |
| Frontend | Terminal polish: typing animation on output, auto-scroll, error messages for bad commands, loading indicators (e.g., `Confirming...` with dots). Terminal startup sequence animation. |
| Backend | Ensure agent runs reliably. Handle edge cases (zero rewards, failed tx, gas spikes). Deploy agent to Railway. |

**8:00 - 11:00 PM | Demo Prep (All)**

- Record backup demo video (screen recording of typing commands in terminal)
- Write demo script on index cards (list exact commands to type)
- Practice demo 3 times end-to-end — practice typing the commands at a natural pace
- Test on actual World App (not just browser)
- Prepare fallback plan if live demo fails

#### SUNDAY, APRIL 5

**5:00 - 9:00 AM | Final Testing (All)**

- Full end-to-end test on mainnet
- Fix any last bugs
- Verify agent is running and has harvested at least once
- Check Supabase has correct data for terminal commands
- Submit project
- Final demo practice

---

## 15. Demo Script

### 3-Minute Demo

#### [0:00 - 0:30] THE PROBLEM

> "There's $42 million in DeFi on World Chain. Users deposit into Morpho vaults and earn yield. But rewards pile up unclaimed in Merkl. Nobody auto-compounds. There's no Beefy, no Yearn — nothing on World Chain.
>
> If you're earning yield on World Chain today, you're leaving money on the table."

#### [0:30 - 1:00] THE SOLUTION

> "Harvest is the first yield aggregator on World Chain. You deposit. Our AI agent does the rest — claiming rewards, compounding them back into your position, finding the best yields.
>
> One agent transaction replaces thousands of individual claims. Your yield earns yield, automatically."

#### [1:00 - 2:30] LIVE DEMO

Open Harvest in World App on phone. Show on projector/screen. The presenter TYPES commands live in the terminal.

> "Let me show you. I open Harvest in World App..."

1. **Auth sequence runs automatically** — Terminal prints World ID verification, wallet connection
   > "First, it verifies I'm human. World ID prevents bots from farming the vault. Connected."

2. **Type `vaults`** — See available vaults with APY and TVL
   > "Let me see what vaults are available."
   > Type: `vaults`
   > Terminal prints the vault table: Re7 USDC at 4.15% APY, $125K TVL.
   > "Two vaults live. The USDC vault is earning 4.15% APY with 47 depositors."

3. **Type `deposit 50 usdc`** — Watch the deposit flow in terminal output
   > "I'll deposit 50 USDC. Watch."
   > Type: `deposit 50 usdc`
   > Terminal prints: "DEPOSIT 50.00 USDC -> Re7 USDC Vault... Confirm in World App..."
   > Confirm MiniKit sendTransaction on phone (atomic approve + deposit)
   > Terminal prints: "TX confirmed. OK. Deposited 50.00 USDC."
   > "That's an atomic approve-and-deposit. One confirmation. No separate approval step."

4. **Type `portfolio`** — See the deposit reflected immediately
   > "Now let's check my portfolio."
   > Type: `portfolio`
   > Terminal prints the portfolio table with the 50 USDC position.
   > "There it is. 50 USDC deposited, already earning."

5. **Type `agent status`** — See harvest history
   > "What has the agent been doing?"
   > Type: `agent status`
   > Terminal prints recent harvests: "42 WLD claimed, $38 compounded, 2 hours ago."
   > "The agent compounded $38 for all 47 depositors in ONE transaction. That's 47 individual Merkl claims replaced by 1."

6. **Type `agent harvest`** — Trigger a live harvest, watch it compound
   > "Let's trigger a harvest right now."
   > Type: `agent harvest`
   > Terminal prints step-by-step: checking rewards... claiming from Merkl... swapping WLD to USDC... redepositing... TX confirmed.
   > "Live auto-compounding. The share price just ticked up. Every depositor's position just grew."

#### [2:30 - 3:00] WHY THIS MATTERS

> "World Chain has 40 million users. Most of them will never learn what a Morpho vault is. Harvest makes it simple: deposit and forget.
>
> Every deposit is gated — World ID for humans, AgentKit for agents. No bots, no sybil farms. Every dollar in the vault traces to a verified unique human. The agent auto-compounds, and one harvest transaction benefits everyone.
>
> First yield aggregator on World Chain. Battle-tested Beefy contracts. AI-powered strategy. Built in 36 hours."

---

## 16. Prize Alignment

### Best Use of AgentKit ($8,000)

**Why Harvest qualifies:**

The AI strategist agent is the core product — not a bolted-on feature. The agent:

1. **Uses AgentKit wallet** — The keeper EOA is managed through AgentKit's CDP wallet infrastructure. No raw private keys in application code.

2. **Proves human-backing** — AgentKit credentials establish that the agent is operated by a verified entity, not an anonymous bot. This is used when interacting with yield data APIs and on-chain contracts.

3. **Uses x402 micropayments** — The agent pays for premium yield data using x402 protocol. This demonstrates autonomous agent commerce: the agent decides it needs data, pays for it, and uses the result to make strategy decisions.

4. **Operates autonomously** — The agent runs on a schedule, makes decisions about when to harvest (reward threshold, gas cost analysis), and executes on-chain transactions without human intervention.

5. **Manages real value** — The agent is the sole keeper for the vault's strategy. If the agent stops, compounding stops. It is a critical infrastructure component, not a demo.

**Key narrative:** "The agent IS the strategist. It doesn't help a human manage a vault — it IS the vault manager."

### Best Use of World ID ($8,000)

**Why Harvest qualifies:**

1. **Sybil prevention** — World ID gates deposits. Without verification, a single entity could create thousands of wallets to farm disproportionate vault rewards or Merkl distributions.

2. **Trust layer** — The vault can advertise "47 verified humans, $125K TVL" — this is a meaningful trust signal. Every depositor is a proven unique person.

3. **Orb-level verification** — We use orb-level (not device-level) for maximum sybil resistance.

4. **Privacy-preserving** — We store hashed nullifiers, not raw World ID data. Users prove personhood without revealing identity.

5. **Seamless UX** — Verification happens once at first login. Users don't re-verify for each deposit. The World App biometric flow is fast and familiar.

### Best Use of MiniKit ($4,000)

**Why Harvest qualifies:**

1. **sendTransaction multicall** — Atomic approve + deposit in a single user tap. This is the ideal use of MiniKit's multicall capability — users don't need to understand token approvals.

2. **walletAuth (SIWE)** — Full SIWE authentication flow using MiniKit. Secure session management with HttpOnly cookies.

3. **verify (World ID)** — Integrated World ID verification through MiniKit's verify command.

4. **Native mini app UX** — Built with `@worldcoin/create-mini-app`, designed for the World App viewport. The terminal interface with tappable shortcut buttons is purpose-built for mobile: no tiny buttons, no complex navigation, just commands and output.

5. **Real utility** — This is not a demo app. It provides real yield aggregation for real users. The mini app distribution (40M World App users) is the growth channel.

---

## 17. Risk Mitigation

### Risk 1: Contract Deployment Fails

**Trigger:** Foundry deployment to World Chain Sepolia or mainnet fails due to RPC issues, gas estimation, or contract size limits.

**Mitigation:**
- Test deployment on a local Anvil fork first: `anvil --fork-url $WORLD_CHAIN_RPC`
- Have multiple RPC providers configured (Alchemy, Infura, public)
- If deployment completely fails: deploy mock contracts that simulate the vault interface but use simple storage instead of real Morpho integration

**Demo fallback:** Show the terminal UI + agent logic, explain the architecture on a whiteboard, demonstrate with mock contracts.

### Risk 2: MiniKit sendTransaction Whitelisting Fails

**Trigger:** Developer Portal does not whitelist our contracts in time, or whitelisting has bugs.

**Mitigation:**
- Whitelist early (Saturday morning)
- Test on Sepolia first (faster iteration)
- Have `cast` commands ready as backup for live contract interaction

**Demo fallback:** Show contract interaction via `cast send` in a real terminal. The terminal UI can display mock responses.

### Risk 3: AgentKit SDK Is Rough

**Trigger:** AgentKit SDK has breaking changes, poor documentation, or does not support World Chain.

**Mitigation:**
- Start AgentKit integration early (Friday night)
- If `AgentKit.from()` does not work: manually construct the wallet using CDP API and sign transactions with ethers/viem
- If x402 SDK does not work: manually construct x402 headers (it is SIWE signing under the hood)
- Read the AgentKit source code, not just the docs

**Demo fallback:** Show the agent code, explain the AgentKit integration points, demonstrate manual x402 header construction.

### Risk 4: Merkl Has No Rewards at Demo Time

**Trigger:** The Merkl distributor has no pending rewards for our strategy address at demo time, so `harvest()` is a no-op.

**Mitigation:**
- Pre-seed harvests: deposit into the vault early (Friday night), let rewards accumulate
- If rewards are still zero: manually seed the harvests table in Supabase with realistic data
- Show historical agent activity via `agent status` command

**Demo fallback:** "The agent harvested 6 times in the last 24 hours. Here's the activity feed." Show the pre-seeded data.

### Risk 5: World App Simulator Does Not Work

**Trigger:** Cannot test MiniKit features without a physical device running World App.

**Mitigation:**
- Use the World App simulator (if available) or the MiniKit dev tools
- Test on a real phone with World App installed as early as possible (Saturday morning)
- Build the frontend so it degrades gracefully outside World App (shows "Open in World App" message)

---

## 18. Cut Order

If time runs out, cut features in this order. Items at the top are cut first (least important). Items at the bottom are NEVER cut.

```
CUT FIRST (nice-to-have):
  1. Terminal typing animation on output
  2. Guided prompt flow for deposit/withdraw (require full command instead)
  3. Multiple vault support (ship USDC vault only)
  4. BeefyOracle integration (hardcode slippage instead)
  5. x402 micropayment integration (use free APIs only)
  
CUT SECOND (important but not critical):
  6. Agent rebalance logic (keep harvest-only)
  7. Vault snapshot cron (manual snapshots only)
  8. Comprehensive error handling for bad commands
  9. Tappable shortcut buttons (fallback: type commands only)

NEVER CUT (the demo depends on these):
  10. BeefyVaultV7 deposit + withdraw
  11. StrategyMorpho harvest()
  12. Agent harvest loop (cron + Merkl claim + compound)
  13. AgentKit credentials on the agent
  14. World ID verification gate
  15. MiniKit sendTransaction (approve + deposit)
  16. Terminal with working commands: vaults, deposit, portfolio, agent status
  17. Supabase logging (so terminal commands have data to show)
```

---

## 19. Competitive Edge

### First-Mover Advantage

DeFiLlama confirms zero yield aggregators exist on World Chain as of April 2026. Harvest is the first. This is not a "me too" product — it fills a genuine gap.

### Battle-Tested Contracts

We are not writing a vault from scratch. Beefy's contracts have secured billions of dollars across dozens of chains. Forking MIT-licensed, audited code is the responsible choice for a hackathon and signals engineering maturity to judges.

### AgentKit as Core Mechanic

Most hackathon projects bolt AI on as an afterthought. In Harvest, the agent IS the product. Remove the agent and the vault does not compound. This is exactly the use case AgentKit was designed for: an autonomous agent that manages on-chain assets, proves its identity, and pays for services.

### "One Transaction Replaces Thousands" Narrative

This is the soundbite. When the agent calls `harvest()`, it compounds rewards for every depositor in a single transaction. If 1,000 users would each need to claim from Merkl individually, Harvest replaces 1,000 transactions with 1. This is a compelling narrative for judges and users.

### Accessible to 40M Users

World App has 40 million users. A mini app that lets them deposit into a yield vault with one tap — no wallet setup, no gas management, no understanding of Morpho or Merkl — is a real distribution advantage.

---

## 20. Appendix: Contract Addresses

### World Chain Mainnet (Chain ID: 480)

#### Morpho Vaults (Underlying Yield Sources)

| Vault | Asset | Address | APY (est.) |
|-------|-------|---------|-----------|
| Re7 USDC | USDC | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` | ~4.15% |
| Re7 WLD | WLD | `0x348831b46876d3dF2Db98BdEc5E3B4083329Ab9f` | ~2.58% |
| Re7 WETH | WETH | `0x0Db7E405278c2674F462aC9D9eb8b8346D1c1571` | ~3.18% |
| Re7 WARS | WARS | `0x1C94c7A2c71ECF13104c31F49d5138EDb099D25D` | ~15.35% |
| Re7 EURC | EURC | `0xDaa79e066DeE8c8C15FFb37b1157F7Eb8e0d1b37` | ~8.10% |

**MVP target:** Re7 USDC and Re7 WLD only.

#### Infrastructure Contracts

| Contract | Address |
|----------|---------|
| Merkl Distributor | `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae` |
| WLD Token | `0x2cFc85d8E48F8EAB294be644d9E25C3030863003` |
| Uniswap V3 SwapRouter02 | `0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| USDC.e | TBD — verify deployed address on World Chain |

#### Harvest Contracts (Deployed by Us)

| Contract | Address |
|----------|---------|
| BeefySwapper | TBD — set after deployment |
| USDC Vault (BeefyVaultV7) | TBD — set after deployment |
| USDC Strategy (StrategyMorpho) | TBD — set after deployment |
| WLD Vault (BeefyVaultV7) | TBD — set after deployment |
| WLD Strategy (StrategyMorpho) | TBD — set after deployment |

### External APIs

| API | URL | Auth |
|-----|-----|------|
| Merkl Rewards | `GET https://api.merkl.xyz/v4/users/{address}/rewards?chainId=480` | None (public) |
| Merkl Claims | `GET https://api.merkl.xyz/v4/users/{address}/claims?chainId=480` | None (public) |
| Morpho API | `GET https://blue-api.morpho.org/graphql` | None (public) |
| World ID Verify | `POST https://developer.worldcoin.org/api/v2/verify/{app_id}` | App secret |

### Key ABIs (Minimal)

#### BeefyVaultV7 (User-Facing)

```json
[
  {
    "inputs": [{ "name": "_amount", "type": "uint256" }],
    "name": "deposit",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "name": "_shares", "type": "uint256" }],
    "name": "withdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "balance",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getPricePerFullShare",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{ "name": "account", "type": "address" }],
    "name": "balanceOf",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "totalSupply",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "name": "_user", "type": "address" },
      { "name": "_status", "type": "bool" }
    ],
    "name": "setVerified",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "name": "", "type": "address" }],
    "name": "worldIdVerified",
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view",
    "type": "function"
  }
]
```

#### StrategyMorpho (Keeper-Only)

```json
[
  {
    "inputs": [
      { "name": "_tokens", "type": "address[]" },
      { "name": "_amounts", "type": "uint256[]" },
      { "name": "_proofs", "type": "bytes32[][]" }
    ],
    "name": "harvest",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "balanceOf",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "balanceOfPool",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "balanceOfWant",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "keeper",
    "outputs": [{ "name": "", "type": "address" }],
    "stateMutability": "view",
    "type": "function"
  }
]
```

#### ERC20 (For Approve Calls)

```json
[
  {
    "inputs": [
      { "name": "spender", "type": "address" },
      { "name": "amount", "type": "uint256" }
    ],
    "name": "approve",
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "name": "account", "type": "address" }],
    "name": "balanceOf",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "decimals",
    "outputs": [{ "name": "", "type": "uint8" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "name": "owner", "type": "address" },
      { "name": "spender", "type": "address" }
    ],
    "name": "allowance",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  }
]
```

---

## Appendix A: Vault Configuration Constants

```typescript
// lib/vaults.ts

export interface VaultConfig {
  address: string;           // Harvest vault (BeefyVaultV7) address
  strategyAddress: string;   // StrategyMorpho address
  name: string;              // Display name
  wantToken: string;         // Token symbol
  wantTokenAddress: string;  // Token contract address
  wantTokenDecimals: number;
  morphoVault: string;       // Underlying MetaMorpho vault address
  morphoVaultName: string;   // e.g., "Re7 USDC"
  baseApy: number;           // Baseline APY for display before real data
  mooTokenSymbol: string;    // e.g., "mooHarvestUSDC"
  icon: string;              // Token icon path
}

export const VAULT_CONFIGS: VaultConfig[] = [
  {
    address: process.env.NEXT_PUBLIC_USDC_VAULT_ADDRESS!,
    strategyAddress: "", // Set after deployment
    name: "Harvest USDC",
    wantToken: "USDC",
    wantTokenAddress: process.env.NEXT_PUBLIC_USDC_TOKEN_ADDRESS!,
    wantTokenDecimals: 6,
    morphoVault: "0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B",
    morphoVaultName: "Re7 USDC",
    baseApy: 4.15,
    mooTokenSymbol: "mooHarvestUSDC",
    icon: "/icons/usdc.svg",
  },
  {
    address: process.env.NEXT_PUBLIC_WLD_VAULT_ADDRESS!,
    strategyAddress: "", // Set after deployment
    name: "Harvest WLD",
    wantToken: "WLD",
    wantTokenAddress: "0x2cFc85d8E48F8EAB294be644d9E25C3030863003",
    wantTokenDecimals: 18,
    morphoVault: "0x348831b46876d3dF2Db98BdEc5E3B4083329Ab9f",
    morphoVaultName: "Re7 WLD",
    baseApy: 2.58,
    mooTokenSymbol: "mooHarvestWLD",
    icon: "/icons/wld.svg",
  },
];
```

---

## Appendix B: Merkl API Integration Details

<!-- Merged from claimall-spec.md -->

### Endpoint

```
GET https://api.merkl.xyz/v4/users/{address}/rewards?chainId=480
```

**Key details:**
- The API is public, no auth required
- Rate limits are generous (unknown exact limit, but fine for a hackathon)
- `amount` is the cumulative total ever earned (NOT incremental)
- `claimed` is what has already been claimed on-chain
- `unclaimed` = `amount` - `claimed` (what the strategy can claim)
- `proofs` is the merkle proof array, ready to pass to the contract

### Response Shape: /v4/users/{address}/rewards?chainId=480

```json
{
  "480": {
    "campaignData": [
      {
        "campaignId": "0x...",
        "token": {
          "address": "0x2cFc85d8E48F8EAB294be644d9E25C3030863003",
          "symbol": "WLD",
          "decimals": 18
        },
        "amount": "1500000000000000000",
        "claimed": "500000000000000000",
        "unclaimed": "1000000000000000000",
        "proofs": ["0x...", "0x...", "..."]
      }
    ]
  }
}
```

### Response Shape: /v4/users/{address}/claims?chainId=480

```json
{
  "tokens": ["0x2cFc85d8E48F8EAB294be644d9E25C3030863003"],
  "amounts": ["42500000000000000000"],
  "proofs": [
    ["0xabc...", "0xdef...", "0x123..."]
  ]
}
```

### Backend Implementation

```typescript
export async function getMerklRewards(address: string) {
  const res = await fetch(
    `https://api.merkl.xyz/v4/users/${address}/rewards?chainId=480`
  );

  if (!res.ok) {
    throw new Error(`Merkl API error: ${res.status}`);
  }

  const data = await res.json();
  const chainData = data["480"];

  if (!chainData?.campaignData?.length) {
    return { rewards: [], totalUsd: 0 };
  }

  return chainData.campaignData
    .filter((c: any) => BigInt(c.unclaimed) > 0n)
    .map((c: any) => ({
      source: "Merkl",
      protocol: "Morpho",
      token: c.token.symbol,
      tokenAddress: c.token.address,
      amount: c.unclaimed,
      decimals: c.token.decimals,
      claimData: {
        cumulativeAmount: c.amount, // cumulative, NOT unclaimed
        proofs: c.proofs,
      },
    }));
}
```

### Merkl API Error Handling

- **Timeout (5s):** Return cached data from Supabase with `cached: true`
- **API down:** Return cached data or empty with `lastUpdated` from cache timestamp
- **No cached data:** Return empty response with descriptive error

### Price Data (DeFi Llama)

```
GET https://coins.llama.fi/prices/current/worldchain:0x2cFc85d8E48F8EAB294be644d9E25C3030863003
```

No API key needed, no rate limits, reliable. Cache prices for 5 minutes in-memory.

**Note:** Verify these response shapes against the actual Merkl API. The v4 API may differ from v3. Test early.

---

## Appendix C: Seeding Demo Data

For a compelling demo, pre-seed the database with realistic historical data.

```typescript
// scripts/seed-demo-data.ts

import { supabase } from "../app/lib/supabase";

async function seedDemoData() {
  const USDC_VAULT = process.env.NEXT_PUBLIC_USDC_VAULT_ADDRESS!;
  const now = new Date();

  // Seed 24 hours of vault snapshots (every 4 hours)
  const snapshots = [];
  let sharePrice = 1_000_000_000_000_000_000n; // 1e18 (starts at 1.0)
  
  for (let i = 6; i >= 0; i--) {
    const timestamp = new Date(now.getTime() - i * 4 * 60 * 60 * 1000);
    sharePrice += 250_000_000_000_000n; // +0.00025 per harvest (~4% APY)
    
    snapshots.push({
      vault_address: USDC_VAULT,
      total_assets: "125000000000", // $125K
      share_price: sharePrice.toString(),
      apy_current: 4.15,
      total_depositors: 47,
      timestamp: timestamp.toISOString(),
    });
  }

  await supabase.from("vault_snapshots").insert(snapshots);

  // Seed harvest history
  const harvests = [];
  for (let i = 5; i >= 0; i--) {
    const timestamp = new Date(now.getTime() - i * 4 * 60 * 60 * 1000);
    const rewardAmount = (30 + Math.random() * 20).toFixed(1);
    const rewardUsd = (parseFloat(rewardAmount) * 0.9).toFixed(2);
    
    harvests.push({
      vault_address: USDC_VAULT,
      strategy_address: "0x...",
      rewards_claimed: JSON.stringify({ WLD: rewardAmount }),
      rewards_compounded_usd: parseFloat(rewardUsd),
      gas_cost: "350000",
      gas_cost_usd: 0.04,
      tx_hash: `0x${Math.random().toString(16).slice(2)}${Math.random().toString(16).slice(2)}`,
      timestamp: timestamp.toISOString(),
    });
  }

  await supabase.from("harvests").insert(harvests);

  console.log("Demo data seeded successfully");
}

seedDemoData().catch(console.error);
```

Run before demo: `npx tsx scripts/seed-demo-data.ts`

---

## Appendix D: Key Dependencies

### Frontend (app/package.json)

```json
{
  "dependencies": {
    "next": "^15.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "@worldcoin/minikit-js": "^1.0.0",
    "@worldcoin/minikit-react": "^1.0.0",
    "@supabase/supabase-js": "^2.39.0",
    "viem": "^2.20.0",
    "wagmi": "^2.12.0",
    "@tanstack/react-query": "^5.50.0",
    "tailwindcss": "^4.0.0",
    "clsx": "^2.1.0",
    "tailwind-merge": "^2.3.0",
    "siwe": "^2.3.0",
    "iron-session": "^8.0.0"
  }
}
```

### Agent (agent/package.json)

```json
{
  "dependencies": {
    "@coinbase/agentkit": "^0.5.0",
    "viem": "^2.20.0",
    "@supabase/supabase-js": "^2.39.0",
    "node-cron": "^3.0.3",
    "dotenv": "^16.4.0",
    "pino": "^9.0.0"
  },
  "devDependencies": {
    "typescript": "^5.5.0",
    "@types/node": "^20.14.0",
    "tsx": "^4.16.0"
  }
}
```

### Contracts (contracts/foundry.toml)

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.23"
optimizer = true
optimizer_runs = 200
evm_version = "paris"

[rpc_endpoints]
worldchain = "${WORLD_CHAIN_RPC_URL}"
worldchain_sepolia = "${WORLD_CHAIN_SEPOLIA_RPC}"

[etherscan]
worldchain = { key = "${ETHERSCAN_API_KEY}" }
```

---

## Appendix E: Error Handling Matrix

| Error | Where | Terminal Output | Recovery |
|-------|-------|-----------------|----------|
| World ID proof invalid | Auth (startup) | `ERR: Verification failed. Retrying...` | Auto-retry verify flow |
| SIWE signature invalid | Auth (startup) | `ERR: Could not connect wallet.` | Auto-retry walletAuth |
| Session expired | Any command | `ERR: Session expired. Reconnecting...` | Auto-trigger re-auth inline |
| Deposit tx reverts | `deposit` command | `ERR: Transaction failed. Check your balance.` | User re-runs command |
| Deposit tx rejected by user | `deposit` command | `Cancelled.` | User re-runs command |
| Insufficient balance | `deposit` command | `ERR: Insufficient USDC balance. Have: 12.50` | User adjusts amount |
| Withdraw tx reverts | `withdraw` command | `ERR: Withdrawal failed. Try again.` | User re-runs command |
| Vault at capacity (unlikely) | `deposit` command | `ERR: Vault temporarily full.` | Suggest `vaults` to see alternatives |
| Unknown command | Command input | `Unknown command. Type 'help' for available commands.` | User types `help` |
| RPC node down | Any on-chain read | `ERR: Unable to load vault data. Retrying...` | Auto-retry with exponential backoff |
| Supabase down | API routes | `ERR: Service temporarily unavailable.` | Return cached data if available |
| Agent harvest fails | Agent (logged) | Not shown to user directly | Agent retries next cycle |
| Merkl API down | Agent | Not shown to user directly | Agent skips harvest, retries next cycle |

---

*End of specification. This document contains everything needed to build Harvest from scratch. Start with Section 14 (Build Schedule) and work through each phase. Good luck.*
