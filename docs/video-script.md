# Harvest Demo Video — Script & Outline

> **Target length:** 3:00–3:15 (safe within 2–4 min ETHGlobal requirement)
> **Format:** Screen recording of live app + voiceover narration. Zero slides until closing stats card.
> **Resolution:** 1080p minimum
> **Voiceover:** Real human voice (AI voiceover = disqualification risk)
> **Recording tool:** QuickTime/OBS screen capture of World App simulator or phone mirror

---

## Format Recommendation

**All demo, no slides.** Kartik is right — judges see 100+ slide decks. A live product running on mainnet with real money stands out. The only non-demo screen is a 15-second closing stats card.

**Structure:**
1. Cold open on the terminal (no intro slide, no logo, no "hi my name is")
2. Walk through the app live
3. Trigger a real harvest on-chain
4. Close with a stats card showing depth of work

---

## Pre-Recording Checklist

- [ ] App loaded in World App (or simulator with MiniKit working)
- [ ] Wallet connected and World ID verified (pre-done, don't waste time on auth flow)
- [ ] Some USDC in wallet for deposit demo
- [ ] Agent has pending Merkl rewards ready to claim (check `agent status` first)
- [ ] Terminal clean (run `clear` before recording)
- [ ] Good mic, quiet room, no background noise

---

## Script

### [0:00–0:15] COLD OPEN — The Terminal Boots

**Screen:** App opens. Terminal boot sequence plays — "HARVEST OS v2.5... Connecting to World Chain (480)... World ID: VERIFIED"

**Voiceover:**
> "This is Harvest. The first yield aggregator on World Chain. DeFi, for humans."

*Let the boot sequence breathe for a beat. The terminal aesthetic IS the hook.*

---

### [0:15–0:40] THE PROBLEM — Say It Fast

**Screen:** Type `vaults`. Vault table appears showing Re7 USDC, 4.23% APY, TVL, depositors.

**Voiceover:**
> "World Chain has 25 million verified humans and $42 million in DeFi — but zero yield aggregators. If you deposit into Morpho, you earn base yield plus World reward tokens. To compound those rewards, every single user has to claim, swap, and redeposit manually. Every time. That's thousands of redundant transactions."

---

### [0:40–1:10] THE SOLUTION — Show the Deposit

**Screen:** Type `deposit 50`. Deposit picker appears. Tap $50. MiniKit confirmation pops up. Transaction confirms.

**Voiceover:**
> "Harvest fixes this. You deposit once — through World App, using world chains native account abstraction for a gasless atomic approve-and-deposit. Your USDC goes into a shared vault built on Beefy's battle-tested contracts — the same architecture securing billions across 25 chains. And here's the key: only verified humans can deposit. World ID, orb-level. No bots, no sybil farms."

**Screen:** Type `portfolio`. Shows deposit, vault shares, USD value.

> "That's it. You're in. Now the agent takes over."

---

### [1:10–2:00] THE AGENT — This Is the Core

**Screen:** Type `agent status`. Shows agent state: last harvest, pending WLD rewards, Uniswap quote, streaming yield countdown, next check time.

**Voiceover:**
> "Every few hours, our AI agent wakes up. It's registered through AgentKit — proven human-backed, not a bot. It checks Merkl for pending reward tokens, queries the Uniswap Trading API for a swap quote, and decides: is harvesting profitable right now? If gas costs more than half the output, it waits. Otherwise, it makes the swap."

*Pause. Let them read the status screen.*

> "When it's profitable — it claims the rewards, swaps WLD to USDC through Uniswap V3, and redeposits into Morpho. One transaction. Every depositor's shares go up."

**Screen:** Type `agent harvest`. Live harvest executes — step by step:
```
[1/4] Checking Merkl rewards...     18.4 WLD available
[2/4] Claiming from Merkl...        TX: 0x123...abc  OK
[3/4] Swapping WLD -> USDC...       16.65 USDC received
[4/4] Depositing into Morpho...     TX: 0x456...def  OK

Compounded $16.65 for all depositors.
Share price: 1.000000 -> 1.000133
```

**Voiceover (over the harvest animation):**
> "Claim. Swap. Redeposit. One agent transaction replaces hundreds of individual claims. That's the whole loop — auto-compounding yield for every human in the vault."

---

### [2:00–2:20] THE PROOF — Show It's Real

**Screen:** Type `portfolio` again. Share price has ticked up. Show the delta.

**Voiceover:**
> "Share price went up. That's real yield, compounded on mainnet, with real money. We have over a thousand dollars in deposits from actual World App users."

**Screen:** Optionally flash the Worldscan link (type `scan`) — shows the vault contract on-chain.

> "Every transaction is verifiable on-chain. This isn't a demo on testnet — this is live."

---

### [2:20–2:50] THE ARCHITECTURE — 20 Seconds, Verbal Only

**Screen:** Keep showing the terminal. Maybe type `help` so the command list is visible. Or stay on the portfolio screen.

**Voiceover:**
> "Under the hood: Solidity contracts forked from Beefy Finance and deployed to World Chain mainnet. A TypeScript harvester agent running on a cron — powered by AgentKit and the Uniswap Trading API. And a Next.js mini app running inside World App with MiniKit for atomic transactions and IDKit for World ID verification. Three components, all integrated. We also ran Certora formal verification on the vault and strategy — 51 properties proven correct. And we ran a full internal security audit, 26 findings, zero critical."

---

### [2:50–3:10] CLOSING STATS CARD

**Screen:** Cut to a clean stats card (dark background, green text, terminal aesthetic). This is the ONE non-demo screen.

```
HARVEST — DeFi, for humans.

First yield aggregator on World Chain

178 commits  |  98 PRs  |  20,000 lines of code
2,710 lines Solidity  |  1,807 lines TypeScript
51 Certora formal verification properties
26 security audit findings (0 critical)
$1,000+ in real deposits on mainnet
Built in 36 hours

World ID + AgentKit + MiniKit + Uniswap V3
github.com/ElliotFriedman/harvest-world
```

**Voiceover:**
> "178 commits. 98 PRs. 20,000 lines of code. 51 formally verified properties. Over a thousand dollars deposited. All in 36 hours. Harvest — DeFi, for humans."

*Hold the card for 3–4 seconds. End.*

---

## Timing Breakdown

| Section | Duration | Content |
|---------|----------|---------|
| Cold open (boot) | 0:00–0:15 | Terminal boots, one-liner thesis |
| Problem + vaults | 0:15–0:40 | `vaults` command, explain the gap |
| Deposit flow | 0:40–1:10 | `deposit 50`, `portfolio`, World ID mention |
| Agent status | 1:10–1:40 | `agent status`, explain AgentKit + intelligence |
| Live harvest | 1:40–2:00 | `agent harvest`, step-by-step on-screen |
| Proof it's real | 2:00–2:20 | `portfolio` delta, $1K deposits, mainnet |
| Architecture (verbal) | 2:20–2:50 | Tech stack over terminal screen |
| Stats card + close | 2:50–3:10 | One closing card, final line |
| **Total** | **~3:10** | |

---

## Key Lines to Nail (Practice These)

1. **"The first yield aggregator on World Chain. DeFi, for humans."** (opening)
2. **"Only verified humans can deposit. World ID, orb-level."** (deposit section)
3. **"One agent transaction replaces hundreds of individual claims."** (harvest section)
4. **"This isn't a demo on testnet — this is live."** (proof section)
5. **"178 commits. 20,000 lines. 36 hours. Harvest."** (closing)

---

## Prize Track Hits (What Judges Should Walk Away With)

| Track | What to emphasize | Where in video |
|-------|-------------------|----------------|
| **AgentKit ($8K)** | Agent IS the strategist. Human-backed via AgentKit. Makes autonomous profit decisions. | Agent status + harvest section (1:10–2:00) |
| **World ID ($8K)** | Deposits gated to Orb-verified humans. Sybil-proof vault. | Deposit section (0:40–1:10) |
| **MiniKit ($4K)** | Atomic Permit2 approve+deposit via sendTransaction. Full mini app. | Deposit section (0:40–1:10) |

---

## Tips for Recording

1. **Pre-verify World ID** before recording. Don't waste 30 seconds on the IDKit modal.
2. **Have rewards ready.** Check `agent status` first — if pending rewards are 0, seed them or wait.
3. **Type commands live** (don't paste). The terminal UX IS the product — show it being used.
4. **Pause after each command** for 1–2 seconds so judges can read the output.
5. **Don't rush the harvest.** The step-by-step output (Checking... Claiming... Swapping... Depositing...) is the most compelling visual. Let it play.
6. **Practice the voiceover 3 times** before recording. Aim for conversational, not scripted.
7. **Record in one take** if possible. Cuts make it feel less real.
8. **Show the phone** in frame for 2–3 seconds at the start if possible — proves it's running in World App.

---

## Judge Q&A Prep (3 Minutes at Partner Booths)

You get 4 min demo + 3 min Q&A. The video does the demo. Below is what they'll ask at the **World/Worldcoin partner booth** and the **finalist stage**.

### The 5 Questions They Will Definitely Ask

**Q1: "How is this different from just using Morpho directly?"**

> "You can use Morpho directly and earn 4.15%. But your Merkl reward tokens sit unclaimed — you'd have to manually claim, swap WLD to USDC on Uniswap, and redeposit. Every time. Harvest does that automatically. One agent transaction compounds for every depositor at once. And we gate deposits with World ID — so the vault is sybil-proof, which matters for fair reward distribution."

**Q2: "How does the agent actually work? Walk me through the harvest."**

> "Every day, the agent wakes up. It queries the Merkl API for pending reward tokens — usually WLD. It gets a swap quote from the Uniswap Trading API. If gas costs more than half the swap output, it skips — not profitable. Otherwise: it calls claim() on our strategy contract with merkle proofs, which triggers the swap through Uniswap V3 — WLD to WETH to USDC — and redeposits into Morpho. Share price goes up. Every depositor benefits. The agent is registered through AgentKit, so it's proven human-backed, not an anonymous bot managing people's money."

**Q3: "What happens if the agent goes down? Are funds at risk?"**

> "No. Funds sit in the Beefy vault contract and Morpho underneath — both non-custodial. If the agent stops, compounding rewards stops, but users are still earning yield from the underlying vault, but nobody loses money. Users can withdraw anytime. The agent can only call harvest() — it can't move user principal. It's functionally a keeper, like Gelato or Chainlink Automation, but with AgentKit identity."

**Q4: "You forked Beefy — what did you actually build?"**

> "We took Beefy's vault and strategy contracts, stripped governance and timelocks for hackathon speed, and added two things: Permit2 integration for World App's MiniKit — which blocks standard ERC-20 approvals — and the World ID deposit gate. We wrote the StrategyMorpho from scratch to handle Merkl claiming and the WLD-to-USDC swap path through Uniswap V3. We built the entire TypeScript harvester agent with AgentKit. We built the terminal mini app with MiniKit and IDKit. We ran Certora formal verification — 51 properties proven correct on the vault and strategy. And we ran a 26-finding security audit. 178 commits, 20,000 lines of code, all in 36 hours.

We have an ambitious roadmap and ideas for how to extend this to a multi-vault, multi-asset yield manager that is broader than the current single asset vault to allow users to earn on all of their assets on world chain."

**Q5: "Is this deployed? Can I try it?"**

> "Yes, live on World Chain mainnet right now. We have over a thousand dollars in real deposits from actual World App users. Every transaction is on Worldscan. Open World App, search Harvest — you can deposit right now. Or scan this QR code."

*Have the QR code ready on your phone or a printed card.*

---

### World-Specific Questions (Partner Booth)

**"How does World ID add value beyond a login?"**

> "It's not a login — it's a deposit gate. The vault only accepts funds from Orb-verified humans. This means reward distribution is fair — no bot can deposit a million dollars and dilute everyone's yield. It's sybil-proof DeFi. When Morpho or anyone else runs incentive programs on World Chain, Harvest vaults are the only place where you know every depositor is a unique human. That's a primitive other protocols can build on. Fin tech platforms want real users, they don't want a bunch of unverified agents harvesting yield from them."

**"Why AgentKit and not just a normal backend cron?"**

> "The cron is simple. What AgentKit adds is identity. Our agent is registered in AgentBook — on-chain proof it's backed by a verified human. This matters because the agent is managing real user funds. In a world where AI agents are proliferating, being able to say 'this agent traces back to a real person' is how you build trust. We also designed the vault so that external agents — other people's agents — can deposit too, as long as they prove human backing through AgentKit. The vault becomes a DeFi primitive for the agent economy. In the future, we would like any agent to be able to claim and compound user rewards as long as they are tied to a real world account using agentkit"

**"How does MiniKit integration actually work?"**

> "MiniKit blocks standard ERC-20 approve() calls — it's a security measure. So we integrated Permit2. When a user taps deposit, we batch two transactions atomically: a Permit2 approval and the vault deposit. One confirmation in World App. We also use walletAuth for SIWE sessions and IDKit for the World ID verification flow. The whole app is a mini app running natively inside World App — 40 million users can access it without installing anything."

---

### Hardball Questions (Finalist Stage)

**"4.15% to 4.23% APY — that's 8 basis points. Is that meaningful?"**

> "On its own, no. But three things. First, it compounds — over years and at scale, 8bps on millions of TVL is real money. Second, the real value isn't the APY delta — it's the UX. Most World App users will never learn to claim Merkl rewards manually. Harvest makes yield effortless. Third, the gas savings are significant — one transaction replaces hundreds. On World Chain with 25 million users, that's meaningful network efficiency. By batching all claims into a single call, we reduce the backend load on Merkle, and helps decongest the world chain, helping it scale through efficiency"

**"What stops Beefy from just deploying on World Chain themselves?"**

> "Nothing. And they probably will. But right now they haven't — and we're live with real deposits. First mover matters in DeFi because of liquidity and integrations. If Beefy deploys tomorrow, we've already shipped the World ID gate and AgentKit agent, which they don't have. We're not competing on vault design — we're competing on distribution (World App), identity (World ID), and agent infrastructure (AgentKit)."

**"How did you build 20,000 lines of code in 36 hours?"**

> "We used AI tools extensively — Claude Code for development. That's documented in our repo. But every line was reviewed, tested, and verified by our team. We had around ~3,600 lines of code. We ran formal verification with Certora — 51 properties proven correct. We conducted an AI security audit with 26 findings, none high or critical severity. The git history shows 178 commits with clear progression. AI made us faster; it didn't replace engineering judgment. The Beefy fork gave us a solid foundation so we didn't have to write a vault from scratch."

**"What about regulatory risk with an AI managing funds?"**

> "The agent doesn't custody funds. It calls a public function on a smart contract that anyone can call. It's the same as a Gelato keeper or Chainlink node — automated execution, not fund management. Users deposit and withdraw directly from the vault contract. The agent can only trigger harvest(), which compounds rewards back into the same vault."

---

### Your Closing Line (Memorize This)

When Q&A winds down, have this ready:

> "World Chain has 25 million verified humans, $42 million in DeFi, and zero yield aggregators. We built the first one in 36 hours — with real deposits, formal verification, and an agent that's already compounding yield on mainnet. Harvest. DeFi, for humans."

Then stop talking.
