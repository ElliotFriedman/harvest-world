# Harvest — DeFi, for Humans

**The first yield aggregator on World Chain.** Auto-compounds Morpho vault rewards for all depositors. Every depositor is a verified unique human.

Built for ETHGlobal Cannes 2026.

---

## What it does

Harvest pools USDC deposits into a shared Morpho vault. An AI agent (AgentKit) runs every 6–12 hours: claims Merkl rewards, swaps to USDC via Uniswap V3, and redeposits — compounding yield for every depositor in a single transaction.

- **World ID gates deposits.** Only Orb-verified humans can deposit. No bots, no sybil farming.
- **AgentKit runs the strategy.** Human-backed agents can also deposit, proven via AgentBook.
- **One harvest, everyone benefits.** 1 transaction replaces N individual claims.

## Architecture

```
app/          Next.js 15 World Mini App (terminal UI, MiniKit 2.0)
contracts/    Foundry — BeefyVaultV7 + StrategyMorpho (forked from Beefy Finance, MIT)
agent/        TypeScript harvester cron (AgentKit + x402)
docs/         Product spec, technical design, pitch, infra
```

## Key contracts (World Chain, chainId 480)

| Contract | Address |
|----------|---------|
| Morpho Re7 USDC Vault | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` |
| USDC.e | `0x79A02482A880bCE3F13e09Da970dC34db4CD24d1` |
| Merkl Distributor | `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| World ID Router | `0x17B354dD2595411ff79041f930e491A4Df39A278` |

## Prize targets

| Track | Prize |
|-------|-------|
| Best Use of AgentKit | $8,000 |
| Best Use of World ID | $8,000 |
| Best Use of MiniKit | $4,000 |

## Demo

Open Harvest in World App → verify human (World ID orb) → `vaults` → `deposit 50 usdc` → `portfolio` → `agent status` → `agent harvest`

## Contracts

Forked from [beefyfinance/beefy-contracts](https://github.com/beefyfinance/beefy-contracts) (MIT). Modifications: World ID deposit gate, Permit2 transfer path, Uniswap V3 swap config for World Chain.

## Stats

- World Chain: $42.7M TVL, 25M+ users, zero yield aggregators
- Morpho Re7 USDC: ~4.15% base APY + Merkl WLD rewards
- Gas savings: 1 harvest tx replaces N individual claim transactions
