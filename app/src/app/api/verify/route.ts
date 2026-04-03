import { NextRequest, NextResponse } from "next/server";

// Forwards the IDKit proof payload as-is to the World ID backend.
// Returns the verification result so the client can proceed with
// calling vault.verifyHuman() on-chain.
export async function POST(req: NextRequest) {
  const body = await req.json();

  const res = await fetch(
    `https://developer.world.org/api/v4/verify/${process.env.WORLD_RP_ID}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }
  );

  const data = await res.json();
  return NextResponse.json(data, { status: res.status });
}
