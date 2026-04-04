import { NextRequest, NextResponse } from "next/server";
import { createPublicClient, http } from "viem";

// Server-only — RPC_URL never exposed to browser
const RPC_URL = process.env.RPC_URL || "https://worldchain.drpc.org";

const client = createPublicClient({
  chain: {
    id: 480,
    name: "World Chain",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [RPC_URL] } },
    contracts: { multicall3: { address: "0xcA11bde05977b3631167028862bE2a173976CA11" } },
  },
  transport: http(RPC_URL),
});

const USDC = "0x79A02482A880bCE3F13e09Da970dC34db4CD24d1" as const;
const VAULT = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ?? "0x512ce44e4f69a98bc42a57ced8257e65e63cd74f") as `0x${string}`;

const balanceOfAbi = [{ inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ name: "", type: "uint256" }], stateMutability: "view", type: "function" }] as const;
const vaultAbi = [
  { inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ name: "", type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "getPricePerFullShare", outputs: [{ name: "", type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "balance", outputs: [{ name: "", type: "uint256" }], stateMutability: "view", type: "function" },
] as const;

// Simple in-memory cache to avoid hammering the RPC on rapid taps
const cache = new Map<string, { data: Record<string, string>; ts: number }>();
const CACHE_TTL = 5_000; // 5 seconds

export async function GET(req: NextRequest) {
  const wallet = req.nextUrl.searchParams.get("wallet") as `0x${string}` | null;
  const cacheKey = wallet ?? "__tvl__";

  // Return cached response if fresh
  const cached = cache.get(cacheKey);
  if (cached && Date.now() - cached.ts < CACHE_TTL) {
    return NextResponse.json(cached.data);
  }

  try {
    // If no wallet, just return TVL + pricePerShare
    if (!wallet) {
      const results = await client.multicall({
        contracts: [
          { address: VAULT, abi: vaultAbi, functionName: "getPricePerFullShare" },
          { address: VAULT, abi: vaultAbi, functionName: "balance" },
        ],
      });
      const data = {
        usdcBalance: "0",
        vaultShares: "0",
        pricePerShare: (results[0].result ?? BigInt("1000000000000000000")).toString(),
        tvl: (results[1].result ?? BigInt(0)).toString(),
      };
      cache.set(cacheKey, { data, ts: Date.now() });
      return NextResponse.json(data);
    }

    const results = await client.multicall({
      contracts: [
        { address: USDC, abi: balanceOfAbi, functionName: "balanceOf", args: [wallet] },
        { address: VAULT, abi: vaultAbi, functionName: "balanceOf", args: [wallet] },
        { address: VAULT, abi: vaultAbi, functionName: "getPricePerFullShare" },
        { address: VAULT, abi: vaultAbi, functionName: "balance" },
      ],
    });

    const data = {
      usdcBalance: (results[0].result ?? BigInt(0)).toString(),
      vaultShares: (results[1].result ?? BigInt(0)).toString(),
      pricePerShare: (results[2].result ?? BigInt("1000000000000000000")).toString(),
      tvl: (results[3].result ?? BigInt(0)).toString(),
    };
    cache.set(cacheKey, { data, ts: Date.now() });
    return NextResponse.json(data);
  } catch (err) {
    console.error("[/api/balances] RPC error:", err);

    // If we have stale cached data, return it rather than failing
    if (cached) {
      return NextResponse.json(cached.data);
    }

    return NextResponse.json(
      { error: "RPC request failed", message: String(err) },
      { status: 502 }
    );
  }
}
