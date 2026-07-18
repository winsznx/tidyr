import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { AddressText } from "@/components/ui/address";
import { EmptyState } from "@/components/ui/empty-state";
import { Button } from "@/components/ui/button";
import type { WalletRecord } from "@/store/wallets";

function initials(label: string): string {
  const parts = label.trim().split(/\s+/);
  return (parts[0]?.[0] ?? "?").toUpperCase() + (parts[1]?.[0]?.toUpperCase() ?? "");
}

export function WalletsOverviewCard({ wallets }: { wallets: WalletRecord[] }) {
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-base font-medium text-(--color-heading)">
          Connected wallets
        </h2>
        <Link href="/app/wallets">
          <Button size="md" variant="ghost">
            Manage
          </Button>
        </Link>
      </div>

      {wallets.length === 0 ? (
        <EmptyState
          title="No wallets yet"
          description="Add a wallet to see it here."
          action={
            <Link href="/app/wallets">
              <Button size="md">Add wallet</Button>
            </Link>
          }
        />
      ) : (
        <div className="flex flex-col divide-y divide-(--color-border)">
          {wallets.map((wallet) => (
            <div key={wallet.address} className="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-(--radius-pill) bg-(--color-accent-pale) text-xs font-semibold text-(--color-accent)">
                {initials(wallet.label)}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium text-(--color-heading)">
                  {wallet.label}
                </p>
                <AddressText value={wallet.address} chars={4} />
              </div>
              <div className="flex shrink-0 items-center gap-1.5">
                {wallet.isPrimary ? <Badge tone="accent">Primary</Badge> : null}
                {wallet.watchOnly ? (
                  <Badge tone="neutral">Watch-only</Badge>
                ) : (
                  <Badge tone="success">Signer</Badge>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
