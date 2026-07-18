import type { HTMLAttributes, ReactNode } from "react";

import { cn } from "@/lib/cn";

/** Default card: white surface, 12px radius, 1px border, no shadow (design.md §"Do"). */
export function Card({
  children,
  elevated = false,
  className,
  ...props
}: HTMLAttributes<HTMLDivElement> & { children: ReactNode; elevated?: boolean }) {
  return (
    <div
      className={cn(
        "rounded-(--radius-card) bg-(--color-canvas) p-4",
        elevated ? "shadow-(--shadow-subtle-3)" : "border border-(--color-border)",
        className,
      )}
      {...props}
    >
      {children}
    </div>
  );
}
