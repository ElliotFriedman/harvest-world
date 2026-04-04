# Harvest -- Cloud & Infrastructure Architecture

**Version:** 1.0
**Date:** April 3, 2026
**Status:** Decision-ready
**Companion to:** `harvest-v2-spec.md`, `harvest-v2-design.md`

This document answers every infrastructure question for Harvest: where things run, how they connect, what they cost, and what happens when something breaks. Read this, provision the accounts, and deploy.

---

## 1. Architecture Overview

```
+=========================================================================+
|                         INTERNET / USERS                                 |
+=========================================================================+
          |                                          |
          | (HTTPS, WebSocket)                       | (Push notifications)
          v                                          v
+-------------------+                    +------------------------+
|    World App      |                    |  World Developer API   |
|  (Mobile Client)  |                    |  (notifications)       |
|  +-------------+  |                    +------------------------+
|  | Harvest     |  |                               ^
|  | Mini App    |  |                               |
|  | (WebView)   |  |                               | POST /send
|  +------+------+  |                               |
|         |         |                    +----------+--------------+
|  MiniKit SDK      |                    |                         |
|  - walletAuth     |                    |    Vercel Cron Jobs     |
|  - verify         |                    |    (scan-rewards,       |
|  - sendTransaction|                    |     grant-reminders)    |
+---------+---------+                    +----------+--------------+
          |                                         |
          | HTTPS REST                              | HTTP (internal)
          v                                         v
+=========================================================================+
|                                                                         |
|                    VERCEL  (Pro plan -- free for hackathon)              |
|                                                                         |
|  +---------------------------------------------------------------+     |
|  |              Next.js 15 App (App Router)                      |     |
|  |                                                                |     |
|  |  EDGE NETWORK (Vercel CDN)                                    |     |
|  |  +----------------------------------------------------------+ |     |
|  |  | Static assets: /_next/static/*, favicon, fonts, images   | |     |
|  |  | Edge middleware: session cookie validation                | |     |
|  |  +----------------------------------------------------------+ |     |
|  |                                                                |     |
|  |  SERVERLESS FUNCTIONS (Node.js 20, us-east-1)                 |     |
|  |  +----------------------------------------------------------+ |     |
|  |  | /api/auth/verify       -- World ID proof verification    | |     |
|  |  | /api/auth/session      -- SIWE session creation          | |     |
|  |  | /api/auth/logout       -- Session destruction            | |     |
|  |  | /api/vaults            -- Vault list + stats             | |     |
|  |  | /api/vaults/[addr]/history -- Harvest history per vault  | |     |
|  |  | /api/user/deposits     -- User deposit history           | |     |
|  |  | /api/agent/activity    -- Agent harvest feed             | |     |
|  |  | /api/agent/recommend   -- AI yield recommendation        | |     |
|  |  | /api/claims/prepare    -- Build multicall payload        | |     |
|  |  | /api/claims/confirm    -- Record claim in DB             | |     |
|  |  | /api/notifications/subscribe -- Notification opt-in      | |     |
|  |  | /api/x402/yield-data   -- x402-protected yield data      | |     |
|  |  +----------------------------------------------------------+ |     |
|  |                                                                |     |
|  |  CRON FUNCTIONS (Vercel Cron)                                  |     |
|  |  +----------------------------------------------------------+ |     |
|  |  | /api/cron/harvest      -- Every 4h, harvest all vaults   | |     |
|  |  | /api/cron/scan-rewards -- Every 6h, check reward levels  | |     |
|  |  | /api/cron/snapshot     -- Every 1h, snapshot vault state  | |     |
|  |  +----------------------------------------------------------+ |     |
|  |                                                                |     |
|  +---------------------------------------------------------------+     |
|                                                                         |
+====+==============+==============+==========+==========================+
     |              |              |          |
     | Supabase     | RPC          | Merkl    | DeFi Llama
     | (Postgres)   | (World Chain)| API      | API
     v              v              v          v
+----------+  +-----------+  +----------+  +----------+
| Supabase |  | Alchemy   |  | Merkl    |  | DeFi     |
| Postgres |  | RPC       |  | api.     |  | Llama    |
| + Auth   |  | World     |  | merkl.   |  | coins.   |
| + RLS    |  | Chain     |  | xyz      |  | llama.fi |
|          |  | (480)     |  |          |  |          |
| Tables:  |  |           |  | Reward   |  | Token    |
| users    |  | Read:     |  | balances |  | prices   |
| deposits |  | balanceOf |  | Merkle   |  | (free,   |
| withdraw |  | sharePrice|  | proofs   |  | no key)  |
| harvests |  |           |  |          |  |          |
| snapshots|  | Write:    |  | (free,   |  +----------+
|          |  | harvest() |  | no key)  |
| (free    |  | deposit() |  +----------+
| tier)    |  | withdraw()|
+----------+  |           |
              | (free tier|
              | or $0/mo  |
              | at low    |
              | volume)   |
              +-----------+

              +--------------------------------------------------+
              |          WORLD CHAIN (Chain ID 480)               |
              |                                                    |
              |  Deployed Contracts:                               |
              |  +--------------------+  +---------------------+  |
              |  | HarvestVaultV7     |  | StrategyMorpho      |  |
              |  | (Proxy + Impl)     |  | (Proxy + Impl)      |  |
              |  |                    |  |                      |  |
              |  | deposit()          |  | harvest()            |  |
              |  | withdraw()         |  | deposit()            |  |
              |  | earn()             |  | withdraw()           |  |
              |  | getPricePerShare() |  | balanceOf()          |  |
              |  | setVerified()      |  |                      |  |
              |  +--------------------+  +---------------------+  |
              |                                                    |
              |  External Contracts:                               |
              |  +--------------------+  +---------------------+  |
              |  | MetaMorpho Vault   |  | Merkl Distributor   |  |
              |  | (Re7 USDC)         |  | 0x3Ef3D8bA38...     |  |
              |  | 0xb1E80387Eb...    |  +---------------------+  |
              |  +--------------------+                            |
              |  +--------------------+                            |
              |  | Uniswap V3 Router  |                            |
              |  | 0x091AD9e2e6...    |                            |
              |  +--------------------+                            |
              +--------------------------------------------------+
```

