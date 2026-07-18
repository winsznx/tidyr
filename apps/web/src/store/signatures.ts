import { create } from "zustand";
import type { Address } from "viem";
import type { Hex } from "@tidyr/shared";

export interface WalletSignature {
  signature: Hex;
  executionPlanHash: Hex;
  signedAt: number;
}

interface SignatureStore {
  signatures: Record<Address, WalletSignature>;
  setSignature: (wallet: Address, signature: WalletSignature) => void;
  clearSignature: (wallet: Address) => void;
}

/**
 * In-memory Permit2 signature queue. Deliberately not persisted — a signature
 * is tied to a specific `nonce`/`deadline` pair and must be re-obtained on
 * reload rather than silently resumed stale, matching `usePlanStore`'s own
 * "deliberately not persisted" convention (see apps/web/src/store/plan.ts).
 */
export const useSignatureStore = create<SignatureStore>((set) => ({
  signatures: {},
  setSignature: (wallet, signature) =>
    set((state) => ({ signatures: { ...state.signatures, [wallet]: signature } })),
  clearSignature: (wallet) =>
    set((state) => {
      const next = { ...state.signatures };
      delete next[wallet];
      return { signatures: next };
    }),
}));
