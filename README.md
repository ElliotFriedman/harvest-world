# Harvest — DeFi, for Humans

**The first yield aggregator on World Chain.** Auto-compounds Morpho vault rewards for all depositors. Every depositor is a verified unique human.

Built for ETHGlobal Cannes 2026.

---

## The Problem

There is $42.7M sitting in DeFi on World Chain right now. Users deposit into Morpho vaults, earn yield, and then... nothing happens. Rewards pile up unclaimed in Merkl. Nobody auto-compounds. And here's the thing — there is no Beefy on World Chain. No Yearn. No yield aggregator of any kind. DeFiLlama confirms it: zero.

Today, if a thousand Morpho users want to claim their rewards, that's a thousand separate transactions — a thousand people doing the same thing individually.

World Chain has 25 million verified humans. None of them are getting compounded yield.

## The Solution

Harvest is a yield aggregator built natively for World Chain. Deposit once. An AI agent does the rest.

Under the hood: we forked Beefy Finance's battle-tested vault contracts (MIT, $billions TVL across 25+ chains), brought that infrastructure to World Chain, and plugged in an AgentKit-powered strategist that claims Merkl rewards, swaps them back to your deposit token, and redeposits — all in a single transaction. One agent harvest benefits every depositor simultaneously.

- **World ID gates deposits.** Only Orb-verified humans can deposit. No bots. No sybil farming of vault yields.
- **AgentKit runs the strategy.** Human-backed agents can also participate, proven via AgentBook — the vault cryptographically distinguishes human-backed automation from anonymous scripts.
- **One harvest, everyone benefits.** 1 agent transaction replaces N individual claims.

## The Vision

Harvest v1 is a USDC yield aggregator. But the architecture is a foundation for something bigger.

**What this becomes with more time:**

A DeFi super-app for World App's 25M users — the first yield optimizer that knows who its users are, and optimizes for them specifically.

Imagine a single app where you set your risk profile — conservative, balanced, or aggressive — and an agent continuously rotates your capital between:

- **Morpho vault markets** — lending yield on USDC, WETH, WLD, WBTC, EURC
- **Uniswap V3 LP positions** — fee revenue on concentrated liquidity ranges
- **Merkl incentive programs** — bonus WLD and MORPHO rewards layered on top

The agent monitors APYs across all venues in real time, rebalances when spreads are meaningful, claims rewards, and compounds back in — all without the user touching anything after the initial deposit.

Because every depositor is World ID-verified, the vault has a property no other protocol on any chain has: **a cryptographic guarantee that every dollar traces back to a unique human.** That's not just a feature. It makes the vault safe for incentive programs, airdrops, and reward distributions that would otherwise be gamed into the ground by bots.

The agent layer compounds this. As AgentKit matures, Harvest can offer opt-in yield strategies where verified humans delegate to AI agents that have proven human backing — a new primitive where the trust guarantees of World ID extend into autonomous financial management.

This is what "DeFi, for humans" actually means at scale.

## What We Built (Hackathon Scope)

| Component | Status |
|-----------|--------|
| BeefyVaultV7 + StrategyMorpho on World Chain mainnet | Deployed |
| World ID deposit gate (Orb-verified humans only) | Implemented |
| AgentKit harvester — claims Merkl, swaps WLD→USDC, redeposits | Implemented |
| Next.js 15 World Mini App with MiniKit 2.0 | Deployed |
| Permit2 atomic approve+deposit | Implemented |
| Terminal UI with progressive disclosure | Implemented |

**USDC vault only for v1.** Multi-asset, multi-strategy, and risk-profile routing are the roadmap.

## Architecture

```
app/          Next.js 15 World Mini App (terminal UI, MiniKit 2.0)
contracts/    Foundry — BeefyVaultV7 + StrategyMorpho (forked from Beefy Finance, MIT)
agent/        TypeScript harvester cron (AgentKit + x402)
docs/         Product spec, technical design, pitch, infra
```

## Key Stats

- World Chain: $42.7M TVL, 25M+ verified users, zero yield aggregators before Harvest
- Morpho Re7 USDC: ~4.15% base APY + Merkl WLD rewards on top
- Auto-compound math: weekly compounding 4.15% → 4.23% effective APY
- Gas savings: 1 harvest transaction replaces N individual claim transactions (N = depositors)

## Key Contracts (World Chain, chainId 480)

| Contract | Address |
|----------|---------|
| Harvest Vault (mooWorldMorphoUSDC) | `0xDA3cF80dC04F527563a40Ce17A5466d6A05eefBD` |
| Morpho Re7 USDC Vault | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` |
| USDC.e (Bridged USDC) | `0x79A02482A880bCE3F13e09Da970dC34db4CD24d1` |
| Merkl Distributor | `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae` |
| World ID Router | `0x17B354dD2595411ff79041f930e491A4Df39A278` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |

## Prize Targets

| Track | Prize | How we win |
|-------|-------|-----------|
| Best Use of AgentKit | $8,000 | Agent IS the strategist — claims, swaps, redeposits autonomously using AgentKit + x402 |
| Best Use of World ID | $8,000 | World ID gates deposits. Only Orb-verified humans. Sybil-proof vault. |
| Best Use of MiniKit | $4,000 | Permit2 atomic approve+deposit, walletAuth, IDKit verify — deep MiniKit integration |

## Demo

Open Harvest in World App → verify human (World ID orb) → `vaults` → `deposit 50 usdc` → `portfolio` → `agent status` → `agent harvest`

## Contracts

Forked from [beefyfinance/beefy-contracts](https://github.com/beefyfinance/beefy-contracts) (MIT licensed, battle-tested, $billions TVL). Modifications: World ID deposit gate, Permit2 transfer path, Uniswap V3 swap routing for World Chain.
