import { create } from "zustand";
import type { Address } from "viem";

export type PlanActionType = "sell" | "consolidate" | "discard" | "burn" | "revoke";

export interface PlanAction {
  wallet: Address;
  token: Address;
  type: PlanActionType;
  /** Only meaningful for "sell" — validated live against SweepExecutor.allowedOutputTokens. */
  outputToken?: Address;
  /** Only meaningful for "consolidate" — defaults to the primary wallet. */
  recipient?: Address;
}

interface PlanStore {
  actions: PlanAction[];
  setAction: (action: PlanAction) => void;
  removeAction: (wallet: Address, token: Address) => void;
  clearPlan: () => void;
}

/**
 * Local, in-memory plan state (Phase F9 builds the UI that drives this).
 * Deliberately not persisted to localStorage — a plan must be re-reviewed
 * (fresh quotes, fresh simulation) rather than silently resumed stale across
 * a reload, per frontend-state-machine.md's quote-expiry rules.
 */
export const usePlanStore = create<PlanStore>((set) => ({
  actions: [],
  setAction: (action) =>
    set((state) => {
      const withoutExisting = state.actions.filter(
        (a) => !(a.wallet === action.wallet && a.token === action.token),
      );
      return { actions: [...withoutExisting, action] };
    }),
  removeAction: (wallet, token) =>
    set((state) => ({
      actions: state.actions.filter((a) => !(a.wallet === wallet && a.token === token)),
    })),
  clearPlan: () => set({ actions: [] }),
}));
