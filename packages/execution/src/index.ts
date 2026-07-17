export const PACKAGE_NAME = "@tidyr/execution" as const;

/**
 * The multi-wallet execution state machine (Phase 14) depends on
 * packages/transaction-review (manifests/signatures) and packages/shared
 * (chain constants) being real, not on this package existing first.
 * Scaffolded now so the workspace graph and CI are established early.
 */
export {};
