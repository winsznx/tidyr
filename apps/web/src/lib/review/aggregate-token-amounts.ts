import type { Address, SweepPlan } from "@tidyr/shared";

export interface TokenAmount {
  token: Address;
  amount: bigint;
}

/**
 * Mirrors `SweepPlanLib.aggregateTokenAmounts` (packages/contracts/src/libraries/
 * SweepPlanLib.sol) exactly: iterates swaps, then transfers, then discards, then
 * burns, accumulating into a first-seen-order deduped list keyed by token address,
 * summing amounts for repeats. This exact array — same tokens, same order, same
 * summed amounts — is what Permit2 verifies the signature against on-chain, so the
 * iteration order here must match the Solidity loop order exactly.
 */
export function aggregateTokenAmounts(plan: SweepPlan): TokenAmount[] {
  const indexByToken = new Map<Address, number>();
  const result: TokenAmount[] = [];

  function accumulate(token: Address, amount: bigint): void {
    const existingIndex = indexByToken.get(token);
    if (existingIndex !== undefined) {
      const existing = result[existingIndex];
      if (existing) {
        existing.amount += amount;
      }
      return;
    }
    indexByToken.set(token, result.length);
    result.push({ token, amount });
  }

  for (const swap of plan.swaps) {
    accumulate(swap.tokenIn, swap.amountIn);
  }
  for (const transfer of plan.transfers) {
    accumulate(transfer.token, transfer.amount);
  }
  for (const discard of plan.discards) {
    accumulate(discard.token, discard.amount);
  }
  for (const burn of plan.burns) {
    accumulate(burn.token, burn.amount);
  }

  return result;
}
