import { Badge } from "@/components/ui/badge";

/** Shown inside the app workspace only (never the marketing landing page). */
export function StagingNotice() {
  return (
    <div className="flex items-center gap-2 border-b border-(--color-border) bg-(--color-cloud) px-4 py-2 text-xs text-(--color-body)">
      <Badge tone="warning">Staging</Badge>
      <span>
        Staging environment — real Monad mainnet contracts, chain-only, no backend. Transactions
        you sign here are real.
      </span>
    </div>
  );
}
