import { SweepReportView } from "./report-view";

export default async function ReportPage({
  params,
}: {
  params: Promise<{ manifestHash: string }>;
}) {
  const { manifestHash } = await params;

  return <SweepReportView manifestHash={manifestHash} />;
}
