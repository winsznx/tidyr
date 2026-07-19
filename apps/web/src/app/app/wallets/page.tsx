"use client";

import { Suspense, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { IconPlus, IconWallet } from "@/components/ui/icon";
import { AddTokenDialog } from "@/components/workspace/add-token-dialog";
import { AddWalletDialog } from "@/components/workspace/add-wallet-dialog";
import { TokenInventory } from "@/components/workspace/token-inventory";
import { WalletCard } from "@/components/workspace/wallet-card";
import { usePlanStore } from "@/store/plan";
import { useWalletStore } from "@/store/wallets";

function WalletsPageContent() {
  const wallets = useWalletStore((s) => s.wallets);
  const actions = usePlanStore((s) => s.actions);
  const clearPlan = usePlanStore((s) => s.clearPlan);
  const [walletDialogOpen, setWalletDialogOpen] = useState(false);
  const [tokenDialogOpen, setTokenDialogOpen] = useState(false);
  const searchParams = useSearchParams();
  const initialQuery = searchParams.get("q") ?? "";

  return (
    <div className="flex flex-col gap-8 pb-24">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-2xl font-medium text-(--color-heading)">Wallets</h1>
        <div className="flex gap-2">
          <Button variant="ghost" onClick={() => setTokenDialogOpen(true)}>
            <IconPlus /> Track token
          </Button>
          <Button onClick={() => setWalletDialogOpen(true)}>
            <IconPlus /> Add wallet
          </Button>
        </div>
      </div>

      {wallets.length === 0 ? (
        <EmptyState
          title="No wallets added yet"
          description="Add a connected signer-capable wallet, or a watch-only address, to start scanning for tokens."
          action={<Button onClick={() => setWalletDialogOpen(true)}>Add wallet</Button>}
        />
      ) : (
        <>
          <section className="flex flex-col gap-4">
            <h2 className="flex items-center gap-2 font-display text-lg font-medium text-(--color-heading)">
              <IconWallet /> Your wallets
            </h2>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {wallets.map((wallet) => (
                <WalletCard key={wallet.address} wallet={wallet} />
              ))}
            </div>
          </section>

          <section className="flex flex-col gap-4">
            <h2 className="font-display text-lg font-medium text-(--color-heading)">
              Token inventory
            </h2>
            <TokenInventory wallets={wallets} initialQuery={initialQuery} />
          </section>
        </>
      )}

      <AddWalletDialog open={walletDialogOpen} onClose={() => setWalletDialogOpen(false)} />
      <AddTokenDialog open={tokenDialogOpen} onClose={() => setTokenDialogOpen(false)} />

      {actions.length > 0 ? (
        <div className="fixed inset-x-0 bottom-0 border-t border-(--color-border) bg-(--color-canvas) px-4 py-3 sm:left-56">
          <div className="mx-auto flex max-w-(--container-content) items-center justify-between">
            <Badge tone="accent">{actions.length} action(s) planned</Badge>
            <div className="flex gap-2">
              <Button variant="ghost" onClick={clearPlan}>
                Clear plan
              </Button>
              <Link href="/app/review">
                <Button>Review plan</Button>
              </Link>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

export default function WalletsPage() {
  return (
    <Suspense fallback={null}>
      <WalletsPageContent />
    </Suspense>
  );
}
