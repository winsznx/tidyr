import { useCallback, useMemo, useState } from "react";
import {
  BaseError,
  ContractFunctionRevertedError,
  type Address,
} from "viem";
import { useAccount, usePublicClient, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import type { Hex, SweepPlan } from "@tidyr/shared";

import { sweepExecutorAbi } from "@/lib/abi/sweep-executor";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";
import { useExecutionStore } from "@/store/executions";

export type PlanExecutionStatus =
  | "idle"
  | "simulating"
  | "simulated"
  | "broadcasting"
  | "pending"
  | "success"
  | "failed";

export interface UsePlanExecutionResult {
  status: PlanExecutionStatus;
  connectedAddress: Address | undefined;
  ownerMismatch: boolean;
  simulatedExecutionPlanHash: Hex | null;
  errorMessage: string | null;
  txHash: Hex | null;
  simulate: () => Promise<void>;
  execute: () => Promise<void>;
  reset: () => void;
}

/**
 * Maps the exact custom errors declared on SweepExecutor
 * (packages/contracts/src/SweepExecutor.sol) to a human-readable message,
 * including their decoded args where the contract provides them. Falls back
 * to the raw shortMessage from viem when the revert doesn't decode against
 * our ABI (e.g. a revert bubbling up from an adapter/token contract).
 */
function describeRevert(err: unknown): string {
  if (err instanceof BaseError) {
    const revertError = err.walk(
      (e) => e instanceof ContractFunctionRevertedError,
    ) as ContractFunctionRevertedError | undefined;

    if (revertError?.data) {
      const { errorName, args } = revertError.data;
      switch (errorName) {
        case "NotPlanOwner":
          return "Reverted: NotPlanOwner — the connected wallet is not this plan's owner on-chain.";
        case "ZeroRecipient":
          return "Reverted: ZeroRecipient — the plan's recipient address is the zero address.";
        case "OutputTokenNotAllowed":
          return `Reverted: OutputTokenNotAllowed(${args?.[0] ?? "unknown"}) — this output token is no longer allow-listed on SweepExecutor.`;
        case "PlanExpired":
          return "Reverted: PlanExpired — this plan's deadline has passed; rebuild and re-sign on Review.";
        case "InvalidPlanNonce":
          return `Reverted: InvalidPlanNonce(expected ${args?.[0] ?? "?"}, provided ${args?.[1] ?? "?"}) — this wallet's on-chain nonce has moved since the plan was built; refresh Review.`;
        case "AmbiguousSwapToken":
          return `Reverted: AmbiguousSwapToken(${args?.[0] ?? "unknown"}) — a swap's input token matches the settlement token.`;
        case "UnexpectedPulledAmount":
          return `Reverted: UnexpectedPulledAmount(token ${args?.[0] ?? "?"}, expected ${args?.[1] ?? "?"}, actual ${args?.[2] ?? "?"}) — Permit2 pulled a different amount than the plan declared.`;
        case "AdapterInvariantViolation":
          return `Reverted: AdapterInvariantViolation(adapter ${args?.[0] ?? "?"}, actualOut ${args?.[1] ?? "?"}, minRequired ${args?.[2] ?? "?"}) — a swap adapter returned less than its minimum.`;
        case "NativeTransferFailed":
          return "Reverted: NativeTransferFailed — sending native MON to the recipient failed.";
        default:
          return errorName
            ? `Reverted: ${errorName}${args && args.length > 0 ? `(${args.join(", ")})` : ""}`
            : err.shortMessage;
      }
    }

    return err.shortMessage;
  }

  return err instanceof Error ? err.message : "Simulation failed for an unknown reason.";
}

/**
 * Drives the real two-step F13 execution flow for one wallet's signed plan:
 * (1) `simulate()` — a real `publicClient.simulateContract` eth_call against
 * live chain state using the real Permit2 signature from F12, mirroring the
 * staticcall-before-broadcast discipline in
 * packages/contracts/script/Phase10SmokeSweepFinal.s.sol; (2) `execute()` —
 * only reachable after a successful simulation, sends the real
 * `executeSweep` transaction via `writeContractAsync` and polls for its
 * receipt. Nothing here runs automatically — both steps are only ever
 * invoked from an explicit caller action (see execute/page.tsx).
 *
 * The moment a real tx hash comes back from `writeContractAsync`, it is
 * persisted to `useExecutionStore` immediately — not gated on the receipt
 * poll resolving "success". A submitted transaction is a durable fact the
 * app must not lose track of even if this component unmounts or the page
 * reloads before confirmation lands (e.g. the user navigates away while a
 * broadcast is still pending); waiting for in-memory poll state to reach
 * "success" before recording anything meant a real, successful sweep could
 * go permanently unrecorded if the tab didn't stay open for the whole wait.
 */
export function usePlanExecution(
  plan: SweepPlan | null,
  signature: Hex | null,
  executionPlanHash: Hex | null,
): UsePlanExecutionResult {
  const publicClient = usePublicClient();
  const { address: connectedAddress } = useAccount();
  const { writeContractAsync } = useWriteContract();
  const setExecution = useExecutionStore((s) => s.setExecution);

  const [status, setStatus] = useState<PlanExecutionStatus>("idle");
  const [simulatedExecutionPlanHash, setSimulatedExecutionPlanHash] = useState<Hex | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<Hex | null>(null);

  const receipt = useWaitForTransactionReceipt({ hash: txHash ?? undefined });

  const ownerMismatch = Boolean(
    plan && connectedAddress && connectedAddress.toLowerCase() !== plan.owner.toLowerCase(),
  );

  const reset = useCallback(() => {
    setStatus("idle");
    setSimulatedExecutionPlanHash(null);
    setErrorMessage(null);
    setTxHash(null);
  }, []);

  const simulate = useCallback(async () => {
    if (!plan || !signature) {
      setErrorMessage("No signed plan available to simulate.");
      return;
    }
    if (!publicClient) {
      setErrorMessage("No RPC client available.");
      return;
    }
    if (!connectedAddress) {
      setErrorMessage("No wallet connected.");
      return;
    }
    if (connectedAddress.toLowerCase() !== plan.owner.toLowerCase()) {
      setErrorMessage(
        `Connected wallet (${connectedAddress}) does not match this plan's wallet (${plan.owner}). Switch accounts before simulating.`,
      );
      return;
    }

    setStatus("simulating");
    setErrorMessage(null);
    try {
      const { result } = await publicClient.simulateContract({
        address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
        abi: sweepExecutorAbi,
        functionName: "executeSweep",
        args: [plan, signature],
        account: connectedAddress,
      });
      setSimulatedExecutionPlanHash(result);
      setStatus("simulated");
    } catch (err) {
      setErrorMessage(describeRevert(err));
      setStatus("failed");
    }
  }, [plan, signature, publicClient, connectedAddress]);

  const execute = useCallback(async () => {
    if (status !== "simulated") {
      setErrorMessage("Run a successful simulation before broadcasting.");
      return;
    }
    if (!plan || !signature) {
      setErrorMessage("No signed plan available to execute.");
      return;
    }
    if (!connectedAddress || connectedAddress.toLowerCase() !== plan.owner.toLowerCase()) {
      setErrorMessage(
        "Connected wallet no longer matches this plan's owner. Re-check your wallet extension before broadcasting.",
      );
      setStatus("failed");
      return;
    }

    setStatus("broadcasting");
    setErrorMessage(null);
    try {
      const hash = await writeContractAsync({
        address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
        abi: sweepExecutorAbi,
        functionName: "executeSweep",
        args: [plan, signature],
      });
      setTxHash(hash);
      setStatus("pending");
      if (executionPlanHash) {
        setExecution({
          displayManifestHash: plan.displayManifestHash,
          executionPlanHash,
          wallet: plan.owner,
          txHash: hash,
          submittedAt: Date.now(),
        });
      }
    } catch (err) {
      setErrorMessage(describeRevert(err));
      setStatus("failed");
    }
  }, [status, plan, signature, connectedAddress, writeContractAsync, executionPlanHash, setExecution]);

  const derivedStatus = useMemo<PlanExecutionStatus>(() => {
    if (status !== "pending") return status;
    if (receipt.isSuccess) return receipt.data?.status === "success" ? "success" : "failed";
    if (receipt.isError) return "failed";
    return "pending";
  }, [status, receipt.isSuccess, receipt.isError, receipt.data]);

  return {
    status: derivedStatus,
    connectedAddress,
    ownerMismatch,
    simulatedExecutionPlanHash,
    errorMessage:
      derivedStatus === "failed" && status === "pending" && !errorMessage
        ? "Transaction reverted on-chain — check MonadScan for the exact failure."
        : errorMessage,
    txHash,
    simulate,
    execute,
    reset,
  };
}
