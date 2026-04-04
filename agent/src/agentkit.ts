// ---------------------------------------------------------------------------
// Harvest Agent — AgentKit integration for human-backed agent identity
// ---------------------------------------------------------------------------
//
// The agent wallet is registered on-chain in World's AgentBook contract via:
//   npx @worldcoin/agentkit-cli register <agent-wallet-address>
//
// This module verifies that registration on startup. The agent still signs
// transactions with its private key — AgentKit provides the identity/attestation
// layer proving the agent is human-backed (World ID verified).
// ---------------------------------------------------------------------------

import { createAgentBookVerifier } from "@worldcoin/agentkit";
import { WORLD_CHAIN_CAIP2, RPC_URL } from "./config.js";

/**
 * Verify that the agent wallet is registered as human-backed in AgentBook.
 *
 * AgentBook is a World Chain contract that maps wallet addresses to anonymous
 * human identifiers. When an agent is registered via the AgentKit CLI, the
 * deployer scans a QR code with World App (Orb-verified), which records the
 * agent address -> human ID mapping on-chain.
 *
 * @returns The human ID (hex string) if registered, or null if not.
 */
export async function verifyAgentHumanBacking(
  agentAddress: string
): Promise<string | null> {
  console.log("[AgentKit] Checking human-backing for agent wallet...");
  console.log(`  Agent address: ${agentAddress}`);
  console.log(`  AgentBook chain: ${WORLD_CHAIN_CAIP2}`);

  try {
    const agentBook = createAgentBookVerifier({ rpcUrl: RPC_URL });
    const humanId = await agentBook.lookupHuman(agentAddress, WORLD_CHAIN_CAIP2);

    if (humanId) {
      console.log(`[AgentKit] Agent registered as human-backed via AgentKit`);
      console.log(`  Human ID: ${humanId}`);
      return humanId;
    } else {
      console.warn(
        `[AgentKit] Agent wallet is NOT registered in AgentBook.`
      );
      console.warn(
        `  To register, run: npx @worldcoin/agentkit-cli register ${agentAddress}`
      );
      return null;
    }
  } catch (error) {
    console.error(
      "[AgentKit] Failed to verify agent human-backing:",
      error instanceof Error ? error.message : error
    );
    console.warn(
      "[AgentKit] Continuing without AgentKit verification (graceful degradation)."
    );
    return null;
  }
}