---

## 2. Hosting Decisions with Rationale

### 2.1 Frontend + API: Vercel (Single Deployment)

**Decision:** Deploy the entire Next.js 15 app (frontend + API routes + cron handlers) as a single Vercel project.

**Rationale:**
- The World Mini App template (`@worldcoin/create-mini-app`) scaffolds a Next.js project with Vercel as the assumed deployment target. Zero friction.
- API routes run as serverless functions in the same project. No CORS issues, no separate deployment, no network hop for frontend-to-API calls during SSR.
- Vercel's edge network handles CDN automatically for static assets, fonts, and pre-rendered pages. The mini app loads fast inside World App's WebView.
- Vercel Pro is free for hackathon teams (apply via Vercel for Startups or use a team member's Pro account). Even the Hobby plan handles the traffic for a hackathon demo.

**Region:** `us-east-1` (iad1). Supabase free tier also defaults to us-east-1. Co-locating minimizes latency between serverless functions and the database.

### 2.2 Agent/Harvester: Vercel Cron (NOT a Separate Service)

**Decision:** Run the harvester as a Vercel Cron job that triggers a Next.js API route, not as a separate Railway/Render long-running process.

**Rationale:**

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Vercel Cron** | Zero extra infra, same codebase, same env vars, same deployment. Cron triggers API route which runs as serverless function (max 300s on Pro, 60s on Hobby). | 300-second timeout. Cannot run a persistent process. | **Winner for hackathon** |
| **Railway** | Long-running process, no timeout. Good for production. | Extra service to manage, separate deploy, separate env vars, separate monitoring. $5/mo after trial. | Overkill for hackathon |
| **Render** | Same as Railway. Free tier has 750h/mo. | Cold starts on free tier (50s). Separate service. | Unnecessary complexity |
| **GitHub Actions** | Free (2000 min/mo). Can run on schedule. | Not a real hosting platform. Slow cold start. Awkward for accessing env vars securely. | Hacky |

**Why Vercel Cron works for the harvester:**

1. The harvest operation is a discrete, bounded task: check Merkl rewards, build proof, send one transaction, wait for receipt, log to Supabase. This completes in 10-30 seconds, well within even the 60-second Hobby timeout.
2. The agent does not need to be a persistent process. It runs every 4 hours, does its work, and exits. This is exactly what cron jobs are for.
3. Everything stays in one codebase. The harvest logic in `/api/cron/harvest/route.ts` imports the same `lib/merkl.ts`, `lib/viem-client.ts`, and `lib/supabase.ts` that the rest of the app uses. No code duplication.

**Cron configuration in `vercel.json`:**

```json
{
  "crons": [
    {
      "path": "/api/cron/harvest",
      "schedule": "0 */4 * * *"
    },
    {
      "path": "/api/cron/snapshot",
      "schedule": "0 * * * *"
    },
    {
      "path": "/api/cron/scan-rewards",
      "schedule": "0 */6 * * *"
    }
  ]
}
```

**Security:** Each cron route validates `Authorization: Bearer <CRON_SECRET>` header. Vercel injects this automatically for cron-triggered requests. External callers cannot trigger harvests.

**Fallback plan:** If the harvest operation ever exceeds 300 seconds (unlikely -- it is one RPC call plus one transaction), spin up a Railway service that runs the same `strategist.ts` code on a `setInterval`. This takes 15 minutes to set up and requires zero code changes, only a `Dockerfile` and one env var file.

### 2.3 Database: Supabase (Free Tier)

**Decision:** Supabase managed Postgres. Free tier.

**Rationale:**
- 500 MB database storage (we will use <1 MB for a hackathon).
- 5 GB bandwidth (more than enough).
- 50K monthly active users (we will have <100).
- Built-in Row Level Security for the tables that need it.
- Realtime subscriptions available if we want to push harvest events to the frontend (stretch goal).
- Service role key for server-side access, anon key for client-side read-only access.

**Region:** `us-east-1` to co-locate with Vercel functions.

### 2.4 RPC Provider: Alchemy (Free Tier)

**Decision:** Alchemy for World Chain RPC.

**Rationale:**
- Alchemy has a dedicated World Chain endpoint (`worldchain-mainnet.g.alchemy.com`).
- Free tier: 300M compute units/month. A harvest transaction uses ~100 CU. We will use <1% of the quota.
- Fallback: Tenderly public gateway (`worldchain-mainnet.gateway.tenderly.co`) requires no key but has no SLA. Use as a backup in viem client configuration.

```typescript
// viem client with fallback
const transport = fallback([
  http(`https://worldchain-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`),
  http("https://worldchain-mainnet.gateway.tenderly.co"),
]);
```

---

## 3. Data Flows

### 3.1 Deposit Flow

```
User taps "deposit 100 USDC" in terminal
         |
         v
