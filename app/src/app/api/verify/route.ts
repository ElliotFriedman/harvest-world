import { NextRequest, NextResponse } from "next/server";

// Forwards the IDKit v2 proof payload to the World ID v2 verification endpoint.
// Returns the verification result so the client can proceed with
// calling vault.verifyHuman() on-chain.
export async function POST(req: NextRequest) {
  const body = await req.json();

  const res = await fetch(
    `https://developer.worldcoin.org/api/v2/verify/${process.env.NEXT_PUBLIC_APP_ID}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }
  );

  const data = await res.json();
  return NextResponse.json(data, { status: res.status });
}
