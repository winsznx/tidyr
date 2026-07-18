import type { ReactNode } from "react";
import Link from "next/link";

import { Wordmark } from "@/components/brand/wordmark";
import { StagingNotice } from "@/components/workspace/staging-notice";
import { MobileNav } from "./mobile-nav";
import { Topbar } from "./topbar";
import { WorkspaceRail } from "./workspace-rail";

/**
 * Desktop: compact left rail + top bar + main content. Mobile: a top bar
 * with a hamburger-triggered slide-over nav, single column (the rail
 * collapses rather than forcing a desktop layout onto small screens, per
 * frontend-integration-matrix.md's responsive requirements).
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
        <MobileNav walletSlot={headerRight} />
        <Link href="/" aria-label="TIDYR home">
          <Wordmark />
        </Link>
        <span className="min-w-11" aria-hidden="true" />
      </header>

      <WorkspaceRail />

      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar right={headerRight} />
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