[1] Frontend builds multicall via MiniKit
    MiniKit.commandsAsync.sendTransaction({
      transaction: [
        { address: USDC, fn: "approve", args: [VAULT, 100e6] },
        { address: VAULT, fn: "deposit", args: [100e6] },
      ]
    })
         |
         v
[2] World App prompts user to confirm
    User taps "Confirm" in World App wallet UI
         |
         v
[3] World App submits TX to World Chain
    Atomic multicall: approve + deposit in single TX
    The vault mints harvestUSDC shares to user
    The vault calls earn() to push funds to strategy
    Strategy deposits into MetaMorpho vault
         |
         v
[4] Frontend receives TX hash from MiniKit callback
    finalPayload.transaction_id = "0xabc..."
         |
         v
[5] Frontend calls POST /api/claims/confirm
    Body: { txHash, vaultAddress, amount }
         |
         v
[6] API route:
    a. Fetches TX receipt from RPC (confirms success)
    b. Reads Deposit event from logs (extracts shares)
    c. Fetches USDC price from DeFi Llama
    d. Inserts row into Supabase `deposits` table
    e. Returns { success: true, shares, txHash }
         |
         v
[7] Frontend shows success in terminal:
    "> deposit confirmed. 100 USDC -> 99.75 harvestUSDC"
    "> tx: 0xabc... [view on worldscan]"
```

**Key points:**
- The transaction itself goes through World App's wallet, NOT through our API. Our API never touches user funds.
- The API only records the deposit after confirming the TX succeeded on-chain. This is an indexing step, not a critical path.
- If the API recording fails, the deposit still happened on-chain. The frontend can retry the confirm call, or the snapshot cron will pick it up.

### 3.2 Harvest Flow (Agent Autocompounding)

```
Vercel Cron fires at 00:00, 04:00, 08:00, 12:00, 16:00, 20:00 UTC
         |
         v
[1] GET /api/cron/harvest
    Validates CRON_SECRET header
         |
         v
[2] For each vault in VAULT_CONFIGS:
    a. Fetch pending Merkl rewards for strategy address
       GET https://api.merkl.xyz/v4/users/{strategyAddr}/rewards?chainId=480
       (x402 payment header signed by agent wallet)
         |
         v
[3] Decision gate:
    IF rewards_usd < $5 -> skip, log "below threshold"
    IF rewards_usd >= $5 -> proceed to harvest
         |
         v
[4] Fetch Merkl claim proofs:
    GET https://api.merkl.xyz/v4/users/{strategyAddr}/claims?chainId=480
    Returns: { tokens, amounts, proofs }
         |
         v
[5] Build harvest() calldata:
    encodeFunctionData({
      abi: STRATEGY_ABI,
      functionName: "harvest",
      args: [merklUsers, merklTokens, merklAmounts, merklProofs]
    })
         |
         v
