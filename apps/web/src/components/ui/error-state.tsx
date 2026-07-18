import type { ReactNode } from "react";

import { Card } from "./card";

/** Always requires a reason and a next action — no generic "Something went wrong". */
export function ErrorState({ reason, action }: { reason: string; action: ReactNode }) {
  return (
    <Card className="flex flex-col items-start gap-3 border-[#8a1f1f]/20 py-6">
      <p className="text-sm text-(--color-heading)">{reason}</p>
      {action}
    </Card>
  );
}
