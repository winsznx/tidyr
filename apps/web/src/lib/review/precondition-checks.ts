import type { PublicClient } from "viem";
import type { SweepPlan } from "@tidyr/shared";

import { sweepExecutorAbi } from "@/lib/abi/sweep-executor";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";

export interface PreconditionCheckResult {
  outputTokenAllowed: boolean;
  nonceCurrent: boolean;
  liveNonce: bigint;
  deadlineInFuture: boolean;
  blockTimestamp: bigint;
  ok: boolean;
}

/**
 * Read-only, live preconditions against the real, frozen SweepExecutor. A
 * full `executeSweep` staticcall is deliberately NOT attempted here: it
 * requires a valid Permit2 signature, which does not exist until F12 (the
 * signing phase) produces one — attempting one now would only prove that a
 * missing/placeholder signature reverts, which tells us nothing. Instead we
 * verify every precondition `executeSweep` itself checks before it ever
 * touches Permit2: the output token is still allow-listed, the nonce this
 * plan was built against still matches the live nonce (protects against a
 * stale plan if this page sits open across another sweep), and the deadline
 * is still ahead of the *chain's* clock (not `Date.now()` — this mirrors the
 * exact on-chain check `executeSweep` performs against `block.timestamp`).
 * Once F12 produces a real signature, the full staticcall this defers can be
 * added — the same precedent already exists in
 * packages/contracts/script/Phase10SmokeSweepFinal.s.sol, which staticcalled
 * before broadcasting.
 */
export async function runPreconditionChecks(
  client: PublicClient,
  plan: SweepPlan,
): Promise<PreconditionCheckResult> {
  const [outputTokenAllowed, liveNonce, block] = await Promise.all([
    client.readContract({
      address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
      abi: sweepExecutorAbi,
      functionName: "allowedOutputTokens",
      args: [plan.outputToken],
    }),
    client.readContract({
      address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
      abi: sweepExecutorAbi,
      functionName: "nonces",
      args: [plan.owner],
    }),
    client.getBlock(),
  ]);

  const nonceCurrent = liveNonce === plan.nonce;
  const deadlineInFuture = plan.deadline > block.timestamp;

  return {
    outputTokenAllowed,
    nonceCurrent,
    liveNonce,
    deadlineInFuture,
    blockTimestamp: block.timestamp,
    ok: outputTokenAllowed && nonceCurrent && deadlineInFuture,
  };
}
