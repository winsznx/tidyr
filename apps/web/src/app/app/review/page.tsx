import { EmptyState } from "@/components/ui/empty-state";

export default function ReviewPage() {
  return (
    <EmptyState
      title="Transaction review"
      description="The three-layer verified review (intent manifest, calldata decode-and-compare, on-chain simulation) ships in a dedicated build pass — this is TIDYR's most security-critical surface and is not rushed."
    />
  );
}
