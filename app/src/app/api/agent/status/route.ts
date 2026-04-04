import { NextResponse } from "next/server";
import { createPublicClient, http } from "viem";
import {
  STRATEGY_ADDRESS,
  WLD_ADDRESS,
  strategyAbi,
  harvestStore,
  fetchMerklRewards,
  fetchWldPrice,
  formatWldAmount,
} from "../../../../lib/harvester";

// Server-only — RPC_URL never exposed to browser
const RPC_URL = process.env.RPC_URL || "https://worldchain.drpc.org";

const client = createPublicClient({
  chain: {
    id: 480,
    name: "World Chain",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [RPC_URL] } },
  },
  transport: http(RPC_URL),
});

export async function GET() {
  try {
    // Fetch on-chain data + Merkl rewards + WLD price in parallel
    const [balanceOfPool, totalLocked, lastHarvestTs, lockDuration, merklRewards, wldPrice] = await Promise.all([
      client.readContract({ address: STRATEGY_ADDRESS, abi: strategyAbi, functionName: "balanceOfPool" }).catch(() => BigInt(0)),
      client.readContract({ address: STRATEGY_ADDRESS, abi: strategyAbi, functionName: "totalLocked" }).catch(() => BigInt(0)),
      client.readContract({ address: STRATEGY_ADDRESS, abi: strategyAbi, functionName: "lastHarvest" }).catch(() => BigInt(0)),
      client.readContract({ address: STRATEGY_ADDRESS, abi: strategyAbi, functionName: "lockDuration" }).catch(() => BigInt(86400)),
      fetchMerklRewards(STRATEGY_ADDRESS),
      fetchWldPrice(),
    ]);

    // Parse pending rewards (look for WLD specifically, or take first)
    let pendingRewards: {
      token: string;
      amount: string;
      usdValue: number;
    } | null = null;

    if (merklRewards.length > 0) {
      // Prefer WLD, otherwise take the first unclaimed reward
      const wldReward = merklRewards.find(
        (r) => r.token.toLowerCase() === WLD_ADDRESS.toLowerCase()
      );
      const reward = wldReward ?? merklRewards[0];

      const amountFormatted = formatWldAmount(reward.unclaimed);
      const amountFloat = parseFloat(amountFormatted);
      const usdValue = amountFloat * wldPrice;

      pendingRewards = {
        token: reward.symbol,
        amount: `${amountFormatted} ${reward.symbol}`,
        usdValue: Math.round(usdValue * 100) / 100,
      };
    }

    // Streaming profit info
    const nowSec = BigInt(Math.floor(Date.now() / 1000));
    const unlocksAt = lastHarvestTs + lockDuration;
    const remaining = unlocksAt > nowSec ? unlocksAt - nowSec : BigInt(0);
    const lockedProfitUsdc = lockDuration > BigInt(0) && totalLocked > BigInt(0)
      ? (totalLocked * remaining) / lockDuration
      : BigInt(0);
    const streaming = lockedProfitUsdc > BigInt(0)
      ? {
          lockedUsd: (Number(lockedProfitUsdc) / 1e6).toFixed(4),
          unlocksInMs: Number(remaining) * 1000,
        }
      : null;

    // Last harvest from store
    const lastHarvest =
      harvestStore.length > 0 ? harvestStore[harvestStore.length - 1] : null;

    // Next check: ~6h from last harvest or from now
    const lastTime = lastHarvest
      ? new Date(lastHarvest.timestamp).getTime()
      : Date.now();
    const nextCheck = new Date(lastTime + 6 * 3600_000).toISOString();

    return NextResponse.json({
      status: "active" as const,
      lastHarvest,
      harvests: [...harvestStore].reverse(), // newest first
      pendingRewards,
      nextCheck,
      balanceOfPool: balanceOfPool.toString(),
      streaming,
    });
  } catch (err) {
    console.error("Agent status error:", err);
    // Return a degraded response rather than 500
    const lastHarvest =
      harvestStore.length > 0 ? harvestStore[harvestStore.length - 1] : null;

    return NextResponse.json({
      status: "active" as const,
      lastHarvest,
      harvests: [...harvestStore].reverse(),
      pendingRewards: null,
      nextCheck: new Date(Date.now() + 6 * 3600_000).toISOString(),
      balanceOfPool: "0",
      streaming: null,
    });
  }
}
