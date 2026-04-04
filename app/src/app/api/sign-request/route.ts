import { signRequest } from "@worldcoin/idkit-server";
import { NextResponse } from "next/server";

export async function GET() {
  const { sig, nonce, createdAt, expiresAt } = signRequest({
    signingKeyHex: process.env.RP_SIGNING_KEY!,
    action: "verify-human",
  });

  return NextResponse.json({
    rp_id: process.env.WORLD_RP_ID!,
    nonce,
    created_at: createdAt,
    expires_at: expiresAt,
    signature: sig,
  });
}
