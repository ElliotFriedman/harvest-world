import { createPublicClient, http, type Chain } from "viem";

// ---------------------------------------------------------------------------
// Chain definition
// ---------------------------------------------------------------------------

const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL || "https://worldchain.drpc.org";

export const worldChain: Chain = {
  id: 480,
  name: "World Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
<<<<<<< HEAD
    default: { http: [RPC_URL] },
  },
};

// ---------------------------------------------------------------------------
// Public client
// ---------------------------------------------------------------------------

export const publicClient = createPublicClient({
  chain: worldChain,
  transport: http(RPC_URL),
});

// ---------------------------------------------------------------------------
// Addresses
// ---------------------------------------------------------------------------

const USDC_ADDRESS = "0x79A02482A880bCE3F13e09Da970dC34db4CD24d1" as const;
const VAULT_ADDRESS = "0xDA3cF80dC04F527563a40Ce17A5466d6A05eefBD" as const;

// ---------------------------------------------------------------------------
// Minimal ABIs (read-only functions)
// ---------------------------------------------------------------------------

export const erc20BalanceOfAbi = [
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const vaultAbi = [
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getPricePerFullShare",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "balance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

// ---------------------------------------------------------------------------
// getBalances — batch-reads USDC balance, vault shares, price-per-share, TVL
// ---------------------------------------------------------------------------

export async function getBalances(walletAddress: string): Promise<{
  usdcBalance: bigint;
  vaultShares: bigint;
  pricePerShare: bigint;
  tvl: bigint;
}> {
  const results = await publicClient.multicall({
    contracts: [
      {
        address: USDC_ADDRESS,
        abi: erc20BalanceOfAbi,
        functionName: "balanceOf",
        args: [walletAddress as `0x${string}`],
      },
      {
        address: VAULT_ADDRESS,
        abi: vaultAbi,
        functionName: "balanceOf",
        args: [walletAddress as `0x${string}`],
      },
      {
        address: VAULT_ADDRESS,
        abi: vaultAbi,
        functionName: "getPricePerFullShare",
      },
      {
        address: VAULT_ADDRESS,
        abi: vaultAbi,
        functionName: "balance",
      },
    ],
  });

  return {
    usdcBalance: results[0].result as bigint,
    vaultShares: results[1].result as bigint,
    pricePerShare: results[2].result as bigint,
    tvl: results[3].result as bigint,
  };
}

// ---------------------------------------------------------------------------
// getVaultTvl — standalone helper for total vault balance
// ---------------------------------------------------------------------------

export async function getVaultTvl(): Promise<bigint> {
  return publicClient.readContract({
    address: VAULT_ADDRESS,
    abi: vaultAbi,
    functionName: "balance",
  });
}
