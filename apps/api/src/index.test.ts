import { test } from "node:test";
import assert from "node:assert/strict";

process.env["NODE_ENV"] = "test";
const { app } = await import("./index.ts");

test("GET /health/live returns 200", async () => {
  const res = await app.request("/health/live");
  assert.equal(res.status, 200);
  const body = (await res.json()) as { status: string };
  assert.equal(body.status, "live");
});
