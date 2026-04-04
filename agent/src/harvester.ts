// ---------------------------------------------------------------------------
// Harvest Agent — core harvest logic (claim Merkl rewards + harvest)
// ---------------------------------------------------------------------------

import {
  createPublicClient,
  createWalletClient,
  http,
  formatUnits,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  STRATEGY_ADDRESS,
  VAULT_ADDRESS,
  worldChain,
  RPC_URL,
  strategyAbi,
  vaultAbi,
} from "./config.js";
import { fetchMerklRewards, formatTokenAmount } from "./merkl.js";

// ─── Result type ─────────────────────────────────────────────────────────────

export interface HarvestResult {
  success: boolean;
  reason?: string;
  claimTxHash?: string;
  harvestTxHash?: string;
  rewardsClaimed?: string;
  oldSharePrice?: string;
  newSharePrice?: string;
}

// ─── Main harvest function ───────────────────────────────────────────────────

export async function runHarvest(agentPrivateKey: Hex): Promise<HarvestResult> {
  // Create clients
  const publicClient = createPublicClient({
    chain: worldChain,
    transport: http(RPC_URL),
  });

  const account = privateKeyToAccount(agentPrivateKey);
  const walletClient = createWalletClient({
    account,
    chain: worldChain,
    transport: http(RPC_URL),
  });

  console.log(`\n[Harvest] Agent wallet: ${account.address}`);
  console.log(`[Harvest] Strategy: ${STRATEGY_ADDRESS}`);
  console.log(`[Harvest] Vault: ${VAULT_ADDRESS}`);

  // ── Step 1: Fetch Merkl rewards ──────────────────────────────────────────

  console.log("\n[Step 1/4] Fetching Merkl rewards for strategy...");
  const rewards = await fetchMerklRewards(STRATEGY_ADDRESS);

  if (rewards.length === 0) {
    console.log("  No unclaimed Merkl rewards found. Nothing to harvest.");
    return { success: false, reason: "no_rewards" };
  }

  console.log(`  Found ${rewards.length} reward token(s) with unclaimed balances:`);
  for (const r of rewards) {
    console.log(`    - ${formatTokenAmount(r.unclaimed)} ${r.symbol} (${r.token})`);
  }

  // ── Step 2: Read share price before harvest ──────────────────────────────

  console.log("\n[Step 2/4] Reading vault share price (before)...");
  const priceBefore = await publicClient
    .readContract({
      address: VAULT_ADDRESS,
      abi: vaultAbi,
      functionName: "getPricePerFullShare",
    })
    .catch(() => 0n);

  console.log(`  Price per full share: ${formatUnits(priceBefore, 6)} USDC`);

  // ── Step 3: Claim rewards from Merkl ─────────────────────────────────────

  console.log("\n[Step 3/4] Claiming rewards from Merkl distributor...");
  const tokens = rewards.map((r) => r.token as `0x${string}`);
  const amounts = rewards.map((r) => r.amount);
  const proofs = rewards.map((r) => r.proofs as `0x${string}`[]);

  const rewardsSummary = rewards
    .map((r) => `${formatTokenAmount(r.unclaimed)} ${r.symbol}`)
    .join(", ");

  const claimHash = await walletClient.writeContract({
    address: STRATEGY_ADDRESS,
    abi: strategyAbi,
    functionName: "claim",
    args: [tokens, amounts, proofs],
  });

  console.log(`  Claim tx submitted: ${claimHash}`);
  console.log("  Waiting for confirmation...");
  const claimReceipt = await publicClient.waitForTransactionReceipt({
    hash: claimHash,
  });
  console.log(
    `  Claim confirmed in block ${claimReceipt.blockNumber} (status: ${claimReceipt.status})`
  );

  if (claimReceipt.status === "reverted") {
    console.error("  Claim transaction reverted!");
    return { success: false, reason: "claim_reverted", claimTxHash: claimHash };
  }

  // ── Step 4: Harvest — swap rewards to USDC and redeposit into Morpho ────

  console.log("\n[Step 4/4] Harvesting (swap + redeposit)...");
  const harvestHash = await walletClient.writeContract({
    address: STRATEGY_ADDRESS,
    abi: strategyAbi,
    functionName: "harvest",
    args: [account.address], // callFeeRecipient = agent wallet
  });

  console.log(`  Harvest tx submitted: ${harvestHash}`);
  console.log("  Waiting for confirmation...");
  const harvestReceipt = await publicClient.waitForTransactionReceipt({
    hash: harvestHash,
  });
  console.log(
    `  Harvest confirmed in block ${harvestReceipt.blockNumber} (status: ${harvestReceipt.status})`
  );

  if (harvestReceipt.status === "reverted") {
    console.error("  Harvest transaction reverted!");
    return {
      success: false,
      reason: "harvest_reverted",
      claimTxHash: claimHash,
      harvestTxHash: harvestHash,
      rewardsClaimed: rewardsSummary,
    };
  }

  // ── Read share price after harvest ───────────────────────────────────────

  const priceAfter = await publicClient
    .readContract({
      address: VAULT_ADDRESS,
      abi: vaultAbi,
      functionName: "getPricePerFullShare",
    })
    .catch(() => 0n);

  console.log(`\n  Share price before: ${formatUnits(priceBefore, 6)} USDC`);
  console.log(`  Share price after:  ${formatUnits(priceAfter, 6)} USDC`);

  if (priceAfter > priceBefore) {
    const increase = priceAfter - priceBefore;
    console.log(
      `  Share price increased by ${formatUnits(increase, 6)} USDC per share`
    );
  }

  return {
    success: true,
    claimTxHash: claimHash,
    harvestTxHash: harvestHash,
    rewardsClaimed: rewardsSummary,
    oldSharePrice: formatUnits(priceBefore, 6),
    newSharePrice: formatUnits(priceAfter, 6),
  };
}
