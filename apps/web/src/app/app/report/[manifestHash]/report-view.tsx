"use client";

import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { formatUnits, isHex, type Address } from "viem";
import type { Hex } from "@tidyr/shared";

import { Badge } from "@/components/ui/badge";
import { AddressText } from "@/components/ui/address";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/ui/error-state";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { erc20Abi } from "@/lib/abi/erc20";
import { useSweepReport, type DecodedTransfer } from "@/lib/report/use-sweep-report";

interface TokenMeta {
  symbol: string;
  decimals: number;
}

function useTokenMetadata(tokens: Address[]) {
  const publicClient = usePublicClient();
  const key = [...new Set(tokens.map((t) => t.toLowerCase()))].sort();

  return useQuery({
    queryKey: ["report-token-metadata", key],
    enabled: Boolean(publicClient) && key.length > 0,
    queryFn: async (): Promise<Map<Address, TokenMeta>> => {
      if (!publicClient) throw new Error("not ready");
      const map = new Map<Address, TokenMeta>();
      const calls = tokens.flatMap((token) => [
        { address: token, abi: erc20Abi, functionName: "symbol" } as const,
        { address: token, abi: erc20Abi, functionName: "decimals" } as const,
      ]);
      const results = await publicClient.multicall({ contracts: calls, allowFailure: true });
      tokens.forEach((token, i) => {
        const symbolResult = results[i * 2];
        const decimalsResult = results[i * 2 + 1];
        map.set(token, {
          symbol: symbolResult?.status === "success" ? (symbolResult.result as string) : "UNKNOWN",
          decimals: decimalsResult?.status === "success" ? (decimalsResult.result as number) : 18,
        });
      });
      return map;
    },
    staleTime: 60_000,
  });
}

function formatAmount(value: bigint, meta: TokenMeta | undefined): string {
  if (!meta) return value.toString();
  return formatUnits(value, meta.decimals);
}

