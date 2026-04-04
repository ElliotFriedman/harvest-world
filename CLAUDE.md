# CLAUDE.md — Harvest: World Chain Yield Optimizer

## What This Project Is

Harvest is the **first yield aggregator on World Chain** (chain ID 480). **DeFi, for humans.** It auto-compounds Morpho vault rewards for all depositors using a shared ERC-4626-style vault (forked from Beefy Finance). Every deposit is gated — World ID for humans, AgentKit for human-backed agents. No bots. No sybil farms. Every dollar in the vault traces back to a verified unique human. One agent transaction replaces thousands of individual claims, de-congesting World Chain, increasing capital efficiency, and serving as a foundational primitive for other agents to build on top of.

Built for **ETHGlobal Cannes 2026** (April 3-5, 36-hour hackathon).

## Core Architecture (3 components)

1. **Beefy vault + StrategyMorpho contracts** (Solidity, forked from beefyfinance/beefy-contracts, MIT)
   - Shared vault: all users deposit into one pool, receive proportional shares
   - Strategy claims Merkl rewards, swaps to underlying, redeposits (auto-compound)
   - World ID gates deposits (only verified humans)

2. **Agent/Harvester** (TypeScript cron, runs every 6-12 hours)
   - Calls `harvest()` on the strategy contract
   - Uses AgentKit credentials + x402 for data fetching
   - Threshold-based: only harvests when `pendingRewards >= minHarvest`

3. **Terminal UI** (Next.js 15 World Mini App, MiniKit 2.0)
   - Single-screen retro terminal (green-on-black, monospace)
   - Commands: `portfolio`, `vaults`, `deposit`, `withdraw`, `agent status`, `agent harvest`, `help`
   - Tappable shortcut buttons for mobile UX
   - MiniKit sendTransaction for deposit/withdraw (atomic multicall)

## Key Files — KEEP THESE IN SYNC

When making changes to the product (scope, architecture, contracts, UI, demo), update ALL relevant files:

| File | Purpose | Update when... |
|------|---------|----------------|
| `CLAUDE.md` | This file. Central context. | Any major decision changes |
| `docs/product-spec.md` | Product specification (20 sections) | Scope, features, screens, demo, prizes, schedule change |
| `docs/technical-design.md` | Technical design (12 sections) | API routes, types, contracts, MiniKit code, agent code change |
| `docs/pitch.md` | Pitch script + demo storyboard + judge Q&A | Narrative, demo flow, key stats change |
| `docs/cloud-architecture.md` | Infra/cloud architecture | Hosting, deployment, agent runtime change |
| `docs/infra-checklist.md` | Infrastructure setup task list | Infra, deployment, API keys change |
| `contracts/` | Foundry project with Beefy fork | Contract changes |
| `app/` | Next.js 15 mini app | Frontend changes |
| `agent/` | Harvester cron | Agent/harvester changes |
| `README.md` | Repo README (mirrors pitch one-pager) | Any public-facing change |

## README Proof of Work — Keep This Section Current

The `README.md` contains a `## Proof of Work` section that judges read to assess effort. **Every time a PR is merged or a significant issue is resolved, update this section.**

Specifically:
- Add the new PR to the correct category table inside the `<details>` block (Infrastructure, Contracts, World ID, Permit2, Mini App, Agent, Features, Security)
- Update the **Development Velocity** stats table: increment the merged PR count, update total commit count (`git log --oneline | wc -l`), and update the LOC breakdown (`cloc . --exclude-dir=node_modules,lib,.git,broadcast,cache,out,dist,.next --quiet | tail -15` — update Solidity, TypeScript, Markdown, and full repo totals)
- If the PR closes an issue, move that issue from the **Roadmap** list to the **Completed** table
- If a new category of work was introduced (e.g. a new area of the codebase), add a new category table inside `<details>`

The commit count and PR count are the fastest way for judges to see work volume at a glance — keep them accurate.

## Key Design Decisions (DO NOT CHANGE without updating all files)

