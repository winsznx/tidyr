"use client";

import { formatUnits } from "viem";
import type { Address } from "viem";

import { Badge } from "@/components/ui/badge";
import { AddressText } from "@/components/ui/address";
import { Skeleton } from "@/components/ui/skeleton";
import { useSellCapability } from "@/lib/tokens/use-sell-capability";
import type { TokenBalanceRow } from "@/lib/tokens/use-token-inventory";
import type { PlanActionType } from "@/store/plan";
import { usePlanStore } from "@/store/plan";
import { useWalletStore } from "@/store/wallets";

const ACTION_LABELS: Record<PlanActionType, string> = {
  sell: "Sell (route candidate)",
  consolidate: "Consolidate",
  discard: "Discard",
  burn: "Burn",
  revoke: "Revoke",
};

export function TokenRow({
  wallet,
  token,
  hideNoRouteCandidate = false,
}: {
  wallet: Address;
  token: TokenBalanceRow;
  hideNoRouteCandidate?: boolean;
}) {
  const { data: sellCapability, isLoading } = useSellCapability(token.address);
  const wallets = useWalletStore((s) => s.wallets);
  const primaryWallet = wallets.find((w) => w.isPrimary);
  const setAction = usePlanStore((s) => s.setAction);
  const actions = usePlanStore((s) => s.actions);

  const currentAction = actions.find((a) => a.wallet === wallet && a.token === token.address);

  if (
    hideNoRouteCandidate &&
    !isLoading &&
    !sellCapability?.hasRouteToMon &&
    !token.knownBurnable
  ) {
    return null;
  }

  const availableActions: PlanActionType[] = ["discard"];
  if (sellCapability?.hasRouteToMon) availableActions.unshift("sell");
  if (token.knownBurnable) availableActions.push("burn");
  if (wallets.length > 1 && primaryWallet) availableActions.push("consolidate");

  function handleAssign(type: PlanActionType | "") {
    if (!type) return;
    setAction({
      wallet,
      token: token.address,
      type,
      ...(type === "consolidate" && primaryWallet ? { recipient: primaryWallet.address } : {}),
    });
  }

  return (
    <tr className="border-b border-(--color-border) text-sm last:border-0">
      <td className="py-3 pr-4">
        <p className="font-medium text-(--color-heading)">{token.symbol}</p>
        <p className="text-xs text-(--color-muted)">{token.name}</p>
        <AddressText value={token.address} chars={4} />
      </td>
      <td className="py-3 pr-4 font-mono text-(--color-heading)">
        {formatUnits(token.balance, token.decimals)}
      </td>
      <td className="py-3 pr-4">
        {isLoading ? (
          <Skeleton className="h-5 w-24" />
        ) : sellCapability?.hasRouteToMon ? (
          <Badge tone="success">Route candidate: {sellCapability.routeVia}</Badge>
        ) : (
          <Badge tone="neutral">No route candidate found</Badge>
        )}
      </td>
      <td className="py-3">
        <select
          className="min-h-11 rounded-(--radius-input) border border-(--color-border) bg-(--color-canvas) px-2 text-sm"
          value={currentAction?.type ?? ""}
          onChange={(e) => handleAssign(e.target.value as PlanActionType | "")}
          aria-label={`Action for ${token.symbol}`}
        >
          <option value="">No action</option>
          {availableActions.map((action) => (
            <option key={action} value={action}>
              {ACTION_LABELS[action]}
            </option>
          ))}
        </select>
      </td>
    </tr>
  );
}
