import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Address } from "viem";

import { DEMO_TOKENS } from "@/lib/deployment";

interface TrackedTokensStore {
  /** User-added token addresses, beyond the known demo tokens. */
  manualTokens: Address[];
  addToken: (address: Address) => { ok: true } | { ok: false; error: string };
  removeToken: (address: Address) => void;
}

/**
 * There is no indexer (see docs/frontend-integration-matrix.md §0), so token
 * discovery cannot be automatic wallet-wide scanning. The candidate list is
 * the known demo tokens plus whatever the user explicitly adds here.
 */
export const useTrackedTokensStore = create<TrackedTokensStore>()(
  persist(
    (set, get) => ({
      manualTokens: [],
      addToken: (address) => {
        const lower = address.toLowerCase();
        const alreadyKnown =
          DEMO_TOKENS.some((t) => t.address.toLowerCase() === lower) ||
          get().manualTokens.some((t) => t.toLowerCase() === lower);
        if (alreadyKnown) return { ok: false, error: "This token is already tracked." };
        set((state) => ({ manualTokens: [...state.manualTokens, address] }));
        return { ok: true };
      },
      removeToken: (address) =>
        set((state) => ({
          manualTokens: state.manualTokens.filter((t) => t.toLowerCase() !== address.toLowerCase()),
        })),
    }),
    { name: "tidyr.tracked-tokens" },
  ),
);
