import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";

import { erc20Abi } from "@/lib/abi/erc20";
import { DEMO_TOKENS, MAINNET_DEPLOYMENT } from "@/lib/deployment";
import { useTrackedTokensStore } from "@/store/tracked-tokens";

export interface TokenBalanceRow {
  address: Address;
  symbol: string;
  name: string;
  decimals: number;
  balance: bigint;
  /** DUST4 is the only demo token with a real burn() function (BurnableDemoToken). */
  knownBurnable: boolean;
}

/**
 * Reads balances + metadata for the candidate token list (known demo tokens
 * + user-added addresses — there is no wallet-wide indexer, see
 * frontend-integration-matrix.md §0) for a single wallet, via multicall.
 * Zero-balance tokens are filtered out here; callers that need the raw count
 * for a "N zero-balance tokens hidden" affordance should read
 * `allCandidatesCount` from the returned object.
 */
export function useTokenInventory(wallet: Address | undefined) {
  const publicClient = usePublicClient();
  const manualTokens = useTrackedTokensStore((s) => s.manualTokens);

  const candidates: Address[] = [...DEMO_TOKENS.map((t) => t.address as Address), ...manualTokens];

  return useQuery({
    queryKey: ["token-inventory", wallet, candidates],
    enabled: Boolean(wallet && publicClient && candidates.length > 0),
    queryFn: async (): Promise<{ rows: TokenBalanceRow[]; allCandidatesCount: number }> => {
      if (!wallet || !publicClient) throw new Error("not ready");

      const balances = await publicClient.multicall({
        contracts: candidates.map((address) => ({
          address,
          abi: erc20Abi,
          functionName: "balanceOf",
          args: [wallet],
        })),
        allowFailure: true,
      });

      const nonZero = candidates
        .map((address, i) => ({ address, result: balances[i] }))
        .filter(
          (entry): entry is { address: Address; result: { status: "success"; result: bigint } } =>
            entry.result?.status === "success" && (entry.result.result as bigint) > 0n,
        );

      if (nonZero.length === 0) {
        return { rows: [], allCandidatesCount: candidates.length };
      }

      const metadataCalls = nonZero.flatMap(({ address }) => [
        { address, abi: erc20Abi, functionName: "symbol" } as const,
        { address, abi: erc20Abi, functionName: "name" } as const,
        { address, abi: erc20Abi, functionName: "decimals" } as const,
      ]);
      const metadataResults = await publicClient.multicall({
        contracts: metadataCalls,
        allowFailure: true,
      });

      const rows: TokenBalanceRow[] = nonZero.map(({ address, result }, i) => {
        const symbolResult = metadataResults[i * 3];
        const nameResult = metadataResults[i * 3 + 1];
        const decimalsResult = metadataResults[i * 3 + 2];
        return {
          address,
          symbol: symbolResult?.status === "success" ? (symbolResult.result as string) : "UNKNOWN",
          name: nameResult?.status === "success" ? (nameResult.result as string) : "Unknown token",
          decimals: decimalsResult?.status === "success" ? (decimalsResult.result as number) : 18,
          balance: result.result,
          knownBurnable: address.toLowerCase() === MAINNET_DEPLOYMENT.addresses.dust4.toLowerCase(),
        };
      });

      return { rows, allCandidatesCount: candidates.length };
    },
    staleTime: 15_000,
  });
}
