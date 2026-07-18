"use client";

import Link from "next/link";

import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { useConnectionState, hasAnyWalletPath } from "@/lib/connection-state";

export default function WorkspaceEntryPage() {
  const state = useConnectionState();

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

  return (
    <EmptyState
      title="Workspace ready"
      description="Add wallets and scan for tokens to start building a cleanup plan."
      action={
        <Link href="/app/wallets">
          <Button>Go to wallets</Button>
        </Link>
      }
    />
  );
}
