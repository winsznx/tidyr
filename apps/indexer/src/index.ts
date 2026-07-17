export const PACKAGE_NAME = "@tidyr/indexer" as const;

/**
 * Finalized-event ingestion (SweepCompleted / ActionExecuted / ActionFailed),
 * idempotent by chainId+txHash+logIndex, is implemented in Phase 13 once
 * contracts are deployed and packages/shared exposes real ABIs/addresses.
 */
export {};
