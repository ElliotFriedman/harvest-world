// ---------------------------------------------------------------------------
// Harvest Agent — main entry point
// ---------------------------------------------------------------------------
//
// Standalone harvester for the Harvest yield aggregator on World Chain.
// Claims Merkl rewards, swaps to USDC, and redeposits into Morpho vaults.
//
// The agent uses World's AgentKit SDK for human-backed identity verification.
// The agent wallet must be registered via:
//   npx @worldcoin/agentkit-cli register <address>
//
// Usage:
//   AGENT_PRIVATE_KEY=0x... npx tsx agent/src/index.ts
//
// Environment variables:
//   AGENT_PRIVATE_KEY  — Required. Private key for the agent wallet.
//   RPC_URL            — Optional. World Chain RPC (default: https://worldchain.drpc.org)
// ---------------------------------------------------------------------------

import type { Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { verifyAgentHumanBacking } from "./agentkit.js";
import { runHarvest } from "./harvester.js";

async function main() {
  console.log("=".repeat(60));
  console.log("  Harvest Agent — World Chain Yield Optimizer");
  console.log("  DeFi, for humans.");
  console.log("=".repeat(60));
  console.log(`  Time: ${new Date().toISOString()}`);
  console.log(`  Chain: World Chain (480)`);

  // ── Validate environment ─────────────────────────────────────────────────

  const agentKey = process.env.AGENT_PRIVATE_KEY;
  if (!agentKey) {
    console.error(
      "\n[Error] AGENT_PRIVATE_KEY not set. Export it or add to .env file."
    );
    console.error("  Example: AGENT_PRIVATE_KEY=0xabc... npx tsx src/index.ts");
    process.exit(1);
  }

  // Derive the agent wallet address from the private key
  const account = privateKeyToAccount(agentKey as Hex);
  console.log(`  Agent wallet: ${account.address}`);

  // ── AgentKit: verify human-backed identity ───────────────────────────────

  console.log("\n" + "-".repeat(60));
  const humanId = await verifyAgentHumanBacking(account.address);

  if (humanId) {
    console.log("[AgentKit] Human-backed agent identity confirmed.");
  } else {
    console.warn(
      "[AgentKit] Agent is NOT registered as human-backed. Proceeding anyway."
    );
    console.warn(
      "  For AgentKit prize eligibility, register with: npx @worldcoin/agentkit-cli register"
    );
  }

  // ── Run harvest cycle ────────────────────────────────────────────────────

  console.log("\n" + "-".repeat(60));
  console.log("[Harvest] Starting harvest cycle...\n");

  const result = await runHarvest(agentKey as Hex);

  // ── Report results ───────────────────────────────────────────────────────

  console.log("\n" + "=".repeat(60));
  if (result.success) {
    console.log("  HARVEST SUCCESSFUL");
    console.log(`  Rewards claimed: ${result.rewardsClaimed}`);
    console.log(`  Claim tx:    ${result.claimTxHash}`);
    console.log(`  Harvest tx:  ${result.harvestTxHash}`);
    console.log(
      `  Share price: ${result.oldSharePrice} -> ${result.newSharePrice} USDC`
    );
  } else if (result.reason === "no_rewards") {
    console.log("  NO REWARDS TO HARVEST");
    console.log(
      "  The strategy has no unclaimed Merkl rewards. Will check again next cycle."
    );
  } else {
    console.error(`  HARVEST FAILED: ${result.reason}`);
    if (result.claimTxHash) {
      console.error(`  Claim tx: ${result.claimTxHash}`);
    }
    if (result.harvestTxHash) {
      console.error(`  Harvest tx: ${result.harvestTxHash}`);
    }
  }
  console.log("=".repeat(60));

  // Exit with appropriate code
  process.exit(result.success || result.reason === "no_rewards" ? 0 : 1);
}

main().catch((err) => {
  console.error("\n[Fatal] Unhandled error:", err);
  process.exit(1);
});
