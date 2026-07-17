export const PACKAGE_NAME = "@tidyr/transaction-review" as const;

export * from "./executionPlanHash.ts";
export * from "./displayManifestHash.ts";

/**
 * Calldata decode-and-compare verification, Permit2 typed data, and ERC-7730
 * descriptor generation are implemented in Phase 3/11 — nothing ships here until
 * those integrations can be tested against real (or forked) contract behavior.
 */
