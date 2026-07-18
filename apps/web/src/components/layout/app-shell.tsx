import type { ReactNode } from "react";
import Link from "next/link";

import { Wordmark } from "@/components/brand/wordmark";
import { StagingNotice } from "@/components/workspace/staging-notice";
import { cn } from "@/lib/cn";

const RAIL_LINKS = [
  { href: "/app", label: "Workspace" },
  { href: "/app/wallets", label: "Wallets" },
  { href: "/app/review", label: "Review" },
  { href: "/app/execute", label: "Execute" },
] as const;

/**
 * Desktop: compact left rail + main content. Mobile: top nav, single column
 * (the rail collapses rather than forcing a desktop layout onto small
 * screens, per frontend-integration-matrix.md's responsive requirements).
 * `footer` only renders when the caller has an active plan with actions —
 * callers pass `undefined` otherwise so no empty sticky bar ever appears.
 */
export function AppShell({
  children,
  headerRight,
  footer,
}: {
  children: ReactNode;
  headerRight?: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <div className="flex min-h-dvh flex-col bg-(--color-cloud) sm:flex-row">
      <header className="flex items-center justify-between border-b border-(--color-border) bg-(--color-canvas) px-4 py-3 sm:hidden">
        <Link href="/" aria-label="TIDYR home">
          <Wordmark />
        </Link>
        {headerRight}
      </header>

      <nav
        aria-label="Workspace navigation"
        className="hidden w-56 shrink-0 flex-col gap-1 border-r border-(--color-border) bg-(--color-canvas) p-4 sm:flex"
      >
        <Link href="/" className="mb-6" aria-label="TIDYR home">
          <Wordmark />
        </Link>
        {RAIL_LINKS.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className={cn(
              "rounded-(--radius-nav) px-3 py-2 text-sm font-medium text-(--color-body)",
              "hover:bg-(--color-cloud) hover:text-(--color-heading)",
            )}
          >
            {link.label}
          </Link>
        ))}
        <div className="mt-auto">{headerRight}</div>
      </nav>

      <div className="flex min-w-0 flex-1 flex-col">
        <StagingNotice />
        <main className="flex-1 p-4 sm:p-8">{children}</main>
        {footer ? (
          <div className="sticky bottom-0 border-t border-(--color-border) bg-(--color-canvas) p-4">
            {footer}
          </div>
        ) : null}
      </div>
    </div>
  );
}
