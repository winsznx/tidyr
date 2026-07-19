"use client";

import { useEffect, useRef } from "react";

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
import { usePlanApprovals, type UsePlanApprovalsResult } from "@/lib/review/use-plan-approvals";
import { usePlanExecution, type PlanExecutionStatus } from "@/lib/review/use-plan-execution";
import { usePlanStore } from "@/store/plan";
import { useExecutionStore } from "@/store/executions";
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

const EXECUTION_STATUS_BADGE: Record<
  PlanExecutionStatus,
  { tone: "neutral" | "accent" | "success" | "warning" | "danger"; label: string }
> = {
  idle: { tone: "neutral", label: "Not simulated" },
  simulating: { tone: "warning", label: "Simulating…" },
  simulated: { tone: "success", label: "Simulation OK" },
  broadcasting: { tone: "warning", label: "Broadcasting…" },
  pending: { tone: "warning", label: "Pending" },
  success: { tone: "success", label: "Executed" },
  failed: { tone: "danger", label: "Failed" },
};

function ExecutionPanel({
  review,
  refetchReview,
}: {
  review: WalletReview;
  refetchReview: () => void;
}) {
  const existingSignature = useSignatureStore((s) => s.signatures[review.wallet]);
  const clearSignature = useSignatureStore((s) => s.clearSignature);
  const setExecution = useExecutionStore((s) => s.setExecution);
  const {
    status,
    connectedAddress,
    ownerMismatch,
    simulatedExecutionPlanHash,
    errorMessage,
    txHash,
    simulate,
    execute,
  } = usePlanExecution(review.plan, existingSignature?.signature ?? null);

  const autoSimulatedFor = useRef<string | null>(null);
  const recordedFor = useRef<string | null>(null);

  useEffect(() => {
    if (!existingSignature) return;
    if (ownerMismatch) return;
    if (autoSimulatedFor.current === existingSignature.signature) return;
    autoSimulatedFor.current = existingSignature.signature;
    void simulate();
  }, [existingSignature, ownerMismatch, simulate]);

  useEffect(() => {
    if (status !== "success") return;
    clearSignature(review.wallet);
    refetchReview();
  }, [status, clearSignature, refetchReview, review.wallet]);

  useEffect(() => {
    if (status !== "success") return;
    if (!txHash || !review.displayManifestHash || !review.executionPlanHash) return;
    if (recordedFor.current === txHash) return;
    recordedFor.current = txHash;
    setExecution({
      displayManifestHash: review.displayManifestHash,
      executionPlanHash: review.executionPlanHash,
      wallet: review.wallet,
      txHash,
      submittedAt: Date.now(),
    });
  }, [
    status,
    txHash,
    review.displayManifestHash,
    review.executionPlanHash,
    review.wallet,
    setExecution,
  ]);

  if (!existingSignature) return null;

  const badge = EXECUTION_STATUS_BADGE[status];

  return (
    <div className="flex flex-col gap-3 border-t border-(--color-border) pt-3">
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-(--color-heading)">Execution</span>
        <Badge tone={badge.tone}>{badge.label}</Badge>
      </div>

      {ownerMismatch ? (
        <p className="text-sm text-(--color-body)">
          <Badge tone="danger">Wallet mismatch</Badge>{" "}
          <span className="ml-1">
            Your wallet extension is connected as {connectedAddress}, but this plan belongs to{" "}
            {review.wallet}. Switch accounts before simulating or broadcasting.
          </span>
        </p>
      ) : null}

      {status === "simulated" && simulatedExecutionPlanHash ? (
        <p className="text-xs text-(--color-body)">
          Simulation succeeded — decoded execution plan hash{" "}
          <AddressText value={simulatedExecutionPlanHash} chars={8} />
        </p>
      ) : null}

      {errorMessage ? <p className="text-sm text-[#8a1f1f]">{errorMessage}</p> : null}

      {status === "pending" || status === "success" ? (
        txHash ? (
          <p className="text-xs text-(--color-body)">
            <a
              href={`https://monadscan.com/tx/${txHash}`}
              target="_blank"
              rel="noreferrer noopener"
              className="text-(--color-accent) underline"
            >
              View transaction on MonadScan
            </a>
          </p>
        ) : null
      ) : null}

      <div className="flex flex-wrap items-center gap-3">
        {status !== "simulated" && status !== "broadcasting" && status !== "pending" && status !== "success" ? (
          <Button
            variant="ghost"
            size="md"
            disabled={ownerMismatch || status === "simulating"}
            onClick={() => void simulate()}
          >
            {status === "simulating" ? "Simulating…" : "Simulate"}
          </Button>
        ) : null}

        {status !== "success" ? (
          <div className="flex flex-col gap-1">
            <Button
              variant="dark"
              size="md"
              disabled={status !== "simulated" || ownerMismatch}
              onClick={() => void execute()}
            >
              {status === "broadcasting"
                ? "Broadcasting…"
                : status === "pending"
                  ? "Awaiting confirmation…"
                  : "Broadcast"}
            </Button>
            <p className="text-xs text-(--color-body)">
              This broadcasts a real transaction that moves funds and cannot be undone.
            </p>
          </div>
        ) : null}
      </div>
    </div>
  );
}