[6] Sign and submit TX from agent wallet:
    walletClient.writeContract({
      address: strategyAddress,
      abi: STRATEGY_ABI,
      functionName: "harvest",
      args: [...]
    })
    Agent wallet pays gas in ETH on World Chain
         |
         v
[7] On-chain execution:
    a. StrategyMorpho.harvest() claims Merkl rewards (WLD)
    b. Swaps WLD -> WETH -> USDC via Uniswap V3
    c. Charges fees (3% protocol, 1% harvester, 0.5% strategist)
    d. Deposits remaining USDC into MetaMorpho vault
    e. Share price increases for all vault depositors
    f. Emits Harvest(caller, wantEarned, fee) event
         |
         v
[8] Wait for TX receipt:
    publicClient.waitForTransactionReceipt({ hash: txHash })
         |
         v
[9] Log to Supabase:
    a. INSERT into `harvests` table (vault, rewards, gas, txHash)
    b. Read new share price: vault.getPricePerFullShare()
    c. Read total assets: vault.balance()
    d. INSERT into `vault_snapshots` table (sharePrice, totalAssets, apy)
         |
         v
[10] Optional: trigger notifications
     For users with notification_enabled = true
     AND their deposit value increased by > threshold:
     POST World Developer API /notify
         |
         v
[11] Return 200 OK to Vercel Cron
     Body: { harvested: 2, skipped: 0, totalCompounded: "$42.15" }
```

**Key points:**
- The entire flow runs in a single serverless function invocation. No persistent process needed.
- The agent wallet's private key is loaded from `AGENT_PRIVATE_KEY` env var (see Section 4 for security details).
- If any vault harvest fails, the error is caught and logged, but other vaults still proceed.
- The Merkl API and proof fetching are the slowest steps (~2-3 seconds each). The actual TX submission and confirmation on World Chain takes ~2-5 seconds.

### 3.3 Withdrawal Flow

```
User taps "withdraw 50 harvestUSDC" in terminal
         |
         v
[1] Frontend builds withdraw TX via MiniKit
    MiniKit.commandsAsync.sendTransaction({
      transaction: [{
        address: VAULT,
        fn: "withdraw",
        args: [50e18]  // shares in 18 decimals
      }]
    })
         |
         v
[2] World App prompts confirmation -> user taps Confirm
         |
         v
[3] On-chain: vault burns shares, pulls USDC from strategy,
    sends USDC to user wallet
         |
         v
[4] Frontend receives TX hash, calls POST /api/withdrawals/confirm
         |
         v
[5] API logs withdrawal to Supabase `withdrawals` table
```

### 3.4 Read Flow (Dashboard Load)

```
User opens Harvest in World App
         |
         v
[1] Next.js SSR on Vercel Edge:
    Renders shell HTML + hydration data
    Static assets served from Vercel CDN (global edge)
         |
         v
[2] Client hydrates, checks session cookie:
    GET /api/auth/session
    If no session -> trigger walletAuth + verify flow
    If valid session -> proceed to load data
         |
         v
[3] Client fetches vault data (parallel requests):
    GET /api/vaults -> vault list + stats (from Supabase snapshots)
    GET /api/agent/activity -> recent harvests (from Supabase)
    GET /api/user/deposits -> user's positions (from Supabase)
         |
         v
[4] All three API routes:
    a. Query Supabase Postgres (co-located in us-east-1)
    b. Latency: ~10-30ms per query
    c. No on-chain reads needed (snapshots are pre-cached by cron)
         |
         v
[5] Client renders terminal UI with live data
    SWR revalidation on 30-second interval for dashboard freshness
```

**Why this is fast:** The dashboard does NOT make RPC calls. All on-chain data (share prices, TVL, APY) is pre-indexed into Supabase by the snapshot cron. API routes are pure database reads. This means the dashboard loads in <200ms after the initial page load.

---

## 4. Agent Private Key Security

### 4.1 The Problem

The agent needs a private key to sign harvest transactions. This key controls an EOA that:
- Is registered as the keeper on each StrategyMorpho contract
- Holds a small ETH balance for gas (~0.01 ETH, worth ~$25)
- Receives 1% harvester fee from each harvest

The key must be available to the Vercel serverless function at runtime.

### 4.2 Hackathon Approach (Acceptable Risk)

**Decision:** Store `AGENT_PRIVATE_KEY` as a Vercel environment variable, scoped to Production only.

**Why this is acceptable for a hackathon:**
- The wallet holds <$50 in ETH for gas. The max loss from a key leak is that amount.
- Vercel environment variables are encrypted at rest and injected at runtime. They are not exposed in build logs or client bundles (no `NEXT_PUBLIC_` prefix).
- The key is only used in `/api/cron/harvest`, which is a server-side route that cannot be called by external clients (protected by `CRON_SECRET`).
- This is the same approach used by every Beefy keeper bot and most DeFi backend services.

**Setup:**
```
Vercel Dashboard -> Project Settings -> Environment Variables

