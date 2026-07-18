"use client";

import { useState } from "react";
import type { ReactNode } from "react";
import Link from "next/link";

import { Wordmark } from "@/components/brand/wordmark";
import { IconChevronLeft, IconChevronDown, IconWallet, IconCheck } from "@/components/ui/icon";
import { Tooltip } from "@/components/ui/tooltip";
import { cn } from "@/lib/cn";

const RAIL_LINKS = [
  { href: "/app", label: "Workspace", icon: IconChevronDown },
  { href: "/app/wallets", label: "Wallets", icon: IconWallet },
  { href: "/app/review", label: "Review", icon: IconCheck },
  { href: "/app/execute", label: "Execute", icon: IconChevronLeft },
] as const;

/** Desktop-only collapsible rail. Collapse state is session-local (not persisted). */
export function WorkspaceRail({ headerRight }: { headerRight?: ReactNode }) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <nav
      aria-label="Workspace navigation"
      className={cn(
        "hidden shrink-0 flex-col gap-1 border-r border-(--color-border) bg-(--color-canvas) p-4 transition-[width] sm:flex",
        collapsed ? "w-16" : "w-56",
      )}
    >
      <Link href="/" className="mb-6 flex items-center" aria-label="TIDYR home">
        {collapsed ? (
          <span className="inline-block h-6 w-6 rounded-[4px] bg-(--color-accent)" />
        ) : (
          <Wordmark />
        )}
      </Link>

      {RAIL_LINKS.map((link) => {
        const Icon = link.icon;
        const item = (
          <Link
            key={link.href}
            href={link.href}
            className={cn(
              "flex items-center gap-2 rounded-(--radius-nav) px-3 py-2 text-sm font-medium text-(--color-body)",
              "hover:bg-(--color-cloud) hover:text-(--color-heading)",
              collapsed && "justify-center px-0",
            )}
          >
            <Icon />
            {collapsed ? null : link.label}
          </Link>
        );
        return collapsed ? (
          <Tooltip key={link.href} label={link.label}>
            {item}
          </Tooltip>
        ) : (
          item
        );
      })}

      <div className="mt-auto flex flex-col gap-2">
        {headerRight}
        <Tooltip label={collapsed ? "Expand sidebar" : "Collapse sidebar"}>
          <button
            type="button"
            onClick={() => setCollapsed((c) => !c)}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            aria-pressed={collapsed}
            className={cn(
              "flex min-h-11 items-center gap-2 rounded-(--radius-nav) px-3 text-sm text-(--color-muted)",
              "hover:bg-(--color-cloud) hover:text-(--color-heading)",
              collapsed && "justify-center px-0",
            )}
          >
            <IconChevronLeft className={cn("transition-transform", collapsed && "rotate-180")} />
            {collapsed ? null : "Collapse"}
          </button>
        </Tooltip>
      </div>
    </nav>
  );
}
