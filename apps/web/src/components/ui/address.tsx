"use client";

import { cn } from "@/lib/cn";
import { truncateAddress } from "@/lib/format";
import { IconCopy, IconExternalLink } from "./icon";
import { Tooltip } from "./tooltip";
import { useToast } from "./toast";

/**
 * Renders an address/hash in IBM Plex Mono with a copy control. The full
 * value is always present in the DOM (via `title` and the copy payload) even
 * though the visible text is truncated — addresses must remain copyable, per
 * frontend-integration-matrix.md's accessibility requirements.
 */
export function AddressText({
  value,
  chars = 4,
  explorerUrl,
  className,
}: {
  value: string;
  chars?: number;
  explorerUrl?: string;
  className?: string | undefined;
}) {
  const showToast = useToast();

  async function handleCopy() {
    await navigator.clipboard.writeText(value);
    showToast("Copied to clipboard");
  }

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 font-mono text-sm text-(--color-body)",
        className,
      )}
    >
      <span title={value}>{truncateAddress(value, chars)}</span>
      <Tooltip label="Copy address">
        <button
          type="button"
          onClick={handleCopy}
          aria-label={`Copy ${value}`}
          className="flex min-h-6 min-w-6 items-center justify-center rounded text-(--color-fog) hover:text-(--color-accent) focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--color-accent)"
        >
          <IconCopy />
        </button>
      </Tooltip>
      {explorerUrl ? (
        <Tooltip label="View on explorer">
          <a
            href={explorerUrl}
            target="_blank"
            rel="noreferrer noopener"
            className="flex items-center text-(--color-fog) hover:text-(--color-accent)"
            aria-label="View on explorer"
          >
            <IconExternalLink />
          </a>
        </Tooltip>
      ) : null}
    </span>
  );
}