AGENT_PRIVATE_KEY = 0x...    (Production only, NOT Preview)
AGENT_WALLET_ADDRESS = 0x... (Production only)
CRON_SECRET = <random>       (Production only)
```

### 4.3 Production Approach (Post-Hackathon)

For production, upgrade to one of these:

| Approach | How | Cost |
|----------|-----|------|
| **AWS KMS** | Store key in KMS, sign via API call instead of loading raw key | ~$1/mo |
| **AgentKit CDP Wallet** | Let AgentKit manage the wallet via Coinbase Developer Platform. Private key never leaves CDP infrastructure. | Free tier |
| **Vault (HashiCorp)** | Self-hosted secrets manager | Complex, overkill |

The recommended production path is **AgentKit CDP Wallet**. The spec already references AgentKit for wallet management. In production, replace:

```typescript
// Hackathon: raw private key
const account = privateKeyToAccount(process.env.AGENT_PRIVATE_KEY);

// Production: AgentKit managed wallet
const agentkit = await AgentKit.from({
  cdpApiKeyId: process.env.CDP_API_KEY_ID,
  cdpApiKeySecret: process.env.CDP_API_KEY_SECRET,
  networkId: "worldchain-mainnet",
});
const account = agentkit.getAccount();
```

---

## 5. Monitoring & Alerting

### 5.1 How Do We Know If the Agent Stops Working?

Five layers of monitoring, from cheapest to most sophisticated:

#### Layer 1: Supabase Query (Zero Cost)

The simplest check: query the `harvests` table for the most recent entry.

```sql
SELECT timestamp, vault_address, rewards_compounded_usd
FROM harvests
ORDER BY timestamp DESC
LIMIT 1;
```

If the latest harvest is older than 8 hours (2x the 4-hour interval), something is wrong. This query can be run manually or by a cron job.

#### Layer 2: Health Check Endpoint (Zero Cost)

Add a public health check route:

```typescript
// /api/health/route.ts
export async function GET() {
  const { data } = await supabase
    .from("harvests")
    .select("timestamp")
    .order("timestamp", { ascending: false })
    .limit(1)
    .single();

  const lastHarvest = data?.timestamp ? new Date(data.timestamp) : null;
  const hoursAgo = lastHarvest
    ? (Date.now() - lastHarvest.getTime()) / 3600000
    : Infinity;

  const healthy = hoursAgo < 8;

  return NextResponse.json({
    status: healthy ? "ok" : "stale",
    lastHarvest: lastHarvest?.toISOString() || "never",
    hoursAgo: Math.round(hoursAgo * 10) / 10,
    agentWallet: AGENT_WALLET_ADDRESS,
  }, { status: healthy ? 200 : 503 });
}
```

Point an external uptime monitor (UptimeRobot free tier, or Better Stack free tier) at `/api/health`. If it returns 503, you get an email/Slack/SMS alert.

#### Layer 3: Vercel Cron Logs (Zero Cost)

Vercel logs all cron invocations in the dashboard under **Deployments > Functions > Cron**. You can see:
- Whether the cron fired on schedule
- The function duration
- Any errors thrown
- The response body

Check these logs if the health check goes stale.

#### Layer 4: Agent Self-Reporting to Supabase (Zero Cost)

The harvest cron already logs to the `harvests` table on success. Add failure logging:

```typescript
// In the cron handler catch block:
catch (error) {
  await supabase.from("agent_errors").insert({
    vault_address: vault.vaultAddress,
    error_message: error.message,
    error_stack: error.stack?.slice(0, 1000),
    timestamp: new Date().toISOString(),
  });
}
```

The dashboard can show a red indicator if `agent_errors` has recent entries.

#### Layer 5: On-Chain Heartbeat Check (Zero Cost)

As a last resort, the share price itself is the heartbeat. If `getPricePerFullShare()` has not changed in 24 hours but the Morpho vault is generating yield, the agent is not compounding. The snapshot cron captures this:

```typescript
// In /api/cron/snapshot
const currentPrice = await vault.getPricePerFullShare();
const previousPrice = latestSnapshot.share_price;

