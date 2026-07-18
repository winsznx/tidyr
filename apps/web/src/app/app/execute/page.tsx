import { EmptyState } from "@/components/ui/empty-state";

export default function ExecutePage() {
  return (
    <EmptyState
      title="Signature queue and execution monitor"
      description="Per-wallet signing and live receipt-polling execution monitoring ship after the review flow. No transaction is ever sent from this route today."
    />
  );
}
