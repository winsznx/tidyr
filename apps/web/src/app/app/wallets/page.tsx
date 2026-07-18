"use client";

import { useState } from "react";

import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { AddWalletDialog } from "@/components/workspace/add-wallet-dialog";
import { WalletCard } from "@/components/workspace/wallet-card";
import { useWalletStore } from "@/store/wallets";

export default function WalletsPage() {
  const wallets = useWalletStore((s) => s.wallets);
  const [dialogOpen, setDialogOpen] = useState(false);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-2xl font-medium text-(--color-heading)">Wallets</h1>
        <Button onClick={() => setDialogOpen(true)}>Add wallet</Button>
      </div>

      {wallets.length === 0 ? (
        <EmptyState
          title="No wallets added yet"
          description="Add a connected signer-capable wallet, or a watch-only address, to start scanning for tokens."
          action={<Button onClick={() => setDialogOpen(true)}>Add wallet</Button>}
        />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {wallets.map((wallet) => (
            <WalletCard key={wallet.address} wallet={wallet} />
          ))}
        </div>
      )}

      <AddWalletDialog open={dialogOpen} onClose={() => setDialogOpen(false)} />
    </div>
  );
}
