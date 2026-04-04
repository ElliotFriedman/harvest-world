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

export interface HarvestRecord {
  timestamp: string;
  txHash: string;
  wantEarned: string;
  rewardsClaimed: string;
}

export interface AgentStatus {
  status: "active" | "idle";
  lastHarvest: HarvestRecord | null;
  harvests: HarvestRecord[];
  pendingRewards: { token: string; amount: string; usdValue: number } | null;
  nextCheck: string;
}

export interface HarvestResult {
  success: boolean;
  txHash?: string;
  rewardsClaimed?: string;
  wantEarned?: string;
  newSharePrice?: string;
  oldSharePrice?: string;
  reason?: string;
  message?: string;
}

export async function getAgentStatus(): Promise<AgentStatus> {
  const res = await fetch("/api/agent/status");
  if (!res.ok) throw new Error("Failed to fetch agent status");
  return res.json();
}

export async function triggerHarvest(): Promise<HarvestResult> {
  const res = await fetch("/api/agent/harvest", { method: "POST" });
  return res.json();
}
