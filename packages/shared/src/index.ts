export const PACKAGE_NAME = "@tidyr/shared" as const;

export * from "./actions.ts";

/**
 * Chain constants and deployed contract addresses are populated in Phase 9 once
 * SweepExecutor and the adapters are actually deployed — this package must never
 * ship fabricated addresses ahead of a real deployment.
 */
