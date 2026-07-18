"use client";

import { EmptyState } from "@/components/ui/empty-state";
import { ProgressRing } from "@/components/ui/progress-ring";
import { Skeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/ui/stat-card";
import { NextStepCard } from "@/components/workspace/dashboard/next-step-card";
import { PlanBreakdownCard } from "@/components/workspace/dashboard/plan-breakdown-card";
import { ProtocolStatusCard } from "@/components/workspace/dashboard/protocol-status-card";
import { WalletsOverviewCard } from "@/components/workspace/dashboard/wallets-overview-card";
import { DEMO_TOKENS } from "@/lib/deployment";
import { hasAnyWalletPath, useConnectionState } from "@/lib/connection-state";
import { usePlanStore } from "@/store/plan";
import { useTrackedTokensStore } from "@/store/tracked-tokens";
import { useWalletStore } from "@/store/wallets";

export default function WorkspaceEntryPage() {
  const state = useConnectionState();
  const wallets = useWalletStore((s) => s.wallets);
  const actions = usePlanStore((s) => s.actions);
  const manualTokens = useTrackedTokensStore((s) => s.manualTokens);

  if (!hasAnyWalletPath()) {
    return (
      <EmptyState
        title="No wallet provider available"
        description="No injected wallet was detected and WalletConnect isn't configured in this deployment. Install an injected wallet (e.g. MetaMask) to continue."
      />
    );
  }

  if (state === "connecting") {
    return (
      <div className="max-w-md space-y-3">
        <Skeleton className="h-6 w-48" />
        <Skeleton className="h-4 w-64" />
      </div>
    );
  }

  if (state === "disconnected") {
    return (
      <EmptyState
        title="Connect a wallet to begin"
        description="TIDYR reads your wallets directly from Monad mainnet. Connect a signer-capable wallet using the button above, or add a watch-only address once connected."
      />
    );
  }

  if (state === "wrong-chain") {
    return (
      <EmptyState
        title="Switch to Monad mainnet"
        description="Your connected wallet is on a different chain. Use the network switcher above to continue — TIDYR only operates on Monad mainnet, chain ID 143."
      />
    );
  }

  const walletsWithActions = new Set(actions.map((a) => a.wallet)).size;
  const actionCoverage = wallets.length > 0 ? (walletsWithActions / wallets.length) * 100 : 0;
  const primaryWallet = wallets.find((w) => w.isPrimary);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-display text-2xl font-medium text-(--color-heading)">Dashboard</h1>
        <p className="mt-1 text-sm text-(--color-body)">
          Live state from Monad mainnet — nothing on this page is fabricated.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Wallets connected" value={wallets.length} href="/app/wallets" />
        <StatCard
          label="Tokens tracked"
          value={DEMO_TOKENS.length + manualTokens.length}
          subLabel={`${DEMO_TOKENS.length} known + ${manualTokens.length} manually tracked`}
          href="/app/wallets"
        />
        <StatCard label="Actions planned" value={actions.length} href="/app/wallets" />
        <StatCard
          label="Primary wallet"
          value={primaryWallet ? "Set" : "None"}
          subLabel={primaryWallet ? primaryWallet.label : "Add a wallet to set one"}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <WalletsOverviewCard wallets={wallets} />
        </div>
        <ProtocolStatusCard />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <PlanBreakdownCard actions={actions} />
        <div className="flex flex-col items-center justify-center gap-2 rounded-(--radius-card) border border-(--color-border) bg-(--color-canvas) p-5">
          <ProgressRing percent={actionCoverage} label="Wallets with a planned action" />
        </div>
        <NextStepCard walletsCount={wallets.length} actionsCount={actions.length} />
      </div>
    </div>
  );
}
