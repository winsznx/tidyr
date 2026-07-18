import type { TypedDataDefinition } from "viem";
import type { Hex, SweepPlan } from "@tidyr/shared";

import { EXTERNAL_ADDRESSES, MAINNET_DEPLOYMENT } from "@/lib/deployment";
import { aggregateTokenAmounts } from "@/lib/review/aggregate-token-amounts";

/**
 * Permit2's `PermitBatchWitnessTransferFrom` EIP-712 type, extended with TIDYR's own
 * `TidyrWitness` (packages/contracts/src/libraries/TidyrWitness.sol). Field order and
 * types mirror Permit2's `_PERMIT_BATCH_WITNESS_TRANSFER_FROM_TYPEHASH_STUB` exactly —
 * see packages/contracts/script/Phase10SmokeSweepFinal.s.sol's `_sign` for the
 * ground-truth reference this was derived from.
 */
const PERMIT2_TYPES = {
  PermitBatchWitnessTransferFrom: [
    { name: "permitted", type: "TokenPermissions[]" },
    { name: "spender", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "witness", type: "TidyrWitness" },
  ],
  TokenPermissions: [
    { name: "token", type: "address" },
    { name: "amount", type: "uint256" },
  ],
  TidyrWitness: [{ name: "executionPlanHash", type: "bytes32" }],
} as const;

export type Permit2TypedData = TypedDataDefinition<
  typeof PERMIT2_TYPES,
  "PermitBatchWitnessTransferFrom"
>;

/**
 * Builds the exact EIP-712 typed-data payload Permit2's `permitWitnessTransferFrom`
 * verifies (via `_pullViaPermit2` in packages/contracts/src/SweepExecutor.sol). No
 * `version` field and no `salt` in the domain — Permit2's own `EIP712.sol` domain
 * typehash is `EIP712Domain(string name,uint256 chainId,address verifyingContract)`.
 *
 * `spender` is `SweepExecutor`'s own address: `_pullViaPermit2` calls
 * `PERMIT2.permitWitnessTransferFrom` from within `SweepExecutor` itself, so Permit2
 * resolves `msg.sender` (the implicit spender) to `SweepExecutor`, not the plan owner.
 * `nonce` is `plan.nonce` unchanged — TIDYR deliberately reuses `SweepExecutor`'s own
 * per-owner nonce counter as the Permit2 nonce directly (see `_pullViaPermit2`, which
 * passes `plan.nonce` straight through in the `PermitBatchTransferFrom` struct).
 */
export function buildPermit2TypedData(
  plan: SweepPlan,
  executionPlanHash: Hex,
  chainId: number,
): Permit2TypedData {
  const permitted = aggregateTokenAmounts(plan).map(({ token, amount }) => ({ token, amount }));

  return {
    domain: {
      name: "Permit2",
      chainId,
      verifyingContract: EXTERNAL_ADDRESSES.permit2,
    },
    types: PERMIT2_TYPES,
    primaryType: "PermitBatchWitnessTransferFrom",
    message: {
      permitted,
      spender: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
      nonce: plan.nonce,
      deadline: plan.deadline,
      witness: { executionPlanHash },
    },
  };
}
