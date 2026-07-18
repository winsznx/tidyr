import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Address } from "viem";

/**
 * A saved wallet record. Only the fields listed in the `PersistedWalletFields`
 * below are ever written to localStorage — everything else (balances, scan
 * status, connector instance) is derived at runtime from wagmi/viem and never
 * persisted, per frontend-integration-matrix.md §5's storage policy.
 */
export interface WalletRecord {
  address: Address;
  label: string;
  watchOnly: boolean;
  isPrimary: boolean;
}

interface WalletStore {
  wallets: WalletRecord[];
  addWallet: (
    record: Omit<WalletRecord, "isPrimary">,
  ) => { ok: true } | { ok: false; error: string };
  removeWallet: (address: Address) => void;
  renameWallet: (address: Address, label: string) => void;
  setPrimary: (address: Address) => void;
}

function isDuplicate(wallets: WalletRecord[], address: Address): boolean {
  return wallets.some((w) => w.address.toLowerCase() === address.toLowerCase());
}

export const useWalletStore = create<WalletStore>()(
  persist(
    (set, get) => ({
      wallets: [],
      addWallet: (record) => {
        if (isDuplicate(get().wallets, record.address)) {
          return { ok: false, error: "This wallet is already added." };
        }
        const isFirst = get().wallets.length === 0;
        set((state) => ({
          wallets: [...state.wallets, { ...record, isPrimary: isFirst }],
        }));
        return { ok: true };
      },
      removeWallet: (address) => {
        set((state) => {
          const remaining = state.wallets.filter(
            (w) => w.address.toLowerCase() !== address.toLowerCase(),
          );
          const removedWasPrimary = state.wallets.some(
            (w) => w.address.toLowerCase() === address.toLowerCase() && w.isPrimary,
          );
          if (removedWasPrimary && remaining.length > 0) {
            const [first, ...rest] = remaining;
            if (first) return { wallets: [{ ...first, isPrimary: true }, ...rest] };
          }
          return { wallets: remaining };
        });
      },
      renameWallet: (address, label) => {
        set((state) => ({
          wallets: state.wallets.map((w) =>
            w.address.toLowerCase() === address.toLowerCase() ? { ...w, label } : w,
          ),
        }));
      },
      setPrimary: (address) => {
        set((state) => ({
          wallets: state.wallets.map((w) => ({
            ...w,
            isPrimary: w.address.toLowerCase() === address.toLowerCase(),
          })),
        }));
      },
    }),
    {
      name: "tidyr.wallets",
      partialize: (state) => ({ wallets: state.wallets }),
    },
  ),
);
