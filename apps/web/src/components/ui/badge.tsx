import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

type BadgeTone = "neutral" | "accent" | "success" | "warning" | "danger";

const toneClasses: Record<BadgeTone, string> = {
  neutral: "bg-(--color-cloud) text-(--color-heading)",
  accent: "bg-(--color-accent-pale) text-(--color-accent)",
  success: "bg-(--color-cloud) text-(--color-heading) ring-1 ring-inset ring-(--color-border)",
  warning: "bg-[#fdf3d9] text-[#7a5b00]",
  danger: "bg-[#fbe1e1] text-[#8a1f1f]",
};

export function Badge({ children, tone = "neutral" }: { children: ReactNode; tone?: BadgeTone }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-(--radius-pill) px-2.5 py-1 text-xs font-medium",
        toneClasses[tone],
      )}
    >
      {children}
    </span>
  );
}