function ApprovalsPanel({
  review,
  approvals,
}: {
  review: WalletReview;
  approvals: UsePlanApprovalsResult;
}) {
  const { statuses, allSufficient, isLoading, approve } = approvals;

  const symbolFor = (token: string): string =>
    review.manifest?.actions.find((a) => a.token.toLowerCase() === token.toLowerCase())
      ?.tokenSymbol ?? token;

  if (!review.plan || isLoading || statuses.length === 0) return null;
  if (allSufficient) return null;

  return (
    <div className="flex flex-col gap-2 border-t border-(--color-border) pt-3">
      <p className="text-sm font-medium text-(--color-heading)">Token approvals required</p>
      <p className="text-xs text-(--color-body)">
        Permit2 can only pull tokens this wallet has separately approved it to spend — a signature
        alone doesn&apos;t grant that. Each of these is a real, one-time on-chain approval
        transaction.
      </p>
      {statuses
        .filter((s) => !s.sufficient)
        .map((s) => (
          <div key={s.token} className="flex items-center justify-between gap-3 text-sm">
            <span className="text-(--color-heading)">{symbolFor(s.token)}</span>
            <Button
              variant="ghost"
              size="md"
              disabled={s.isApproving}
              onClick={() => void approve(s.token, s.required)}
            >
              {s.isApproving ? "Approving…" : "Approve"}
            </Button>
          </div>
        ))}
    </div>
  );
}

function SigningRow({
  review,
  label,
  refetchReview,
}: {
  review: WalletReview;
  label: string;
  refetchReview: () => void;
}) {
  const existingSignature = useSignatureStore((s) => s.signatures[review.wallet]);
  const clearSignature = useSignatureStore((s) => s.clearSignature);
  const { connectedAddress, ownerMismatch, isPending, error, requestSignature } =
    usePlanSignature(review.plan, review.executionPlanHash);
  const approvals = usePlanApprovals(review.plan);

  const reason = blockingReason(review);
  const canSign =
    !reason &&
    !ownerMismatch &&
    !existingSignature &&
    !approvals.isLoading &&
    approvals.allSufficient;

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

      {review.plan && !existingSignature ? (
        <ApprovalsPanel review={review} approvals={approvals} />
      ) : null}

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
          <ExecutionPanel review={review} refetchReview={refetchReview} />
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
            Sign &amp; execute sweep plan
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-(--color-body)">
            Signing authorizes SweepExecutor to pull exactly the tokens and amounts shown
            below, for this plan only — a Permit2 EIP-712 message that never broadcasts
            anything by itself. Once signed, a real read-only simulation runs against
            SweepExecutor before the Broadcast button unlocks. Broadcasting sends a real,
            irreversible transaction on Monad mainnet.
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
                refetchReview={() => void refetch()}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
