import type { ReactNode } from "react";

import { Card } from "./card";

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <Card className="flex flex-col items-start gap-3 py-8">
      <h3 className="font-display text-lg font-medium text-(--color-heading)">{title}</h3>
      <p className="text-sm text-(--color-body)">{description}</p>
      {action}
    </Card>
  );
}
