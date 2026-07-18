import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";

/** EIP-7702 delegation designator prefix (0xef0100 || address). */
const DELEGATION_PREFIX = "0xef0100";

export interface WalletChainData {
  monBalance: bigint;
  delegatedTo: Address | null;
}

/**
 * Live per-wallet chain reads: native MON balance and EIP-7702 delegation
 * state (detected by reading the account's own bytecode for the delegation
 * designator prefix — a real on-chain read, not an assumption). Returns
 * `delegatedTo: null` for a normal EOA with no code, distinguishing that from
 * "unknown" (query still loading), which callers get via TanStack Query's
 * own `isLoading`.
 */
export function useWalletChainData(address: Address | undefined) {
  const publicClient = usePublicClient();

  return useQuery({
    queryKey: ["wallet-chain-data", address],
    enabled: Boolean(address && publicClient),
    queryFn: async (): Promise<WalletChainData> => {
      if (!address || !publicClient) throw new Error("not ready");
      const [monBalance, code] = await Promise.all([
        publicClient.getBalance({ address }),
        publicClient.getCode({ address }),
      ]);
      const delegatedTo =
        code && code.toLowerCase().startsWith(DELEGATION_PREFIX)
          ? (`0x${code.slice(8, 48)}` as Address)
          : null;
      return { monBalance, delegatedTo };
    },
    staleTime: 15_000,
  });
}
