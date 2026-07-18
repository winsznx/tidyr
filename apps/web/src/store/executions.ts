import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Address } from "viem";
import type { Hex } from "@tidyr/shared";

export interface ExecutionRecord {
  displayManifestHash: Hex;
  executionPlanHash: Hex;
  wallet: Address;
  txHash: Hex;
  submittedAt: number;
}

interface ExecutionStore {
  records: Record<Hex, ExecutionRecord>;
  setExecution: (record: ExecutionRecord) => void;
}

/**
 * Local record of "I broadcast this plan at this tx hash", keyed by
 * `displayManifestHash`. Unlike `usePlanStore` (store/plan.ts) and
 * `useSignatureStore` (store/signatures.ts) — which are deliberately NOT
 * persisted because a plan/signature must always be freshly re-reviewed
 * against live chain state rather than silently resumed stale — this store
 * intentionally persists. A completed execution's own record of which tx
 * hash it broadcast is a durable, backward-looking fact, not a forward-
 * looking authorization that could go stale. It is exactly the "locally-
 * retained submitted tx hash" that docs/frontend-integration-matrix.md's
 * Report row requires, since this app has no backend indexer to look this
 * up any other way (see F14 in apps/web/src/lib/report/use-sweep-report.ts).
 */
export const useExecutionStore = create<ExecutionStore>()(
  persist(
    (set) => ({
      records: {},
      setExecution: (record) =>
        set((state) => ({
          records: { ...state.records, [record.displayManifestHash]: record },
        })),
    }),
    {
      name: "tidyr.executions",
      partialize: (state) => ({ records: state.records }),
    },
  ),
);
