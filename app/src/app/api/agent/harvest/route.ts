import { NextResponse } from "next/server";
import {
  createPublicClient,
  createWalletClient,
  http,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  STRATEGY_ADDRESS,
  VAULT_ADDRESS,
  strategyAbi,
  vaultAbi,
  harvestStore,
  fetchMerklRewards,
  formatWldAmount,
} from "../../../../lib/harvester";

// Server-only — RPC_URL never exposed to browser
const RPC_URL = process.env.RPC_URL || "https://worldchain.drpc.org";

const worldChain = {
  id: 480,
  name: "World Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
} as const;

const publicClient = createPublicClient({
  chain: worldChain,
  transport: http(RPC_URL),
});

// Vercel Cron sends GET requests
export async function GET(request: Request) {
  // Verify the request is from Vercel Cron
  const authHeader = request.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  return harvest();
}

export async function POST() {
  return harvest();
}

async function harvest() {
  // 1. Check for agent private key
  const agentKey = process.env.AGENT_PRIVATE_KEY;
  if (!agentKey) {
    return NextResponse.json(
      {
        success: false,
        reason: "missing_key",
        message: "Agent wallet not configured. Set AGENT_PRIVATE_KEY.",
      },
      { status: 503 }
    );
  }

  try {
    // 2. Fetch Merkl rewards for the strategy
    const rewards = await fetchMerklRewards(STRATEGY_ADDRESS);

    if (rewards.length === 0) {
      return NextResponse.json({
        success: false,
        reason: "no_rewards",
        message: "No unclaimed Merkl rewards for the strategy.",
      });
    }

    // 3. Build claim parameters from rewards
    const tokens = rewards.map((r) => r.token as `0x${string}`);
    const amounts = rewards.map((r) => r.amount);
    const proofs = rewards.map((r) => r.proofs as `0x${string}`[]);

    // Format summary for response
    const rewardsSummary = rewards
      .map((r) => `${formatWldAmount(r.unclaimed)} ${r.symbol}`)
      .join(", ");

    // 4. Create wallet client from agent key
    const account = privateKeyToAccount(agentKey as Hex);
    const walletClient = createWalletClient({
      account,
      chain: worldChain,
      transport: http(RPC_URL),
    });

    // Read price per share before harvest
    const priceBefore = await publicClient
      .readContract({
        address: VAULT_ADDRESS,
        abi: vaultAbi,
        functionName: "getPricePerFullShare",
      })
      .catch(() => BigInt(0));

    // 5. Claim from Merkl distributor via strategy
    const claimHash = await walletClient.writeContract({
      address: STRATEGY_ADDRESS,
      abi: strategyAbi,
      functionName: "claim",
      args: [tokens, amounts, proofs],
    });

    // Wait for claim tx
    await publicClient.waitForTransactionReceipt({ hash: claimHash });

    // 6. Harvest — swap rewards to USDC and redeposit
    const harvestHash = await walletClient.writeContract({
      address: STRATEGY_ADDRESS,
      abi: strategyAbi,
      functionName: "harvest",
      args: [account.address],
    });

    // Wait for harvest tx
    await publicClient.waitForTransactionReceipt({ hash: harvestHash });

    // 7. Read new price per share
    const priceAfter = await publicClient
      .readContract({
        address: VAULT_ADDRESS,
        abi: vaultAbi,
        functionName: "getPricePerFullShare",
      })
      .catch(() => BigInt(0));

    // 8. Record in store
    const record = {
      timestamp: new Date().toISOString(),
      txHash: harvestHash,
      wantEarned: "-- USDC", // exact amount requires event parsing
      rewardsClaimed: rewardsSummary,
    };
    harvestStore.push(record);

    return NextResponse.json({
      success: true,
      txHash: harvestHash,
      claimTxHash: claimHash,
      rewardsClaimed: rewardsSummary,
      wantEarned: record.wantEarned,
      newSharePrice: priceAfter.toString(),
      oldSharePrice: priceBefore.toString(),
    });
  } catch (err) {
    console.error("Harvest error:", err);
    return NextResponse.json(
      {
        success: false,
        reason: "tx_failed",
        message: err instanceof Error ? err.message : "Harvest transaction failed",
      },
      { status: 500 }
    );
  }
}
