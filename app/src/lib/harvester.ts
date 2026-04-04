// ---------------------------------------------------------------------------
// Shared harvester module — constants, ABIs, Merkl/price fetchers, in-memory store.
// Used by /api/agent/status and /api/agent/harvest routes.
// ---------------------------------------------------------------------------

export const STRATEGY_ADDRESS = (
  process.env.NEXT_PUBLIC_STRATEGY_ADDRESS ?? "0x313ba1d5d5aa1382a80ba839066a61d33c110489"
) as `0x${string}`;
export const VAULT_ADDRESS = (
  process.env.NEXT_PUBLIC_VAULT_ADDRESS ?? "0x512ce44e4f69a98bc42a57ced8257e65e63cd74f"
) as `0x${string}`;
export const WLD_ADDRESS = "0x2cFc85d8E48F8EAB294be644d9E25C3030863003" as const;

// ─── ABIs ─────────────────────────────────────────────────────────────────────

export const strategyAbi = [
  {
    name: "claim",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_tokens", type: "address[]" },
      { name: "_amounts", type: "uint256[]" },
      { name: "_proofs", type: "bytes32[][]" },
    ],
    outputs: [],
  },
  {
    name: "harvest",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "callFeeRecipient", type: "address" }],
    outputs: [],
  },
  {
    name: "balanceOfPool",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export const vaultAbi = [
  {
    name: "getPricePerFullShare",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "balance",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

// ─── Types ────────────────────────────────────────────────────────────────────

export interface HarvestRecord {
  timestamp: string;
  txHash: string;
  wantEarned: string;
  rewardsClaimed: string;
}

export interface MerklReward {
  token: string;
  symbol: string;
  amount: bigint;
  claimed: bigint;
  unclaimed: bigint;
  proofs: string[];
}

// ─── In-memory harvest store (seeded with demo data) ──────────────────────────

function seedDemoHarvests(): HarvestRecord[] {
  const now = Date.now();
  return [
    {
      timestamp: new Date(now - 22 * 3600_000).toISOString(), // ~22h ago
      txHash: "0xa1b2c3d4e5f60718293a4b5c6d7e8f9001122334455667788990011223344556",
      wantEarned: "42.18 USDC",
      rewardsClaimed: "47.3 WLD",
    },
    {
      timestamp: new Date(now - 16 * 3600_000).toISOString(), // ~16h ago
      txHash: "0xb2c3d4e5f6071829304a5b6c7d8e9f0011223344556677889900112233445567",
      wantEarned: "28.65 USDC",
      rewardsClaimed: "32.1 WLD",
    },
    {
      timestamp: new Date(now - 10 * 3600_000).toISOString(), // ~10h ago
      txHash: "0xc3d4e5f607182930415a6b7c8d9e0f01112233445566778899001122334455ab",
      wantEarned: "35.91 USDC",
      rewardsClaimed: "40.2 WLD",
    },
    {
      timestamp: new Date(now - 4 * 3600_000).toISOString(), // ~4h ago
      txHash: "0xd4e5f60718293041526a7b8c9d0e1f02112233445566778899001122334455cd",
      wantEarned: "19.44 USDC",
      rewardsClaimed: "21.8 WLD",
    },
  ];
}

export const harvestStore: HarvestRecord[] = seedDemoHarvests();

// ─── Merkl rewards fetcher ────────────────────────────────────────────────────

export async function fetchMerklRewards(
  strategyAddress: string
): Promise<MerklReward[]> {
  const url = `https://api.merkl.xyz/v4/users/${strategyAddress}/rewards?chainId=480`;
  const res = await fetch(url, { next: { revalidate: 60 } });

  if (!res.ok) {
    console.error(`Merkl API error: ${res.status}`);
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
    const chainData = data["480"] ?? Object.values(data)[0];
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

    if (unclaimed > BigInt(0)) {
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

// ─── WLD price fetcher (5-min cache) ──────────────────────────────────────────

let cachedWldPrice: { price: number; fetchedAt: number } | null = null;
const PRICE_CACHE_MS = 5 * 60_000; // 5 minutes

export async function fetchWldPrice(): Promise<number> {
  if (cachedWldPrice && Date.now() - cachedWldPrice.fetchedAt < PRICE_CACHE_MS) {
    return cachedWldPrice.price;
  }

  try {
    const url = `https://coins.llama.fi/prices/current/worldchain:${WLD_ADDRESS}`;
    const res = await fetch(url, { next: { revalidate: 300 } });

    if (!res.ok) {
      console.error(`DeFi Llama price error: ${res.status}`);
      return cachedWldPrice?.price ?? 0.89; // fallback
    }

    const data = await res.json();
    const key = `worldchain:${WLD_ADDRESS}`.toLowerCase();
    const price = data?.coins?.[key]?.price ?? 0.89;

    cachedWldPrice = { price, fetchedAt: Date.now() };
    return price;
  } catch {
    return cachedWldPrice?.price ?? 0.89; // fallback
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

export function formatWldAmount(raw: bigint, decimals = 18): string {
  const divisor = BigInt(10) ** BigInt(decimals);
  const whole = raw / divisor;
  const frac = raw % divisor;
  const fracStr = frac.toString().padStart(decimals, "0").slice(0, 2);
  return `${whole}.${fracStr}`;
}
