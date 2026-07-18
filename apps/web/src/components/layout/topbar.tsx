"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { ReactNode } from "react";

import { IconSearch } from "@/components/ui/icon";

/**
 * Real, functional search — not decorative. Submitting navigates to the
 * wallet workspace with the query pre-filled (the only surface today with
 * something to search: known + manually-tracked tokens). No notification
 * bell or mail icon is shown here — TIDYR has no notification system yet,
 * and an icon that does nothing would misrepresent capability.
 */
export function Topbar({ right }: { right?: ReactNode }) {
  const router = useRouter();
  const [query, setQuery] = useState("");

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!query.trim()) return;
    router.push(`/app/wallets?q=${encodeURIComponent(query.trim())}`);
  }

  return (
    <div className="hidden items-center justify-between gap-4 border-b border-(--color-border) bg-(--color-canvas) px-6 py-3 sm:flex">
      <form onSubmit={handleSubmit} className="w-full max-w-sm">
        <label className="relative flex items-center">
          <IconSearch className="pointer-events-none absolute left-3 text-(--color-fog)" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            type="search"
            placeholder="Search wallets or tokens"
            aria-label="Search wallets or tokens"
            className="min-h-11 w-full rounded-(--radius-input) border border-(--color-border) bg-(--color-cloud) py-2.5 pr-3 pl-9 text-sm text-(--color-heading) placeholder:text-(--color-fog) focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--color-accent)"
          />
        </label>
      </form>
      <div className="flex shrink-0 items-center gap-3">{right}</div>
    </div>
  );
}