function TransferTable({
  transfers,
  tokenMeta,
}: {
  transfers: DecodedTransfer[];
  tokenMeta: Map<Address, TokenMeta> | undefined;
}) {
  if (transfers.length === 0) {
    return <p className="text-sm text-(--color-body)">No Transfer events found in this transaction.</p>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[560px]">
        <thead>
          <tr className="border-b border-(--color-border) text-left text-xs text-(--color-muted)">
            <th className="pb-2 font-medium">Token</th>
            <th className="pb-2 font-medium">From</th>
            <th className="pb-2 font-medium">To</th>
            <th className="pb-2 font-medium">Amount</th>
          </tr>
        </thead>
        <tbody>
          {transfers.map((transfer) => {
            const meta = tokenMeta?.get(transfer.token);
            return (
              <tr
                key={`${transfer.token}-${transfer.logIndex}`}
                className="border-b border-(--color-border) text-sm last:border-0"
              >
                <td className="py-2 pr-4">
                  <p className="font-medium text-(--color-heading)">{meta?.symbol ?? "…"}</p>
                  <AddressText value={transfer.token} chars={4} />
                </td>
                <td className="py-2 pr-4">
                  <AddressText value={transfer.from} chars={4} />
                </td>
                <td className="py-2 pr-4">
                  <AddressText value={transfer.to} chars={4} />
                </td>
                <td className="py-2 pr-4 font-mono text-(--color-heading)">
                  {formatAmount(transfer.value, meta)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function ReportSkeleton() {
  return (
    <Card>
      <Skeleton className="h-5 w-40" />
      <div className="mt-3 space-y-2">
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-10 w-full" />
      </div>
    </Card>
  );
}

function InvalidHashState({ manifestHash }: { manifestHash: string }) {
  return (
    <ErrorState
      reason={`"${manifestHash}" is not a valid 32-byte hex hash — check the link and try again.`}
      action={null}
    />
  );
}

export function SweepReportView({ manifestHash }: { manifestHash: string }) {
  const isValidHash = isHex(manifestHash) && manifestHash.length === 66;
  const hash = isValidHash ? (manifestHash as Hex) : ("0x" as Hex);

  const { data, isLoading, isError, refetch, isFetching } = useSweepReport(hash);

  const transferTokens =
    data?.status === "found" ? data.transfers.map((t) => t.token) : [];
  const outputToken = data?.status === "found" ? data.sweepCompleted?.outputToken : undefined;
  const allTokens = outputToken ? [...transferTokens, outputToken] : transferTokens;
  const { data: tokenMeta } = useTokenMetadata(allTokens);

  if (!isValidHash) {
    return (
      <div className="flex flex-col gap-6 pb-24">
        <h1 className="font-display text-2xl font-medium text-(--color-heading)">Sweep report</h1>
        <InvalidHashState manifestHash={manifestHash} />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6 pb-24">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-2xl font-medium text-(--color-heading)">Sweep report</h1>
          <div className="mt-1 flex items-center gap-2 text-sm text-(--color-body)">
            <span className="text-(--color-muted)">Display manifest hash</span>
            <AddressText value={hash} chars={8} />
          </div>
          <p className="mt-2 max-w-2xl text-sm text-(--color-body)">
            Read-only. Reconstructed from real on-chain data — this browser&apos;s own record of
            the broadcast transaction where available, falling back to a bounded recent-block
            scan. There is no backend indexer; a manifest outside both paths honestly reports as
            not found rather than showing a fabricated result.
          </p>
        </div>
        <Button variant="ghost" onClick={() => refetch()} disabled={isFetching}>
          {isFetching ? "Refreshing…" : "Refresh"}
        </Button>
      </div>

      {isLoading ? (
        <ReportSkeleton />
      ) : isError ? (
        <ErrorState
          reason="Could not reconstruct this report — an on-chain read failed (RPC error or receipt lookup failed)."
          action={<Button onClick={() => refetch()}>Try again</Button>}
        />
      ) : !data ? null : data.status === "not-found" ? (
        <EmptyState title="Report not found" description={data.reason} />
      ) : (
        <Card className="flex flex-col gap-4">
          <div className="flex items-center justify-between gap-3">
            <Badge tone={data.txStatus === "success" ? "success" : "danger"}>
              {data.txStatus === "success" ? "Executed" : "Reverted"}
            </Badge>
            <Badge tone="neutral">
              {data.source === "local-record" ? "From local record" : "From recent-block scan"}
            </Badge>
          </div>

          <div className="flex flex-col gap-2 text-sm">
            <div className="flex items-center gap-2">
              <span className="text-(--color-muted)">Transaction</span>
              <AddressText value={data.txHash} chars={8} />
              <a
                href={`https://monadscan.com/tx/${data.txHash}`}
                target="_blank"
                rel="noreferrer noopener"
                className="text-(--color-accent) underline"
              >
                View on MonadScan
              </a>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-(--color-muted)">Block</span>
              <span className="font-mono text-(--color-heading)">{data.blockNumber.toString()}</span>
            </div>
          </div>

          {data.txStatus === "reverted" ? (
            <p className="text-sm text-[#8a1f1f]">
              This transaction reverted on-chain — no SweepCompleted event was emitted and no
              tokens moved.
            </p>
          ) : data.sweepCompleted ? (
            <div className="flex flex-col gap-2 border-t border-(--color-border) pt-3 text-sm">
              <div className="flex items-center gap-2">
                <span className="text-(--color-muted)">Owner</span>
                <AddressText value={data.sweepCompleted.owner} chars={4} />
              </div>
              <div className="flex items-center gap-2">
                <span className="text-(--color-muted)">Recipient</span>
                <AddressText value={data.sweepCompleted.recipient} chars={4} />
              </div>
              <div className="flex items-center gap-2">
                <span className="text-(--color-muted)">Output token</span>
                <AddressText value={data.sweepCompleted.outputToken} chars={4} />
              </div>
              <div className="flex items-center gap-2">
                <span className="text-(--color-muted)">Output amount</span>
                <span className="font-mono text-(--color-heading)">
                  {formatAmount(data.sweepCompleted.outputAmount, tokenMeta?.get(data.sweepCompleted.outputToken))}
                </span>
              </div>
              <div className="flex flex-wrap gap-2">
                <Badge tone="success">{data.sweepCompleted.successfulActions.toString()} succeeded</Badge>
                <Badge tone={data.sweepCompleted.failedActions > 0n ? "warning" : "neutral"}>
                  {data.sweepCompleted.failedActions.toString()} failed
                </Badge>
              </div>
            </div>
          ) : (
            <p className="text-sm text-(--color-body)">
              This transaction succeeded, but no SweepCompleted event was found in its logs —
              it may not be a TIDYR sweep execution.
            </p>
          )}

          <div className="border-t border-(--color-border) pt-3">
            <p className="mb-2 text-sm font-medium text-(--color-heading)">Transfers in this transaction</p>
            <TransferTable transfers={data.transfers} tokenMeta={tokenMeta} />
          </div>
        </Card>
      )}
    </div>
  );
}
