import { cn } from "@/lib/cn";

/** Clean typographic wordmark — placeholder until a final SVG mark is supplied. */
export function Wordmark({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        "font-display text-lg font-semibold tracking-tight text-(--color-heading)",
        className,
      )}
    >
      TIDYR
    </span>
  );
}