if (currentPrice === previousPrice && hoursSinceLastHarvest > 24) {
  // Agent may be stuck -- log warning
  await supabase.from("agent_errors").insert({
    error_message: "Share price unchanged for 24h, agent may be stuck",
    ...
  });
}
```

### 5.2 Agent Wallet Balance Monitoring

The agent wallet needs ETH for gas. If it runs out, harvests fail silently. The snapshot cron should check:

```typescript
const agentBalance = await publicClient.getBalance({
  address: AGENT_WALLET_ADDRESS,
});

if (agentBalance < parseEther("0.002")) {
  // Low gas warning -- log to Supabase and/or send notification
  await supabase.from("agent_errors").insert({
    error_message: `Agent wallet low on gas: ${formatEther(agentBalance)} ETH`,
    ...
  });
}
```

### 5.3 Monitoring Summary

| Signal | Where | Check Frequency | Alert Method |
|--------|-------|-----------------|--------------|
| Last harvest age | Supabase `harvests` table | Every hour (via `/api/health`) | UptimeRobot -> Slack/email |
| Cron execution | Vercel dashboard | Manual / on-demand | Visual check |
| Agent errors | Supabase `agent_errors` table | Dashboard polls every 30s | Red indicator in UI |
| Share price stale | Supabase `vault_snapshots` | Every hour (snapshot cron) | Supabase row + UI indicator |
| Agent wallet ETH | RPC `getBalance` | Every hour (snapshot cron) | Supabase row + UI indicator |
| Vercel function errors | Vercel Logs / Log Drain | Continuous | Vercel alerting (Pro tier) |

---

## 6. CDN & Edge Considerations

### 6.1 What Vercel Handles Automatically

Vercel's edge network gives us global CDN for free. No configuration needed for:

- **Static assets** (`/_next/static/*`): JS bundles, CSS, fonts, images. Immutable hashes, cached indefinitely at 300+ edge locations worldwide.
- **Pre-rendered pages**: If we statically generate any pages at build time, they are served from the edge.
- **Image optimization**: `next/image` resizes and serves WebP/AVIF from the edge if we use it.

### 6.2 Edge Middleware for Session Validation

Deploy a lightweight Edge Middleware that validates the session cookie before API routes execute. This runs at the edge (closest to the user), rejecting unauthenticated requests before they hit the serverless function:

```typescript
// middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  // Skip auth for public routes
  const publicPaths = ["/api/health", "/api/vaults", "/api/cron/"];
  if (publicPaths.some((p) => request.nextUrl.pathname.startsWith(p))) {
    return NextResponse.next();
  }

  // Check session cookie exists for protected API routes
  if (request.nextUrl.pathname.startsWith("/api/")) {
    const session = request.cookies.get("harvest_session");
    if (!session) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: "/api/:path*",
};
```

### 6.3 API Response Caching

For read-heavy endpoints, add `Cache-Control` headers so Vercel's CDN caches responses:

```typescript
// /api/vaults/route.ts
export async function GET() {
  const vaults = await fetchVaultData();

  return NextResponse.json({ vaults }, {
    headers: {
      "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300",
    },
  });
}
```

| Endpoint | Cache Strategy | Reason |
|----------|---------------|--------|
| `GET /api/vaults` | `s-maxage=60` (1 min) | Vault stats change only on harvest (every 4h) |
| `GET /api/agent/activity` | `s-maxage=30` (30s) | Harvest events are infrequent |
| `GET /api/vaults/[addr]/history` | `s-maxage=60` (1 min) | Historical data, rarely changes |
| `GET /api/user/deposits` | No cache | User-specific, authenticated |
| `POST /*` | No cache | Mutations |

### 6.4 World App WebView Considerations

The mini app runs inside World App's WebView (WKWebView on iOS, Android WebView). Key considerations:

- **No service worker**: WebViews have limited service worker support. Do not rely on PWA caching.
- **No localStorage for auth**: Use HttpOnly cookies. The WebView shares the cookie jar with the embedding app context.
- **Viewport**: The WebView is full-screen minus World App's chrome. Use `100dvh` for height, not `100vh`.
- **Performance**: WebView JS engine is slower than a desktop browser. Keep the bundle small. Tree-shake aggressively. The terminal UI with monospace text is inherently lightweight.

---

## 7. Cost Analysis -- All Free Tier for Hackathon

### 7.1 Service-by-Service Breakdown

| Service | Tier | Limit | Our Usage | Monthly Cost |
|---------|------|-------|-----------|--------------|
| **Vercel** | Hobby (or Pro via hackathon) | 100GB bandwidth, 100h function execution | <1GB bandwidth, <1h function time | **$0** |
| **Supabase** | Free | 500MB DB, 5GB bandwidth, 50K MAU | <1MB DB, <100 users | **$0** |
| **Alchemy** | Free | 300M compute units/month | <100K CU/month | **$0** |
| **Merkl API** | Free | No published rate limits | ~6 calls/day (per vault) | **$0** |
| **DeFi Llama** | Free | No key required, generous limits | ~24 calls/day (hourly snapshots) | **$0** |
| **World Developer API** | Free | Included with app registration | <100 notifications/day | **$0** |
| **UptimeRobot** | Free | 50 monitors, 5-min checks | 1 monitor | **$0** |
| **Agent wallet gas** | N/A | N/A | ~6 harvests/day * $0.05 gas = $0.30/day | **~$9/month** |
| **Domain (optional)** | N/A | Vercel provides `*.vercel.app` | Use default Vercel URL | **$0** |

### 7.2 Total Cost

| Item | Cost |
|------|------|
| Infrastructure | **$0/month** |
| Agent gas (World Chain) | **~$9/month** (fund wallet with 0.01 ETH to start) |
| **Total** | **~$9/month** |

The only real cost is ETH for the agent wallet to pay gas on harvest transactions. For the hackathon, pre-fund the wallet with 0.01 ETH (~$25) and it will last weeks.

### 7.3 Free Tier Gotchas

| Service | Gotcha | Mitigation |
|---------|--------|------------|
| **Vercel Hobby** | Cron jobs limited to 1/day on Hobby. Need Pro for `*/4 * * *`. | Use Vercel Pro (free for hackathon teams) or degrade to 1x/day harvest on Hobby. Alternative: use an external cron service (cron-job.org, free) to hit the harvest endpoint. |
| **Vercel Hobby** | Serverless function timeout: 60 seconds | Harvest should complete in 10-30s. If it doesn't, optimize or switch to Pro (300s timeout). |
| **Supabase Free** | Database pauses after 1 week of inactivity | Keep the cron jobs running. They query Supabase every hour, preventing pause. |
| **Alchemy Free** | Rate limit: 330 CU/sec | We make ~5 RPC calls per harvest. No risk of hitting this. |

### 7.4 Vercel Hobby vs. Pro for Cron

This is the one decision that matters. Vercel Hobby only allows **one cron job per day**. We need three crons running at sub-daily intervals.

**Options:**

1. **Vercel Pro** (recommended): Free via Vercel for Startups program or a team member's existing Pro plan. Supports up to 40 cron jobs, minimum interval of 1 minute.

2. **External cron trigger**: Use [cron-job.org](https://cron-job.org) (free, up to 4 jobs) or [EasyCron](https://www.easycron.com) (free, up to 1 job) to make GET requests to the cron endpoints with the `CRON_SECRET` header. This works on Vercel Hobby but adds an external dependency.

3. **Degrade to manual**: For the hackathon demo, trigger harvests manually via `curl` before the demo. Not sustainable but works for a 5-minute demo.

**Recommendation:** Get on Vercel Pro. It is free for hackathon/startup teams and eliminates this constraint entirely.

---

## 8. Environment Variable Map

Complete list of all environment variables, where they are used, and where they come from.

```
+------------------------------------------------------------------+
|                    VERCEL ENVIRONMENT VARIABLES                    |
+------------------------------------------------------------------+
| Variable                        | Used By          | Source       |
|---------------------------------|------------------|--------------|
| NEXT_PUBLIC_APP_ID              | Frontend+API     | World Portal |
| WORLD_API_KEY                   | API (notifs)     | World Portal |
| NEXT_PUBLIC_SUPABASE_URL        | Frontend+API     | Supabase     |
| NEXT_PUBLIC_SUPABASE_ANON_KEY   | Frontend         | Supabase     |
| SUPABASE_SERVICE_ROLE_KEY       | API+Cron         | Supabase     |
| WORLD_CHAIN_RPC_URL             | API+Cron         | Alchemy      |
| JWT_SECRET                      | API (sessions)   | Self-gen     |
| NULLIFIER_HMAC_SECRET           | API (privacy)    | Self-gen     |
| AGENT_PRIVATE_KEY               | Cron (harvest)   | Self-gen     |
| AGENT_WALLET_ADDRESS            | Cron (monitor)   | Derived      |
| CRON_SECRET                     | Cron (auth)      | Vercel auto  |
| OPENAI_API_KEY                  | API (recommend)  | OpenAI       |
| CDP_API_KEY_ID                  | Cron (AgentKit)  | Coinbase CDP |
| CDP_API_KEY_SECRET              | Cron (AgentKit)  | Coinbase CDP |
+------------------------------------------------------------------+

