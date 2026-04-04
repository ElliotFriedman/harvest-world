DESCRIPTION

World Chain has $42.7M TVL, 25M+ verified humans, and zero yield aggregators. Every dollar sitting in Morpho vaults earns base APY but leaves Merkl WLD rewards unclaimed — because claiming requires individual transactions that cost more in gas than most positions earn.

Harvest fixes this with a shared vault. Deposit USDC, receive hvUSDC shares. An AI agent built on AgentKit runs the strategy: it claims pooled WLD rewards from Merkl, swaps them to USDC via Uniswap V3, and redeposits — compounding yield for every depositor in one transaction. One harvest replaces thousands of individual claims.

Every deposit is World ID–gated. Orb verification means every wallet in the vault traces back to a unique human. No bots, no sybil farms, no one gaming reward distribution. The vault cryptographically guarantees its depositor set is human — making it safe for future incentive programs and a foundational DeFi primitive on World Chain.

The agent isn't bolted on. It's registered via AgentKit's AgentBook, which ties the agent wallet to a verified human on-chain. Human-backed automation, not anonymous scripts.

---

HOW IT'S MADE

Harvest is three layers: Solidity contracts (Beefy fork), a TypeScript harvester agent, and a Next.js 15 World Mini App. Everything talks to World Chain mainnet (chain ID 480).

Contracts — We forked Beefy Finance's BeefyVaultV7 (MIT licensed, battle-tested on $billions TVL). Users deposit USDC.e into the vault, receive hvUSDC shares. The StrategyMorphoMerkl contract deposits pooled USDC into Morpho Re7 vault for base yield, then periodically claims WLD rewards from Merkl's distributor (with merkle proofs), swaps them back to USDC via Uniswap V3, and redeposits — auto-compounding for all depositors in one tx. Zero harvest fee; all yield goes to depositors. MiniKit blocks raw approve(), so we use Permit2 (0x000000000022D473030F116dDEE9F6B43aC78BA3) for atomic approve+deposit.

Agent — The harvester is a TypeScript cron using viem. Before executing any harvest, it checks AgentBook (AgentKit's on-chain registry) to verify the agent wallet is human-backed. Then it hits the Merkl v4 API for unclaimed WLD rewards and proofs, submits the claim tx, and calls harvest() on the strategy. One transaction compounds yield for every depositor simultaneously.

IDKit + World ID — Every deposit is World ID–gated. The /api/sign-request endpoint generates RP signatures (nonce + expiry, signed with RP_SIGNING_KEY, never exposed client-side). IDKit runs client-side with Orb preset, sends the proof to /api/verify, which forwards it to developer.world.org/api/v4/verify/{rp_id}. Nullifiers prevent replay. We lazy-load IDKit to avoid webview crashes in World App.

MiniKit — The terminal UI (green-on-black, monospace, one screen) runs inside World App. walletAuth for login, IDKit for verification, sendTransaction for deposits. The share price difference before/after harvest is shown live in agent status.

The hackiest bit: tracking share price delta across the harvest tx to display "yield generated this harvest" — we snapshot getPricePerFullShare() before and after the on-chain call and compute the diff in the status endpoint.
