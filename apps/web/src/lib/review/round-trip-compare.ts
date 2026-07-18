import { decodeFunctionData, encodeFunctionData } from "viem";
import type { Hex } from "viem";
import type { SweepPlan } from "@tidyr/shared";
import { hashExecutionPlan } from "@tidyr/transaction-review";

import { sweepExecutorAbi } from "@/lib/abi/sweep-executor";
import { MAINNET_CHAIN_ID, MAINNET_DEPLOYMENT } from "@/lib/deployment";

export interface RoundTripCompareResult {
  ok: boolean;
  preEncodeHash: Hex;
  postDecodeHash: Hex;
  calldata: Hex;
}

/**
 * Proves the client-built `SweepPlan` survives ABI encode/decode losslessly
 * before the user is ever asked to sign anything: encodes the plan against
 * the real `executeSweep` calldata shape (a placeholder, never-submitted
 * signature is used only because the function requires one positionally —
 * it plays no role in the hash comparison below), decodes it straight back,
 * and asserts `hashExecutionPlan` computed on the decoded plan matches the
 * hash computed on the original pre-encode plan. This is the calldata
 * decode-and-compare layer described in PRD §11 Layer 2.
 */
export function verifyRoundTrip(plan: SweepPlan): RoundTripCompareResult {
  const preEncodeHash = hashExecutionPlan(
    plan,
    BigInt(MAINNET_CHAIN_ID),
    MAINNET_DEPLOYMENT.addresses.sweepExecutor,
  );

  const calldata = encodeFunctionData({
    abi: sweepExecutorAbi,
    functionName: "executeSweep",
    args: [plan, "0x"],
  });

  const decoded = decodeFunctionData({
    abi: sweepExecutorAbi,
    data: calldata,
  });

  if (decoded.functionName !== "executeSweep") {
    return { ok: false, preEncodeHash, postDecodeHash: "0x" as Hex, calldata };
  }

  const [decodedPlan] = decoded.args as [SweepPlan, Hex];
  const postDecodeHash = hashExecutionPlan(
    decodedPlan,
    BigInt(MAINNET_CHAIN_ID),
    MAINNET_DEPLOYMENT.addresses.sweepExecutor,
  );

  return {
    ok: preEncodeHash === postDecodeHash,
    preEncodeHash,
    postDecodeHash,
    calldata,
  };
}
