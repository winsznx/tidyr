import { cn } from "@/lib/cn";

/**
 * Placeholder slot for a final protocol mark/favicon SVG (see
 * docs/frontend-asset-requests.md). Renders a simple violet square so layout
 * never shifts once the real asset is dropped in.
 */
export function ProtocolMarkSlot({ size = 24, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cn("inline-block rounded-[4px] bg-(--color-accent)", className)}
      style={{ width: size, height: size }}
      aria-hidden="true"
    />
  );
}