1. **Shared vault, not per-user strategies** — one pool, proportional shares, one harvest benefits everyone
2. **Beefy fork (MIT)** — BeefyVaultV7 + StrategyMorpho + StrategyFactory. Do not write vault/strategy from scratch.
3. **Terminal UI** — single screen, commands not clicks, tappable shortcuts for mobile. No multi-page routing.
4. **No natural language / AI chat** — agent works silently. Users see activity log via `agent status`.
5. **No swap routing in MVP** — users deposit the token the vault accepts (USDC). Swap routing is stretch.
6. **USDC vault only for MVP** — WLD vault is stretch.
7. **AgentKit gates agent deposits** — external agents must prove human-backing via AgentKit to deposit. The vault's x402-protected deposit endpoint verifies agents via AgentBook. This is genuine — protects against bot farming of vault yields and future airdrop rewards.
8. **World ID gates human deposits** — on-chain verification via `verifyHuman()`. Users submit their IDKit proof once; the vault calls `WORLD_ID_ROUTER.verifyProof()` directly (Group 1 = Orb only). Nullifiers are stored on-chain to prevent replay. No backend signer needed.
9. **"DeFi, for humans"** — the core thesis. The vault cryptographically guarantees every depositor is a unique human. This protects rewards distribution, prevents sybil attacks, and makes the vault safe for future incentive programs.
9. **Cron-based harvesting** — simple backend cron calls harvest() every 6-12 hours. Threshold-based (pendingRewards >= minHarvest).
10. **No multisig for hackathon** — EOAs for deployer and agent wallets. Multisig is production concern.

## Issue Tracker

**Master tracker:** https://github.com/ElliotFriedman/harvest-world/issues/22