NEXT_PUBLIC_ prefix = exposed to browser (safe for public keys)
No prefix = server-side only (secrets)
```

---

## 9. Deployment Checklist

### 9.1 One-Time Setup (Before First Deploy)

```
[ ] Create Vercel account, link to GitHub repo
[ ] Create Supabase project in us-east-1
[ ] Create Alchemy account, get World Chain API key
[ ] Register app in World Developer Portal
[ ] Generate agent wallet (cast wallet new)
[ ] Fund agent wallet with 0.01 ETH on World Chain
[ ] Deploy contracts to World Chain Sepolia (forge script)
[ ] Whitelist contract addresses in World Developer Portal
[ ] Run database migration (SQL from harvest-v2-spec.md Section 8.2)
[ ] Set all environment variables in Vercel dashboard
[ ] Deploy to Vercel (git push to main)
[ ] Verify cron jobs appear in Vercel dashboard
[ ] Test /api/health endpoint returns 200
[ ] Set up UptimeRobot monitor on /api/health
```

### 9.2 Pre-Demo Checklist

```
[ ] Verify agent wallet has sufficient ETH
[ ] Check /api/health returns status: "ok"
[ ] Trigger a manual harvest: curl with CRON_SECRET
[ ] Verify harvest logged in Supabase
[ ] Open mini app in World App simulator
[ ] Complete a test deposit on Sepolia
[ ] Verify deposit appears in terminal history
```

---

## 10. Architecture Diagram -- Simplified (For Presentations)

```
                    +------------------+
                    |   World App      |
                    |   (40M users)    |
                    +--------+---------+
                             |
                     MiniKit SDK
                             |
                    +--------v---------+
                    |    Vercel        |
                    |  +------------+  |
                    |  | Next.js 15 |  |
                    |  | Frontend + |  |
                    |  | API Routes |  |
                    |  | + Cron     |  |
                    |  +-----+------+  |
                    +--------+---------+
                       /     |     \
                      /      |      \
              +------+  +----+----+  +--------+
              |Supa- |  | World   |  | Merkl  |
              |base  |  | Chain   |  | API    |
              |(data)|  |(contracts) |(rewards)|
              +------+  +---------+  +--------+

    ONE Vercel deployment. ONE database. ONE chain.
    Agent runs as a cron job inside the same deployment.
    Total infrastructure cost: $0/month (+ ~$9 gas).
