// ---------------------------------------------------------------------------
// Client-side helpers that fetch from our server-side API routes.
// The viem client + RPC key live server-side only (in /api/balances).
// ---------------------------------------------------------------------------

export interface Balances {
  usdcBalance: bigint;
  vaultShares: bigint;
  pricePerShare: bigint;
  tvl: bigint;
}

export async function getBalances(walletAddress: string): Promise<Balances> {
  const res = await fetch(`/api/balances?wallet=${walletAddress}`);
  if (!res.ok) throw new Error("Failed to fetch balances");
  const data = await res.json();
  return {
    usdcBalance: BigInt(data.usdcBalance),
    vaultShares: BigInt(data.vaultShares),
    pricePerShare: BigInt(data.pricePerShare),
    tvl: BigInt(data.tvl),
  };
}

export async function getVaultTvl(): Promise<bigint> {
  const res = await fetch("/api/balances");
  if (!res.ok) throw new Error("Failed to fetch TVL");
  const data = await res.json();
  return BigInt(data.tvl);
}
