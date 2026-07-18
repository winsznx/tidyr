import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { getAbiItem, parseEventLogs, type Address } from "viem";
import type { Hex } from "@tidyr/shared";

import { sweepExecutorAbi } from "@/lib/abi/sweep-executor";
import { transferEventAbi } from "@/lib/abi/erc20";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";
import { useExecutionStore } from "@/store/executions";

export interface DecodedSweepCompleted {
  executionPlanHash: Hex;
  displayManifestHash: Hex;
  owner: Address;
  recipient: Address;
  outputToken: Address;
  outputAmount: bigint;
  successfulActions: bigint;
  failedActions: bigint;
}

export interface DecodedTransfer {
  token: Address;
  from: Address;
  to: Address;
  value: bigint;
  logIndex: number;
}

export type SweepReportResult =
  | {
      status: "found";
      txHash: Hex;
      txStatus: "success" | "reverted";
      blockNumber: bigint;
      source: "local-record" | "log-scan";
      sweepCompleted: DecodedSweepCompleted | null;
      transfers: DecodedTransfer[];
    }
  | { status: "not-found"; reason: string };

/**
 * `eth_getLogs` block-range cap on Monad mainnet, empirically observed
 * against the live public RPC (https://rpc.monad.xyz, the same endpoint
 * apps/web/src/app/api/rpc/route.ts falls back to): requesting a span over
 * 99 blocks (`toBlock - fromBlock > 99`) returns the explicit JSON-RPC error
 * `{"code":-32614,"message":"eth_getLogs is limited to a 100 range"}`. A span
 * of exactly 99 (100 blocks inclusive) succeeds. This is a real, current
 * measurement, not the "~100" figure from older notes.
 */
const GET_LOGS_MAX_SPAN = 99n;

/**
 * Observed Monad mainnet block production rate (two `eth_blockNumber` calls
 * five seconds apart advanced 15 blocks: ~0.40s/block). At that rate, one
 * 100-block window covers ~40 seconds of chain time. 20 chunks therefore
 * covers roughly 2,000 blocks (~13 minutes) of very recent history — enough
 * to catch a tx broadcast moments ago if the local execution record was lost
 * (e.g. localStorage cleared mid-session), while keeping the fallback scan to
 * a bounded ~20 RPC calls before honestly giving up.
 */
const FALLBACK_MAX_CHUNKS = 20;

const sweepCompletedEvent = getAbiItem({ abi: sweepExecutorAbi, name: "SweepCompleted" });

function decodeSweepCompletedLog(log: {
  args: {
    executionPlanHash: Hex;
    displayManifestHash: Hex;
    owner: Address;
    recipient: Address;
    outputToken: Address;
    outputAmount: bigint;
    successfulActions: bigint;
    failedActions: bigint;
  };
}): DecodedSweepCompleted {
  return { ...log.args };
}

function decodeTransferLogs(
  logs: readonly { address: Address; logIndex: number; args: { from: Address; to: Address; value: bigint } }[],
): DecodedTransfer[] {
  return logs.map((log) => ({
    token: log.address,
    from: log.args.from,
    to: log.args.to,
    value: log.args.value,
    logIndex: log.logIndex,
  }));
}

/**
 * Reconstructs what actually happened for a given `displayManifestHash` from
 * real on-chain data only — never from optimistic local state. Two paths,
 * per docs/frontend-integration-matrix.md's Report row:
 *
 * (a) Primary — this browser's own locally-retained execution record
 * (`useExecutionStore`, set by F13's execute/page.tsx once a broadcast
 * reaches `"success"`). Once we have that record's `txHash`, its receipt is
 * fetched directly — `receipt.logs` already scopes exactly to this one
 * transaction (no cross-tx pollution within its block, unlike a block-range
 * `getLogs` call, which would return every matching event from every
 * transaction in that block and still need txHash-based filtering
 * afterward). Decoding `receipt.logs` is therefore strictly more precise
 * than an additional `getLogs` call here, at zero extra RPC round-trips.
 *
 * (b) Fallback — no local record (different browser/device, or localStorage
 * was cleared). Best-effort: scan backward from the chain tip in
 * `GET_LOGS_MAX_SPAN`-wide windows, filtering `SweepCompleted` by the
 * `displayManifestHash` topic directly, for up to `FALLBACK_MAX_CHUNKS`
 * windows. If nothing turns up, this honestly reports "not found in the
 * queryable window" — there is no backend indexer to fall back to further.
 */
export function useSweepReport(displayManifestHash: Hex) {
  const publicClient = usePublicClient();
  const localRecord = useExecutionStore((s) => s.records[displayManifestHash]);

  return useQuery({
    queryKey: ["sweep-report", displayManifestHash, localRecord?.txHash],
    enabled: Boolean(publicClient),
    queryFn: async (): Promise<SweepReportResult> => {
      if (!publicClient) throw new Error("not ready");

      if (localRecord) {
        const receipt = await publicClient.getTransactionReceipt({ hash: localRecord.txHash });

        if (receipt.status !== "success") {
          return {
            status: "found",
            txHash: localRecord.txHash,
            txStatus: "reverted",
            blockNumber: receipt.blockNumber,
            source: "local-record",
            sweepCompleted: null,
            transfers: [],
          };
        }

        const sweepCompletedLogs = parseEventLogs({
          abi: sweepExecutorAbi,
          eventName: "SweepCompleted",
          logs: receipt.logs,
        });
        const transferLogs = parseEventLogs({
          abi: transferEventAbi,
          eventName: "Transfer",
          logs: receipt.logs,
        });

        return {
          status: "found",
          txHash: localRecord.txHash,
          txStatus: "success",
          blockNumber: receipt.blockNumber,
          source: "local-record",
          sweepCompleted: sweepCompletedLogs[0] ? decodeSweepCompletedLog(sweepCompletedLogs[0]) : null,
          transfers: decodeTransferLogs(transferLogs),
        };
      }

      const latestBlock = await publicClient.getBlockNumber();
      let toBlock = latestBlock;

      for (let chunk = 0; chunk < FALLBACK_MAX_CHUNKS; chunk++) {
        const fromBlock = toBlock > GET_LOGS_MAX_SPAN ? toBlock - GET_LOGS_MAX_SPAN : 0n;

        const rawLogs = await publicClient.getLogs({
          address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
          event: sweepCompletedEvent,
          args: { displayManifestHash },
          fromBlock,
          toBlock,
        });
        const matches = parseEventLogs({
          abi: sweepExecutorAbi,
          eventName: "SweepCompleted",
          logs: rawLogs,
        });

        if (matches.length > 0) {
          const match = matches[matches.length - 1];
          if (!match) break;
          const receipt = await publicClient.getTransactionReceipt({ hash: match.transactionHash });
          const transferLogs = parseEventLogs({
            abi: transferEventAbi,
            eventName: "Transfer",
            logs: receipt.logs,
          });

          return {
            status: "found",
            txHash: match.transactionHash,
            txStatus: receipt.status === "success" ? "success" : "reverted",
            blockNumber: receipt.blockNumber,
            source: "log-scan",
            sweepCompleted: decodeSweepCompletedLog(match),
            transfers: decodeTransferLogs(transferLogs),
          };
        }

        if (fromBlock === 0n) break;
        toBlock = fromBlock - 1n;
      }

      return {
        status: "not-found",
        reason:
          "Not found in the queryable window — no permanent indexer exists for older manifests. " +
          "This browser has no locally-retained record of this manifest's transaction, and it did " +
          "not turn up in the most recent on-chain history this app can scan.",
      };
    },
    staleTime: 15_000,
  });
}
