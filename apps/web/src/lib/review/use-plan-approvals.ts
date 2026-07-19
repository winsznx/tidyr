import { useCallback, useEffect, useState } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import type { Address, SweepPlan } from "@tidyr/shared";

import { erc20Abi } from "@/lib/abi/erc20";
import { EXTERNAL_ADDRESSES } from "@/lib/deployment";
import { aggregateTokenAmounts } from "@/lib/review/aggregate-token-amounts";

export interface TokenRequirement {
  token: Address;
  required: bigint;
  allowance: bigint;
  sufficient: boolean;
}

export interface TokenApprovalStatus extends TokenRequirement {
  isApproving: boolean;
}

export interface UsePlanApprovalsResult {
  statuses: TokenApprovalStatus[];
  allSufficient: boolean;
  isLoading: boolean;
  approve: (token: Address, amount: bigint) => Promise<void>;
  refetch: () => Promise<void>;
}

/**
 * Permit2's signature-based transfer does not replace the underlying ERC20
 * approval model — Permit2 still calls `transferFrom(owner, ..., amount)` on
 * the token itself, which requires `allowance(owner, PERMIT2) >= amount`
 * exactly like any other spender. A Permit2 signature only authorizes *what*
 * Permit2 may pull under the terms it verifies; it does not grant Permit2
 * the on-chain right to pull anything unless the owner has already run a
 * standard `approve(PERMIT2, amount)` transaction. Without this, executeSweep
 * reverts inside Permit2's own transferFrom call with `TRANSFER_FROM_FAILED`
 * (Solmate's SafeTransferLib revert string) - a real failure mode confirmed
 * against live mainnet state, not a hypothetical.
 *
 * This hook checks live allowance for every token the plan will pull
 * (`aggregateTokenAmounts` - the same exact token/amount list Permit2's
 * signature covers) and exposes a real per-token `approve()` action so the
 * Execute page can gate signing until every required allowance is in place.
 */
export function usePlanApprovals(plan: SweepPlan | null): UsePlanApprovalsResult {
  const publicClient = usePublicClient();
  const { address: connectedAddress } = useAccount();
  const { writeContractAsync } = useWriteContract();

  const [requirements, setRequirements] = useState<TokenRequirement[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [approvingToken, setApprovingToken] = useState<Address | null>(null);

  const refetch = useCallback(async () => {
    if (!plan || !publicClient || !connectedAddress) {
      setRequirements([]);
      return;
    }
    setIsLoading(true);
    try {
      const required = aggregateTokenAmounts(plan);
      const allowances = await publicClient.multicall({
        contracts: required.map(({ token }) => ({
          address: token,
          abi: erc20Abi,
          functionName: "allowance",
          args: [connectedAddress, EXTERNAL_ADDRESSES.permit2],
        })),
        allowFailure: true,
      });

      setRequirements(
        required.map(({ token, amount }, i) => {
          const result = allowances[i];
          const allowance = result?.status === "success" ? (result.result as bigint) : 0n;
          return {
            token,
            required: amount,
            allowance,
            sufficient: allowance >= amount,
          };
        }),
      );
    } finally {
      setIsLoading(false);
    }
  }, [plan, publicClient, connectedAddress]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  const approve = useCallback(
    async (token: Address, amount: bigint) => {
      if (!publicClient) return;
      setApprovingToken(token);
      try {
        const hash = await writeContractAsync({
          address: token,
          abi: erc20Abi,
          functionName: "approve",
          args: [EXTERNAL_ADDRESSES.permit2, amount],
        });
        await publicClient.waitForTransactionReceipt({ hash });
        await refetch();
      } finally {
        setApprovingToken(null);
      }
    },
    [publicClient, writeContractAsync, refetch],
  );

  const statuses: TokenApprovalStatus[] = requirements.map((r) => ({
    ...r,
    isApproving: approvingToken === r.token,
  }));

  return {
    statuses,
    allSufficient: statuses.length > 0 && statuses.every((s) => s.sufficient),
    isLoading,
    approve,
    refetch,
  };
}
