"use client";

import { Badge } from "@/components/ui/badge";
import { AddressText } from "@/components/ui/address";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/ui/error-state";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { WalletReview } from "@/lib/review/use-sweep-review";
import { useSweepReview } from "@/lib/review/use-sweep-review";
import { usePlanStore } from "@/store/plan";
import { useWalletStore } from "@/store/wallets";

const ACTION_LABELS: Record<string, string> = {
  SWAP: "Sell",
  CONSOLIDATE: "Consolidate",
  DISCARD: "Discard",
  BURN: "Burn",
};

function ManifestTable({ review }: { review: WalletReview }) {
  if (!review.manifest) return null;

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[560px]">
        <thead>
          <tr className="border-b border-(--color-border) text-left text-xs text-(--color-muted)">
            <th className="pb-2 font-medium">Action</th>
            <th className="pb-2 font-medium">Token</th>
            <th className="pb-2 font-medium">Amount</th>
            <th className="pb-2 font-medium">Route</th>
            <th className="pb-2 font-medium">Min. output</th>
          </tr>
        </thead>
        <tbody>
          {review.manifest.actions.map((action, i) => (
            <tr
              key={`${action.token}-${action.type}-${i}`}
              className="border-b border-(--color-border) text-sm last:border-0"
            >
              <td className="py-2 pr-4">
                <Badge tone={action.type === "SWAP" ? "accent" : "neutral"}>
                  {ACTION_LABELS[action.type] ?? action.type}
                </Badge>
              </td>
              <td className="py-2 pr-4">
                <p className="font-medium text-(--color-heading)">{action.tokenSymbol}</p>
                <AddressText value={action.token} chars={4} />
              </td>
              <td className="py-2 pr-4 font-mono text-(--color-heading)">{action.amount}</td>
              <td className="py-2 pr-4 text-xs text-(--color-body)">{action.route ?? "—"}</td>
              <td className="py-2 pr-4 font-mono text-xs text-(--color-body)">
                {action.minimumOutput ?? "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function PreconditionBadges({ review }: { review: WalletReview }) {
  if (!review.preconditions) return null;
  const { outputTokenAllowed, nonceCurrent, deadlineInFuture } = review.preconditions;

  return (
    <div className="flex flex-wrap gap-2">
      <Badge tone={outputTokenAllowed ? "success" : "danger"}>
        Output token allow-listed: {outputTokenAllowed ? "yes" : "no"}
      </Badge>
      <Badge tone={nonceCurrent ? "success" : "danger"}>
        Nonce fresh: {nonceCurrent ? "yes" : "stale — re-review before signing"}
      </Badge>
      <Badge tone={deadlineInFuture ? "success" : "danger"}>
        Deadline valid: {deadlineInFuture ? "yes" : "expired — re-review before signing"}
      </Badge>
    </div>
  );
}

function WalletReviewCard({ review, label }: { review: WalletReview; label: string }) {
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="font-medium text-(--color-heading)">{label}</p>
          <AddressText value={review.wallet} chars={4} />
        </div>
        {review.plan ? (
          <Badge tone="success">Plan built</Badge>
        ) : (
          <Badge tone="danger">Plan blocked</Badge>
        )}
      </div>

      {review.errors.length > 0 ? (
        <div className="flex flex-col gap-2">
          {review.errors.map((error, i) => (
            <p key={i} className="text-sm text-(--color-heading)">
              <Badge tone="danger">Error</Badge> <span className="ml-1">{error}</span>
            </p>
          ))}
        </div>
      ) : null}

      {review.manifest ? <ManifestTable review={review} /> : null}

      {review.warnings.length > 0 ? (
        <div className="flex flex-col gap-1">
          {review.warnings.map((warning, i) => (
            <p key={i} className="text-xs text-(--color-body)">
              <Badge tone="warning">Excluded</Badge>{" "}
              <span className="ml-1">
                {warning.token} ({warning.type}): {warning.message}
              </span>
            </p>
          ))}
        </div>
      ) : null}

      {review.displayManifestHash && review.executionPlanHash ? (
        <div className="flex flex-col gap-2 border-t border-(--color-border) pt-3 text-sm">
          <div className="flex items-center gap-2">
            <span className="text-(--color-muted)">Display manifest hash</span>
            <AddressText value={review.displayManifestHash} chars={8} />
          </div>
          <div className="flex items-center gap-2">
            <span className="text-(--color-muted)">Execution plan hash</span>
            <AddressText value={review.executionPlanHash} chars={8} />
          </div>
        </div>
      ) : null}

      {review.roundTrip ? (
        <Badge tone={review.roundTrip.ok ? "success" : "danger"}>
          Calldata round-trip: {review.roundTrip.ok ? "verified" : "MISMATCH — do not sign"}
        </Badge>
      ) : null}

      <PreconditionBadges review={review} />
    </Card>
  );
}

function WalletCardSkeleton() {
  return (
    <Card>
      <Skeleton className="h-5 w-40" />
      <div className="mt-3 space-y-2">
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-10 w-full" />
      </div>
    </Card>
  );
}

export default function ReviewPage() {
  const actions = usePlanStore((s) => s.actions);
  const wallets = useWalletStore((s) => s.wallets);
  const { data, isLoading, isError, refetch, isFetching } = useSweepReview();

  const hasNonRevokeActions = actions.some((a) => a.type !== "revoke");

  if (!hasNonRevokeActions) {
    return (
      <EmptyState
        title="Nothing to review"
        description="Add wallets and choose actions (sell, consolidate, discard, burn) on the Wallets page first. Revoke actions are handled as separate wallet transactions, not part of this review."
      />
    );
  }

  return (
    <div className="flex flex-col gap-6 pb-24">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-2xl font-medium text-(--color-heading)">
            Review sweep plan
          </h1>
          <p className="mt-1 text-sm text-(--color-body)">
            Read-only. Every value below is a live on-chain read — no signature has been
            requested and nothing has been broadcast.
          </p>
        </div>
        <Button variant="ghost" onClick={() => refetch()} disabled={isFetching}>
          {isFetching ? "Refreshing…" : "Refresh"}
        </Button>
      </div>

      {isLoading ? (
        <div className="flex flex-col gap-4">
          <WalletCardSkeleton />
          <WalletCardSkeleton />
        </div>
      ) : isError ? (
        <ErrorState
          reason="Could not build the sweep plan — one or more on-chain reads failed (RPC error, or a quote call reverted)."
          action={<Button onClick={() => refetch()}>Try again</Button>}
        />
      ) : !data || data.length === 0 ? (
        <EmptyState
          title="No wallet plans to review"
          description="No wallet with a planned action was found."
        />
      ) : (
        <div className="flex flex-col gap-4">
          {data.map((review) => {
            const wallet = wallets.find(
              (w) => w.address.toLowerCase() === review.wallet.toLowerCase(),
            );
            return (
              <WalletReviewCard
                key={review.wallet}
                review={review}
                label={wallet?.label ?? review.wallet}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
