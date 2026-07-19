"use client";

import { useState } from "react";
import type { Address } from "viem";
import { MON_NATIVE_SENTINEL } from "@tidyr/shared";

import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { EXTERNAL_ADDRESSES } from "@/lib/deployment";
import { useTokenInventory } from "@/lib/tokens/use-token-inventory";
import { usePlanStore } from "@/store/plan";
import type { WalletRecord } from "@/store/wallets";
import { TokenRow } from "./token-row";

const SELL_OUTPUT_OPTIONS = [
  { label: "MON", value: MON_NATIVE_SENTINEL },
  { label: "USDC", value: EXTERNAL_ADDRESSES.usdc },
] as const;

function WalletTokenTable({
  wallet,
  search,
  hideNoRouteCandidate,
}: {
  wallet: WalletRecord;
  search: string;
  hideNoRouteCandidate: boolean;
}) {
  const { data, isLoading, isError } = useTokenInventory(wallet.address as Address);
  const actions = usePlanStore((s) => s.actions);
  const setAction = usePlanStore((s) => s.setAction);
  const [outputToken, setOutputToken] = useState<Address>(MON_NATIVE_SENTINEL);

  function handleOutputTokenChange(next: Address) {
    setOutputToken(next);
    // Every sell action in this wallet must agree on one outputToken (a SweepPlan
    // has exactly one) — re-point any already-assigned sell actions rather than
    // leaving them pointed at the stale choice, which would otherwise resurface
    // as Review's "different output tokens" blocking error.
    for (const action of actions) {
      if (action.wallet === wallet.address && action.type === "sell") {
        setAction({ ...action, outputToken: next });
      }
    }
  }

  const filtered = (data?.rows ?? []).filter((row) => {
    if (!search) return true;
    const needle = search.toLowerCase();
    return (
      row.symbol.toLowerCase().includes(needle) ||
      row.name.toLowerCase().includes(needle) ||
      row.address.toLowerCase().includes(needle)
    );
  });

  if (isLoading) {
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

  if (isError) {
    return (
      <Card>
        <p className="text-sm font-medium text-(--color-heading)">{wallet.label}</p>
        <p className="mt-2 text-sm text-(--color-body)">
          Could not read token balances for this wallet — the RPC call failed. Try again shortly.
        </p>
      </Card>
    );
  }

  if (filtered.length === 0) {
    return (
      <Card>
        <p className="text-sm font-medium text-(--color-heading)">{wallet.label}</p>
        <p className="mt-2 text-sm text-(--color-body)">
          {data && data.allCandidatesCount > 0
            ? "No tracked token has a nonzero balance in this wallet."
            : "No tokens are tracked yet — add a token address to scan for it."}
        </p>
      </Card>
    );
  }

  return (
    <Card className="overflow-x-auto">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm font-medium text-(--color-heading)">{wallet.label}</p>
        <label className="flex items-center gap-2 text-xs text-(--color-body)">
          Sell output
          <select
            className="min-h-8 rounded-(--radius-input) border border-(--color-border) bg-(--color-canvas) px-2 text-sm"
            value={outputToken}
            onChange={(e) => handleOutputTokenChange(e.target.value as Address)}
            aria-label={`Sell output token for ${wallet.label}`}
          >
            {SELL_OUTPUT_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
      </div>
      <table className="w-full min-w-[480px]">
        <thead>
          <tr className="border-b border-(--color-border) text-left text-xs text-(--color-muted)">
            <th className="pb-2 font-medium">Token</th>
            <th className="pb-2 font-medium">Balance</th>
            <th className="pb-2 font-medium">Route</th>
            <th className="pb-2 font-medium">Action</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((row) => (
            <TokenRow
              key={row.address}
              wallet={wallet.address as Address}
              token={row}
              outputToken={outputToken}
              hideNoRouteCandidate={hideNoRouteCandidate}
            />
          ))}
        </tbody>
      </table>
    </Card>
  );
}

export function TokenInventory({
  wallets,
  initialQuery = "",
}: {
  wallets: WalletRecord[];
  initialQuery?: string;
}) {
  const [search, setSearch] = useState(initialQuery);
  const [hideNoRouteCandidate, setHideNoRouteCandidate] = useState(false);

  if (wallets.length === 0) {
    return (
      <EmptyState
        title="No wallets to scan"
        description="Add a wallet above to see its token inventory here."
      />
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by symbol, name, or address"
          aria-label="Search tokens"
          className="max-w-sm"
        />
        <label className="flex items-center gap-2 text-sm text-(--color-body)">
          <Switch
            checked={hideNoRouteCandidate}
            onChange={setHideNoRouteCandidate}
            label="Hide tokens with no route candidate or burn capability"
          />
          Hide tokens with no action available
        </label>
      </div>
      {wallets.map((wallet) => (
        <WalletTokenTable
          key={wallet.address}
          wallet={wallet}
          search={search}
          hideNoRouteCandidate={hideNoRouteCandidate}
        />
      ))}
    </div>
  );
}
