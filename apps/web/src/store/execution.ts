import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Address, Hex } from "viem";

export type WalletExecutionStatus =
  | "pending"
  | "signing"
  | "signed"
  | "broadcasting"
  | "confirming"
  | "confirmed"
  | "failed";

export interface WalletExecutionGraph {
  wallet: Address;
  manifestHash: Hex;
  /** Locally-submitted hashes only — never a signature or raw calldata beyond
   * what's needed to resume monitoring, per the storage policy. */
  submittedTxHashes: Hex[];
  status: WalletExecutionStatus;
}

interface ExecutionStore {
  graphs: Record<string, WalletExecutionGraph>;
  startGraph: (wallet: Address, manifestHash: Hex) => void;
  recordSubmittedTx: (wallet: Address, hash: Hex) => void;
  setStatus: (wallet: Address, status: WalletExecutionStatus) => void;
  clearGraph: (wallet: Address) => void;
}

/**
 * Persists only submitted tx hashes and coarse status, so a page refresh can
 * resume monitoring without ever auto-resubmitting a transaction. Finalized
 * state is always re-derived from chain reads on load, never trusted from
 * this persisted cache alone (frontend-state-machine.md's RESUMED_SESSION
 * rule).
 */
export const useExecutionStore = create<ExecutionStore>()(
  persist(
    (set) => ({
      graphs: {},
      startGraph: (wallet, manifestHash) =>
        set((state) => ({
          graphs: {
            ...state.graphs,
            [wallet]: { wallet, manifestHash, submittedTxHashes: [], status: "pending" },
          },
        })),
      recordSubmittedTx: (wallet, hash) =>
        set((state) => {
          const existing = state.graphs[wallet];
          if (!existing) return state;
          return {
            graphs: {
              ...state.graphs,
              [wallet]: { ...existing, submittedTxHashes: [...existing.submittedTxHashes, hash] },
            },
          };
        }),
      setStatus: (wallet, status) =>
        set((state) => {
          const existing = state.graphs[wallet];
          if (!existing) return state;
          return { graphs: { ...state.graphs, [wallet]: { ...existing, status } } };
        }),
      clearGraph: (wallet) =>
        set((state) => {
          const { [wallet]: _removed, ...rest } = state.graphs;
          return { graphs: rest };
        }),
    }),
    { name: "tidyr.execution" },
  ),
);
