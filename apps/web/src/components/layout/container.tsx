import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

export function Container({
  children,
  className,
}: {
  children: ReactNode;
  className?: string | undefined;
}) {
  return (
    <div className={cn("mx-auto w-full max-w-(--container-content) px-6", className)}>
      {children}
    </div>
  );
}
