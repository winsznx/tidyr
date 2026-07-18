"use client";

import { Badge } from "@/components/ui/badge";
import { AddressText } from "@/components/ui/address";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/ui/error-state";
import { Skeleton } from "@/components/ui/skeleton";
import type { WalletReview } from "@/lib/review/use-sweep-review";
import { useSweepReview } from "@/lib/review/use-sweep-review";
import { usePlanSignature } from "@/lib/review/use-plan-signature";
import { usePlanStore } from "@/store/plan";
import { useSignatureStore } from "@/store/signatures";
import { useWalletStore } from "@/store/wallets";

const ACTION_LABELS: Record<string, string> = {
  SWAP: "Sell",
  CONSOLIDATE: "Consolidate",
  DISCARD: "Discard",
  BURN: "Burn",
};

function ManifestSummary({ review }: { review: WalletReview }) {
  if (!review.manifest) return null;

  return (
    <div className="flex flex-wrap gap-2">
      {review.manifest.actions.map((action, i) => (
        <Badge key={`${action.token}-${action.type}-${i}`} tone="neutral">
          {ACTION_LABELS[action.type] ?? action.type} {action.amount} {action.tokenSymbol}
        </Badge>
      ))}
    </div>
  );
}

function blockingReason(review: WalletReview): string | null {
  if (!review.plan) return "This wallet's plan could not be built — resolve it on Review first.";
  if (review.roundTrip && !review.roundTrip.ok) {
    return "The calldata round-trip check failed on Review — do not sign until that's resolved.";
  }
  if (review.preconditions && !review.preconditions.ok) {
    return "Live precondition checks failed on Review (stale nonce, expired deadline, or output token no longer allow-listed) — refresh Review before signing.";
  }
  return null;
}

function SigningRow({ review, label }: { review: WalletReview; label: string }) {
  const existingSignature = useSignatureStore((s) => s.signatures[review.wallet]);
  const clearSignature = useSignatureStore((s) => s.clearSignature);
  const { connectedAddress, ownerMismatch, isPending, error, requestSignature } =
    usePlanSignature(review.plan, review.executionPlanHash);

  const reason = blockingReason(review);
  const canSign = !reason && !ownerMismatch && !existingSignature;

  return (
    <Card className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="font-medium text-(--color-heading)">{label}</p>
          <AddressText value={review.wallet} chars={4} />
        </div>
        {existingSignature ? (
          <Badge tone="success">Signed</Badge>
        ) : reason ? (
          <Badge tone="danger">Blocked</Badge>
        ) : (
          <Badge tone="warning">Awaiting signature</Badge>
        )}
      </div>

      {review.plan ? <ManifestSummary review={review} /> : null}

      {reason ? (
        <p className="text-sm text-(--color-body)">
          <Badge tone="danger">Blocked</Badge> <span className="ml-1">{reason}</span>
        </p>
      ) : null}

      {!reason && ownerMismatch ? (
        <p className="text-sm text-(--color-body)">
          <Badge tone="danger">Wallet mismatch</Badge>{" "}
          <span className="ml-1">
            Your wallet extension is connected as {connectedAddress}, but this plan belongs to{" "}
            {review.wallet}. Switch accounts before requesting this signature.
          </span>
        </p>
      ) : null}

      {error ? <p className="text-sm text-[#8a1f1f]">{error}</p> : null}

      {existingSignature ? (
        <div className="flex flex-col gap-2 border-t border-(--color-border) pt-3 text-sm">
          <div className="flex items-center gap-2">
            <span className="text-(--color-muted)">Signature</span>
            <AddressText value={existingSignature.signature} chars={8} />
          </div>
          <p className="text-xs text-(--color-body)">
            Signed {new Date(existingSignature.signedAt).toLocaleString()}
          </p>
          <div>
            <Button
              variant="ghost"
              size="md"
              onClick={() => clearSignature(review.wallet)}
            >
              Clear / re-sign
            </Button>
          </div>
        </div>
      ) : (
        <div>
          <Button
            variant="primary"
            size="md"
            disabled={!canSign || isPending}
            onClick={() => void requestSignature()}
          >
            {isPending ? "Requesting signature…" : "Request signature"}
          </Button>
        </div>
      )}
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

export default function ExecutePage() {
  const actions = usePlanStore((s) => s.actions);
  const wallets = useWalletStore((s) => s.wallets);
  const { data, isLoading, isError, refetch, isFetching } = useSweepReview();

  const hasNonRevokeActions = actions.some((a) => a.type !== "revoke");

  if (!hasNonRevokeActions) {
    return (
      <EmptyState
        title="Nothing to sign"
        description="Add wallets and choose actions on the Wallets page, then review the plan before signing."
      />
    );
  }

  return (
    <div className="flex flex-col gap-6 pb-24">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-2xl font-medium text-(--color-heading)">
            Sign sweep plan
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-(--color-body)">
            Signing authorizes SweepExecutor to pull exactly the tokens and amounts shown
            below, for this plan only. No transaction is sent yet — execution happens in a
            separate step. Each signature is a Permit2 EIP-712 message from your connected
            wallet; it never broadcasts anything by itself.
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
          reason="Could not rebuild the sweep plan — one or more on-chain reads failed (RPC error, or a quote call reverted)."
          action={<Button onClick={() => refetch()}>Try again</Button>}
        />
      ) : !data || data.length === 0 ? (
        <EmptyState
          title="No wallet plans to sign"
          description="No wallet with a planned action was found."
        />
      ) : (
        <div className="flex flex-col gap-4">
          {data.map((review) => {
            const wallet = wallets.find(
              (w) => w.address.toLowerCase() === review.wallet.toLowerCase(),
            );
            return (
              <SigningRow
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
