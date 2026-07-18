import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

/**
 * Server-only JSON-RPC proxy. Forwards to a private RPC endpoint (e.g. an
 * Alchemy Monad mainnet URL) read from a server-only env var
 * (MONAD_RPC_URL_PRIVATE - deliberately not NEXT_PUBLIC_, since that prefix
 * bakes a value into the client bundle where anyone can read it). Falls back
 * to the public Monad RPC when no private URL is configured, so local dev
 * needs no secret at all.
 *
 * This route never returns or logs the upstream URL/key - only the JSON-RPC
 * response body is forwarded to the caller.
 */
const UPSTREAM_RPC_URL = process.env["MONAD_RPC_URL_PRIVATE"] ?? "https://rpc.monad.xyz";

export async function POST(request: NextRequest) {
  const body = await request.text();

  const upstreamResponse = await fetch(UPSTREAM_RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
  });

  const responseBody = await upstreamResponse.text();
  return new NextResponse(responseBody, {
    status: upstreamResponse.status,
    headers: { "content-type": "application/json" },
  });
}
