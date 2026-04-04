// ---------------------------------------------------------------------------
// Uniswap Trading API — shared quote helper for API routes
// ---------------------------------------------------------------------------

const UNISWAP_API_URL = "https://trade-api.gateway.uniswap.org/v1/quote";
const STRATEGY_ADDRESS = "0x313bA1D5D5AA1382a80BA839066A61d33C110489";
const WLD_ADDRESS = "0x2cFc85d8E48F8EAB294be644d9E25C3030863003";
const USDC_ADDRESS = "0x79A02482A880bCE3F13e09Da970dC34db4CD24d1";

export interface UniswapQuote {
  expectedOutput: string;  // e.g. "42.18 USDC"
  gasFeeUSD: string;       // e.g. "0.02"
  priceImpact: string;     // e.g. "0.12"
  routing: string;         // e.g. "CLASSIC"
}

export async function fetchUniswapQuote(
  amountIn: bigint,
): Promise<UniswapQuote | null> {
  const apiKey = process.env.UNISWAP_API_KEY;
  if (!apiKey) return null;

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

    if (!res.ok) return null;

    const data = await res.json();
    const quote = data?.quote;
    if (!quote?.output?.amount) return null;

    const rawOut = BigInt(quote.output.amount);
    const outFormatted = (Number(rawOut) / 1e6).toFixed(2);

    return {
      expectedOutput: `${outFormatted} USDC`,
      gasFeeUSD: quote.gasFeeUSD ?? "0",
      priceImpact: quote.priceImpact ?? "0",
      routing: data.routing ?? "CLASSIC",
    };
  } catch {
    return null;
  }
}
