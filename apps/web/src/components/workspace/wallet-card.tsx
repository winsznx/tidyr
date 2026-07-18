"use client";

import { formatEther } from "viem";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { AddressText } from "@/components/ui/address";
import { Skeleton } from "@/components/ui/skeleton";
import { useWalletChainData } from "@/lib/use-wallet-chain-data";
import type { WalletRecord } from "@/store/wallets";
import { useWalletStore } from "@/store/wallets";

export function WalletCard({ wallet }: { wallet: WalletRecord }) {
  const { data, isLoading, isError } = useWalletChainData(wallet.address);
  const { removeWallet, setPrimary } = useWalletStore();

  return (
    <Card className="flex flex-col gap-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="text-sm font-medium text-(--color-heading)">{wallet.label}</p>
          <AddressText
            value={wallet.address}
            explorerUrl={`https://monadscan.com/address/${wallet.address}`}
          />
        </div>
        <div className="flex items-center gap-1.5">
          {wallet.isPrimary ? <Badge tone="accent">Primary</Badge> : null}
          {wallet.watchOnly ? (
            <Badge tone="neutral">Watch-only</Badge>
          ) : (
            <Badge tone="success">Signer</Badge>
          )}
        </div>
      </div>

      <div className="flex items-center justify-between text-sm">
        <span className="text-(--color-muted)">MON balance</span>
        {isLoading ? (
          <Skeleton className="h-4 w-20" />
        ) : isError ? (
          <span className="text-(--color-body)">Unavailable</span>
        ) : (
          <span className="font-mono text-(--color-heading)">
            {data ? formatEther(data.monBalance) : "0"}
          </span>
        )}
      </div>

      <div className="flex items-center justify-between text-sm">
        <span className="text-(--color-muted)">EIP-7702 delegation</span>
        {isLoading ? (
          <Skeleton className="h-4 w-24" />
        ) : data?.delegatedTo ? (
          <AddressText value={data.delegatedTo} chars={3} />
        ) : (
          <span className="text-(--color-body)">None</span>
        )}
      </div>

      <div className="flex gap-2 pt-1">
        {!wallet.isPrimary ? (
          <Button size="md" variant="ghost" onClick={() => setPrimary(wallet.address)}>
            Set primary
          </Button>
        ) : null}
        <Button size="md" variant="ghost" onClick={() => removeWallet(wallet.address)}>
          Remove
        </Button>
      </div>
    </Card>
  );
}
