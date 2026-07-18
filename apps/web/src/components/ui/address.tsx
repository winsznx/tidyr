"use client";

import { useState } from "react";

import { cn } from "@/lib/cn";
import { truncateAddress } from "@/lib/format";

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
  className?: string;
}) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    await navigator.clipboard.writeText(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 font-mono text-sm text-(--color-body)",
        className,
      )}
    >
      <span title={value}>{truncateAddress(value, chars)}</span>
      <button
        type="button"
        onClick={handleCopy}
        aria-label={copied ? "Copied" : `Copy ${value}`}
        className="min-h-6 min-w-6 rounded text-(--color-fog) hover:text-(--color-accent) focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--color-accent)"
      >
        {copied ? "✓" : "⧉"}
      </button>
      {explorerUrl ? (
        <a
          href={explorerUrl}
          target="_blank"
          rel="noreferrer noopener"
          className="text-(--color-fog) hover:text-(--color-accent)"
          aria-label="View on explorer"
        >
          ↗
        </a>
      ) : null}
    </span>
  );
}
