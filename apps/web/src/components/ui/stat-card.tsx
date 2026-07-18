import type { ReactNode } from "react";

import { IconArrowUpRight } from "./icon";
import { cn } from "@/lib/cn";

export function StatCard({
  label,
  value,
  subLabel,
  tone = "default",
  href,
}: {
  label: string;
  value: ReactNode;
  subLabel?: ReactNode;
  tone?: "default" | "accent";
  href?: string;
}) {
  return (
    <div
      className={cn(
        "flex flex-col gap-4 rounded-(--radius-card) border p-5",
        tone === "accent"
          ? "border-transparent bg-(--color-dark-surface) text-white"
          : "border-(--color-border) bg-(--color-canvas)",
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <p
          className={cn(
            "text-sm font-medium",
            tone === "accent" ? "text-white/80" : "text-(--color-body)",
          )}
        >
          {label}
        </p>
        {href ? (
          <a
            href={href}
            className={cn(
              "flex h-7 w-7 shrink-0 items-center justify-center rounded-(--radius-pill) border",
              tone === "accent"
                ? "border-white/20 text-white hover:bg-white/10"
                : "border-(--color-border) text-(--color-muted) hover:bg-(--color-cloud)",
            )}
            aria-label={`Open ${label}`}
          >
            <IconArrowUpRight />
          </a>
        ) : null}
      </div>
      <p className="font-display text-3xl font-semibold">{value}</p>
      {subLabel ? (
        <p className={cn("text-xs", tone === "accent" ? "text-white/60" : "text-(--color-muted)")}>
          {subLabel}
        </p>
      ) : null}
    </div>
  );
}
