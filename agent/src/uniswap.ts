// ---------------------------------------------------------------------------
// Harvest Agent — Uniswap Trading API client for swap intelligence
// ---------------------------------------------------------------------------

import { STRATEGY_ADDRESS, WLD_ADDRESS, USDC_ADDRESS } from "./config.js";
import { formatTokenAmount } from "./merkl.js";

// ─── Types ──────────────────────────────────────────────────────────────────

export interface UniswapQuote {
  expectedOutput: string;  // e.g. "42.18 USDC"
  gasFeeUSD: string;       // e.g. "0.02"
  priceImpact: string;     // e.g. "0.12"
  routing: string;         // e.g. "CLASSIC"
}

// ─── Uniswap quote fetcher ──────────────────────────────────────────────────

const UNISWAP_API_URL = "https://trade-api.gateway.uniswap.org/v1/quote";

export async function fetchUniswapQuote(
  amountIn: bigint,
): Promise<UniswapQuote | null> {
  const apiKey = process.env.UNISWAP_API_KEY;
  if (!apiKey) {
    console.log("  [Uniswap] No API key configured (UNISWAP_API_KEY). Skipping quote.");
    return null;
  }

  try {
    const res = await fetch(UNISWAP_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
      },
      body: JSON.stringify({
        type: "EXACT_INPUT",
        amount: amountIn.toString(),
        tokenInChainId: 480,
        tokenOutChainId: 480,
        tokenIn: WLD_ADDRESS,
        tokenOut: USDC_ADDRESS,
        swapper: STRATEGY_ADDRESS,
        slippageTolerance: 0.5,
      }),
    });

    if (!res.ok) {
      console.error(`  [Uniswap] API error: ${res.status} ${res.statusText}`);
      return null;
    }

    const data = await res.json();
    const quote = data?.quote;
    if (!quote?.output?.amount) {
      console.error("  [Uniswap] Unexpected response shape");
      return null;
    }

    const rawOut = BigInt(quote.output.amount);
    const outFormatted = (Number(rawOut) / 1e6).toFixed(2);

    return {
      expectedOutput: `${outFormatted} USDC`,
      gasFeeUSD: quote.gasFeeUSD ?? "0",
      priceImpact: quote.priceImpact ?? "0",
      routing: data.routing ?? "CLASSIC",
    };
  } catch (err) {
    console.error("  [Uniswap] Quote fetch failed:", err instanceof Error ? err.message : err);
    return null;
  }
}
