import type { ReactNode } from "react";

import { cn } from "@/lib/cn";
import { Container } from "./container";

/** Alternating white/cloud section bands, per design.md's "Layout" band pattern. */
export function Section({
  children,
  tone = "canvas",
  className,
  id,
}: {
  children: ReactNode;
  tone?: "canvas" | "cloud";
  className?: string | undefined;
  id?: string;
}) {
  return (
    <section
      id={id}
      className={cn(
        tone === "cloud" ? "bg-(--color-cloud)" : "bg-(--color-canvas)",
        "py-16 sm:py-20",
      )}
    >
      <Container className={className}>{children}</Container>
    </section>
  );
}
