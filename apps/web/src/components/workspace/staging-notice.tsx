import { Badge } from "@/components/ui/badge";

/** Shown inside the app workspace only (never the marketing landing page). */
export function StagingNotice() {
  return (
    <div className="flex items-center gap-2 border-b border-(--color-border) bg-(--color-cloud) px-4 py-2 text-xs text-(--color-body)">
      <Badge tone="warning">Preview</Badge>
      <span>
        Preview environment — transaction preparation and execution services are not yet enabled.
      </span>
    </div>
  );
}
