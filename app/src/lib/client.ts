// ---------------------------------------------------------------------------
// Client-side helpers that fetch from our server-side API routes.
// The viem client + RPC key live server-side only (in /api/balances).
// ---------------------------------------------------------------------------

export interface Balances {
  usdcBalance: bigint;
  vaultShares: bigint;
  pricePerShare: bigint;
  tvl: bigint;
}

export async function getBalances(walletAddress: string): Promise<Balances> {
  const res = await fetch(`/api/balances?wallet=${walletAddress}`);
  if (!res.ok) throw new Error("Failed to fetch balances");
  const data = await res.json();
  return {
    usdcBalance: BigInt(data.usdcBalance),
    vaultShares: BigInt(data.vaultShares),
    pricePerShare: BigInt(data.pricePerShare),
    tvl: BigInt(data.tvl),
  };
}

export async function getVaultTvl(): Promise<bigint> {
  const res = await fetch("/api/balances");
  if (!res.ok) throw new Error("Failed to fetch TVL");
  const data = await res.json();
  return BigInt(data.tvl);
}

// ─── Agent / Harvester ──────────────────────────────────────────────────────

export type { HarvestRecord } from "./harvester";

export interface AgentStatus {
  status: "active" | "idle";
  lastHarvest: import("./harvester").HarvestRecord | null;
  harvests: import("./harvester").HarvestRecord[];
  pendingRewards: { token: string; amount: string; usdValue: number } | null;
  nextCheck: string;
  balanceOfPool?: string;
  uniswapQuote?: { expectedOutput: string; gasFeeUSD: string; priceImpact: string; routing: string } | null;
  streaming?: { lockedUsd: string; unlocksInMs: number } | null;
}

export interface HarvestResult {
  success: boolean;
  txHash?: string;
  claimTxHash?: string;
  rewardsClaimed?: string;
  wantEarned?: string;
  newSharePrice?: string;
  oldSharePrice?: string;
  reason?: string;
  message?: string;
  uniswapQuote?: { expectedOutput: string; gasFeeUSD: string; priceImpact: string; routing: string } | null;
}

export async function getAgentStatus(): Promise<AgentStatus> {
  const res = await fetch("/api/agent/status");
  if (!res.ok) throw new Error("Failed to fetch agent status");
  return res.json();
}

export async function triggerHarvest(): Promise<HarvestResult> {
  const res = await fetch("/api/agent/harvest", { method: "POST" });
  try {
    return await res.json();
  } catch {
    return { success: false, reason: "tx_failed", message: `HTTP ${res.status}` };
  }
}
