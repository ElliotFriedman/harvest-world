import { signRequest } from "@worldcoin/idkit-server";
import { NextResponse } from "next/server";

// Returns an RP-signed context for IDKit.
// Called client-side before opening the IDKit widget.
// RP_SIGNING_KEY and WORLD_RP_ID must never be sent to the browser.
export async function GET() {
  const { sig, nonce, createdAt, expiresAt } = signRequest({
    signingKeyHex: process.env.RP_SIGNING_KEY!,
    action: "verify-human",
  });

  // RpContext expects created_at / expires_at as unix timestamps (number)
  return NextResponse.json({
    rp_id: process.env.WORLD_RP_ID!,
    nonce,
    created_at: createdAt,
    expires_at: expiresAt,
    signature: sig,
  } satisfies {
    rp_id: string;
    nonce: string;
    created_at: number;
    expires_at: number;
    signature: string;
  });
}