When creating new issues, ALWAYS update the tracker issue (#22) checklist to include the new issue.

## Contract Addresses (World Chain, chainId 480)

| Contract | Address |
|----------|---------|
| USDC.e (Bridged USDC) | `0x79A02482A880bCE3F13e09Da970dC34db4CD24d1` |
| WLD Token | `0x2cFc85d8E48F8EAB294be644d9E25C3030863003` |
| WETH | `0x4200000000000000000000000000000000000006` |
| WBTC | `0x03C7054BCB39f7b2e5B2C7AcB37583e32D70CFa3` |
| EURC | `0x1C60ba0A0eD1019e8Eb035E6daF4155A5cE2380B` |
| MORPHO Token | `0xe2108e43dBD43c9Dc6E494F86c4C4D938Bd10f56` |
| Morpho Blue (core) | `0xe741bc7c34758b4cae05062794e8ae24978af432` |
| Merkl Distributor | `0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae` |
| Morpho Re7 USDC Vault | `0xb1E80387EbE53Ff75a89736097D34dC8D9E9045B` |
| Morpho Re7 WLD Vault | `0x348831b46876d3dF2Db98BdEc5E3B4083329Ab9f` |
| Morpho Re7 WETH Vault | `0x0Db7E405278c2674F462aC9D9eb8b8346D1c1571` |
| Uniswap V3 SwapRouter02 | `0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6` |
| Uniswap V3 QuoterV2 | `0x10158D43e6cc414deE1Bd1eB0EfC6a5cBCfF244c` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| World ID Router | `0x17B354dD2595411ff79041f930e491A4Df39A278` |
| Safe L2 v1.4.1 | `0x29fcB43b46531BcA003ddC8FCB67FFE91900C762` |
| EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |

## External APIs

| API | Endpoint | Purpose |
|-----|----------|---------|
| Merkl Rewards | `GET https://api.merkl.xyz/v4/users/{address}/rewards?chainId=480` | Fetch claimable rewards + merkle proofs |
| DeFi Llama | `GET https://coins.llama.fi/prices/current/{tokens}` | Token prices for USD conversion |
| World Notifications | `POST https://developer.worldcoin.org/api/v2/minikit/send-notification` | Push notifications to users |
| World ID Verify | `POST https://developer.world.org/api/v4/verify/{rp_id}` | Verify World ID proofs |

## Beefy Contracts to Fork

Source: `github.com/beefyfinance/beefy-contracts` (MIT licensed)

| File | Purpose | Modifications |
|------|---------|---------------|
| `vaults/BeefyVaultV7.sol` | User-facing vault, mints shares | Add World ID `verifyHuman()` + Permit2 deposit |
| `strategies/Morpho/StrategyMorpho.sol` | Morpho yield + Merkl claiming | Configure for World Chain vaults |
| `strategies/BaseAllToNativeFactoryStrat.sol` | Base harvest flow | Simplify fee structure |
| `strategies/StrategyFactory.sol` | Beacon proxy factory | Use as-is |
| `infra/BeefySwapper.sol` | Swap router | Hardcode Uniswap V3 WLD->USDC path |

Strip: TimelockController, BeefyTreasury, complex fee config, governance

## Prize Targets

| Track | Prize | How we win |
|-------|-------|-----------|
| Best Use of AgentKit | $8,000 | Agent IS the strategist. Uses AgentKit + x402 to fetch data, proves human-backing, manages vault autonomously |
| Best Use of World ID | $8,000 | World ID gates deposits. Only verified humans. Prevents sybil farming of vault yields |
| Best Use of MiniKit | $4,000 | sendTransaction multicall (approve+deposit atomic), walletAuth, verify. Deep integration |
| **Total eligible** | **$20,000** | |

## Build Schedule (36 hours)

**Friday Apr 3:** Scaffold (9-11 PM) → Contracts strip + Auth (11 PM-2 AM)
**Saturday Apr 4:** Deploy + Dashboard (9 AM-1 PM) → Integration + AgentKit (1-5 PM) → Polish (5-8 PM) → Demo prep (8-11 PM)
**Sunday Apr 5:** Final testing (5-9 AM) → Submission

## Cut Order (if running out of time)

1. NEVER CUT: Vault contract, deposit, harvest, terminal UI, demo
2. Cut first: Multiple vault support (ship USDC only)
3. Cut second: AgentKit x402 integration (manual harvester still works)
4. Cut third: Notifications
5. Cut fourth: Withdraw flow polish

## Key Stats for Pitch

- World Chain: $42.7M TVL, 25M+ users, ZERO yield aggregators (DeFiLlama confirmed)
- Beefy: MIT licensed, $billions TVL across 25+ chains, battle-tested
- Gas savings: 1 harvest tx replaces N individual claims (N = number of depositors)
- Morpho Re7 USDC: ~4.15% APY base + Merkl WLD rewards on top
- Auto-compound advantage: weekly compounding on 4.15% → 4.23% effective APY

## CRITICAL: Deployment & MiniKit Constraints

1. **Deploy to MAINNET, not testnet.** World App requires mini apps on World Chain mainnet (chain ID 480). Testnet contracts won't work with MiniKit in World App.
2. **Permit2 required.** MiniKit blocks standard ERC-20 `approve()` calls. Vault deposit must use Permit2 (`0x000000000022D473030F116dDEE9F6B43aC78BA3`). This is a Beefy fork modification — the vault's deposit path needs `permit2.transferFrom()` instead of `token.transferFrom()`.
3. **Contract whitelisting required.** All contracts the mini app interacts with must be whitelisted in the Developer Portal under Configuration → Advanced BEFORE any user transactions work. Non-whitelisted = `invalid_contract` error.
4. **sendTransaction returns userOpHash, not tx hash.** Must poll `developer.worldcoin.org/api/v2/minikit/userop/{hash}` for final transaction hash.
5. **App store listing won't be approved during hackathon.** The store card/logo won't show until post-approval. Demo via QR code testing flow instead. App name cannot contain "World". Description max 25 words.

## Infra Checklist

Full checklist at `/Users/elliot/harvest-infra-checklist.md`. Key items to do NOW:
- [ ] Developer Portal: app registered, World ID action configured
- [ ] GitHub repo created (monorepo: /contracts + /app + /agent)
- [ ] Deployer wallet funded with ETH on World Chain mainnet
- [ ] Confirm Orb-verified team member (needed for AgentKit registration)
- [ ] Vercel project linked to repo

## Context for AI Assistants

You are helping build a hackathon project. Speed matters more than perfection. When in doubt:
- Ship the simpler version
- Hardcode what you can
- Test on mainnet
- Skip governance/timelocks for now
- One vault (USDC) is enough for the demo
- The terminal UI is the entire frontend — one page, one component tree
- The demo is 3 minutes: `vaults` → `deposit 50 usdc` → `portfolio` → `agent status` → `agent harvest and see notification of yield generated`

OK, I like to add more scope, but don't let me increase the scope, only let me pare down the already existing scope.


Integrate World ID into my project using IDKit.

My app credentials are stored in environment variables:
- WORLD_APP_ID (app_id from the Developer Portal)
- WORLD_RP_ID (rp_id from the Developer Portal)
- RP_SIGNING_KEY (signing key — must stay secret, backend only)

## Worldcoin Integration Steps

1. Install the IDKit SDK for my platform.

2. Create a backend endpoint that generates RP signatures.
   Signatures verify that proof requests come from my app.
   Use `signRequest(action, signingKey)` which returns `{ sig, nonce, createdAt, expiresAt }`.
   Never expose the signing key to the client.

3. On the client, fetch the RP signature from my backend, then create an IDKit request with:
   - `app_id`, `action`, and `rp_context` (containing `rp_id`, `nonce`, `created_at`, `expires_at`, `signature` from the RP signature)
   - `allow_legacy_proofs: true`
   - `.preset(orbLegacy())` for Orb verification
   - Signal is optional — use it to bind context like a user ID or wallet address into the proof. The backend should enforce the same value.

4. On success, send the IDKit result to my backend.
   The backend should forward the payload as-is to: POST https://developer.world.org/api/v4/verify/{rp_id}
   No field remapping is needed.

## Reference
- Full docs: https://docs.world.org/llms.txt

## Worldcoin Prize Track

About
Use MiniKit to ship a Mini App in World App, IDKit to add World ID 4.0 verification anywhere, and AgentKit to power agentic workflows. Together, they let you build human only products
Prizes
🤖 Best use of Agent Kit ⸺ $8,000
🥇
1st place
$4,000
🥈
2nd place
$2,500
🥉
3rd place
$1,500
Apps that use AgentKit to ship agentic experiences where World ID improves safety, fairness, or trust.
Qualification Requirements
Submissions must integrate World's Agent Kit to meaningfully distinguish human-backed agents from bots or automated scripts.
Submissions that only use World ID or MiniKit without the Agent Kit layer will not qualify for this specific track.

Links and Resources
Agent Kit Docs
https://docs.world.org/agents/agent-kit/integrate
↗
👥 Best use of World ID 4.0 ⸺ $8,000
🥇
1st place
$4,000
🥈
2nd place
$2,500
🥉
3rd place
$1,500
Leverage the new World ID 4.0 building products that break without proof of human
Qualification Requirements
Uses World ID 4.0 as a real constraint (eligibility, uniqueness, fairness, reputation, rate limits).
Proof validation is required and needs to occur in a web backend or smart contract.

Links and Resources
World ID Docs
https://docs.world.org/world-id/overview
↗
📱 Best use of Minikit 2.0 ⸺ $4,000
🥇
1st place
$2,000
🥈
2nd place
$1,250
🥉
3rd place
$750
Mini apps that make World ID and World App work smoothly with the broader Ethereum/Solana ecosystems and common dev stacks.
Qualification Requirements
- Build a Mini App with MiniKit 2.0
- Integrate any of the MiniKit SDK Commands.
- If your Mini App uses on-chain activity, deploy your contracts to World Chain.
- (If Mini App) your project must not be gambling or chance based.
- Proof validation is required and needs to occur in a web backend or smart contract.

Links and Resources
Mini App Docs
https://docs.world.org/mini-apps