```

---

## 11. Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Vercel Hobby cron limitation | High (if no Pro) | Harvests run 1x/day instead of 6x | Get Vercel Pro or use external cron trigger |
| Agent wallet runs out of gas | Medium | Harvests stop until refunded | Monitor via snapshot cron, alert at <0.002 ETH |
| Merkl API down or rate-limited | Low | Cannot fetch proofs, harvest skipped | Graceful skip + retry next cycle. Log error. |
| Supabase free tier pauses DB | Low (cron prevents it) | Dashboard shows no data | Cron jobs query Supabase hourly, preventing inactivity |
| Vercel function timeout (60s Hobby) | Low | Harvest fails mid-execution | Harvest is 10-30s. Use Pro for 300s safety margin. |
| AGENT_PRIVATE_KEY leaked | Very Low | Max loss ~$50 in ETH | Only in Vercel env vars (encrypted). Wallet holds minimal funds. Rotate key and re-register keeper on strategy. |
| World Chain RPC outage | Very Low | All on-chain operations fail | Fallback to Tenderly public RPC. Retry next cron cycle. |

---

## 12. Post-Hackathon Scaling Path

When Harvest graduates from hackathon to production, here is the upgrade path:

| Component | Hackathon | Production |
|-----------|-----------|------------|
| Vercel | Pro (free trial) | Pro ($20/mo) or Enterprise |
| Supabase | Free tier | Pro ($25/mo) for point-in-time recovery + daily backups |
| Agent hosting | Vercel Cron | Railway ($5/mo) for long-running process with retry logic |
| Agent wallet | Raw private key in env var | AgentKit CDP Wallet (key never leaves CDP) |
| RPC | Alchemy free tier | Alchemy Growth ($49/mo) for higher throughput + webhooks |
| Monitoring | UptimeRobot free | Better Stack or PagerDuty for on-call alerts |
| Secrets | Vercel env vars | AWS Secrets Manager or HashiCorp Vault |
| CDN | Vercel automatic | Vercel automatic (same, scales with traffic) |
| Database backups | None | Supabase Pro daily backups + manual pg_dump weekly |
