// ---------------------------------------------------------------------------
// Harvest Agent — configuration, constants, and ABIs
// ---------------------------------------------------------------------------

import type { Chain } from "viem";

// ─── Contract addresses (World Chain mainnet, chainId 480) ──────────────────

export const STRATEGY_ADDRESS =
  "0x313bA1D5D5AA1382a80BA839066A61d33C110489" as const;
export const VAULT_ADDRESS =
  "0x512CE44e4F69A98bC42A57ceD8257e65e63cD74f" as const;
export const WLD_ADDRESS =
  "0x2cFc85d8E48F8EAB294be644d9E25C3030863003" as const;
export const USDC_ADDRESS =
  "0x79A02482A880bCE3F13e09Da970dC34db4CD24d1" as const;

// ─── Chain config ────────────────────────────────────────────────────────────

export const RPC_URL =
  process.env.RPC_URL || "https://worldchain.drpc.org";

export const worldChain: Chain = {
  id: 480,
  name: "World Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: [RPC_URL] },
  },
};

// ─── CAIP-2 chain identifier (used by AgentKit) ─────────────────────────────

export const WORLD_CHAIN_CAIP2 = "eip155:480";

// ─── ABIs ────────────────────────────────────────────────────────────────────

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
