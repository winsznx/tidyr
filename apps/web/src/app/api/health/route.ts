import { NextResponse } from "next/server";

/** Process liveness only - no RPC or database call, matching apps/api's own health route. */
export function GET() {
  return NextResponse.json({ status: "ok", service: "tidyr-web" });
}
