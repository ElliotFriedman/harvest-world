// ---------------------------------------------------------------------------
// Harvest Agent — Merkl rewards fetcher and WLD price fetcher
// ---------------------------------------------------------------------------

import { WLD_ADDRESS } from "./config.js";

// ─── Types ───────────────────────────────────────────────────────────────────

export interface MerklReward {
  token: string;
  symbol: string;
  amount: bigint;
  claimed: bigint;
  unclaimed: bigint;
  proofs: string[];
}

// ─── Merkl rewards fetcher ───────────────────────────────────────────────────

export async function fetchMerklRewards(
  strategyAddress: string
): Promise<MerklReward[]> {
  const url = `https://api.merkl.xyz/v4/users/${strategyAddress}/rewards?chainId=480`;
  console.log(`  Fetching Merkl rewards from ${url}`);

  const res = await fetch(url);

  if (!res.ok) {
    console.error(`  Merkl API error: ${res.status} ${res.statusText}`);
    return [];
  }

  const data = await res.json();
  const rewards: MerklReward[] = [];

  // Merkl v4 response shape varies — handle both flat array and chain-keyed object
  let entries: any[] = [];
  if (Array.isArray(data)) {
    entries = data;
  } else if (typeof data === "object" && data !== null) {
    // Merkl v4: keyed by chain ID, e.g. { "480": { "campaignData": [...] } }
    const chainData = (data as any)["480"] ?? Object.values(data)[0];
    if (Array.isArray(chainData)) {
      entries = chainData;
    } else if (chainData?.campaignData) {
      entries = chainData.campaignData;
    } else if (chainData?.rewards) {
      entries = Array.isArray(chainData.rewards)
        ? chainData.rewards
        : Object.values(chainData.rewards);
    }
  }

  for (const entry of entries) {
    if (!entry) continue;
    const tokenAddr = entry?.token?.address ?? entry?.tokenAddress ?? "";
    const symbol = entry?.token?.symbol ?? entry?.symbol ?? "???";
    const totalAmount = BigInt(entry?.amount ?? "0");
    const claimedAmount = BigInt(entry?.claimed ?? "0");
    const unclaimed = totalAmount - claimedAmount;
    const proofs: string[] = entry?.proofs ?? [];

    if (unclaimed > 0n) {
      rewards.push({
        token: tokenAddr,
        symbol,
        amount: totalAmount,
        claimed: claimedAmount,
        unclaimed,
        proofs,
      });
    }
  }

  return rewards;
}

// ─── WLD price fetcher ───────────────────────────────────────────────────────

let cachedWldPrice: { price: number; fetchedAt: number } | null = null;
const PRICE_CACHE_MS = 5 * 60_000; // 5 minutes

export async function fetchWldPrice(): Promise<number> {
  if (cachedWldPrice && Date.now() - cachedWldPrice.fetchedAt < PRICE_CACHE_MS) {
    return cachedWldPrice.price;
  }

  try {
    const url = `https://coins.llama.fi/prices/current/worldchain:${WLD_ADDRESS}`;
    const res = await fetch(url);

    if (!res.ok) {
      console.error(`  DeFi Llama price error: ${res.status}`);
      return cachedWldPrice?.price ?? 0.89;
    }

    const data = await res.json();
    const key = `worldchain:${WLD_ADDRESS}`.toLowerCase();
    const price = data?.coins?.[key]?.price ?? 0.89;

    cachedWldPrice = { price, fetchedAt: Date.now() };
    return price;
  } catch {
    return cachedWldPrice?.price ?? 0.89;
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

export function formatTokenAmount(raw: bigint, decimals = 18): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = raw / divisor;
  const frac = raw % divisor;
  const fracStr = frac.toString().padStart(decimals, "0").slice(0, 4);
  return `${whole}.${fracStr}`;
}
