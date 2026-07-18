import { EmptyState } from "@/components/ui/empty-state";

export default async function ReportPage({
  params,
}: {
  params: Promise<{ manifestHash: string }>;
}) {
  const { manifestHash } = await params;

  return (
    <EmptyState
      title={`Report for ${manifestHash}`}
      description="Finalized reports are rebuilt from indexed SweepCompleted/Transfer events, never from local success state. Report rendering ships in the same pass as the execution monitor."
    />
  );
}
