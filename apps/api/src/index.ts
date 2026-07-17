import { Hono } from "hono";
import { serve } from "@hono/node-server";

const app = new Hono();

/**
 * Process liveness only. Readiness (RPC/Postgres/Redis reachability) is
 * implemented in Phase 12/13 once those dependencies exist — this file
 * intentionally does not fake a "ready" response before then.
 */
app.get("/health/live", (c) => c.json({ status: "live" }));

const port = Number(process.env["PORT"] ?? 8080);

if (process.env["NODE_ENV"] !== "test") {
  serve({ fetch: app.fetch, port });
}

export { app };
