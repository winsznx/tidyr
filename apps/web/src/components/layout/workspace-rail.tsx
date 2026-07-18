"use client";

import { useState } from "react";
import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { Wordmark } from "@/components/brand/wordmark";
import { IconChevronLeft } from "@/components/ui/icon";
import { Tooltip } from "@/components/ui/tooltip";
import { cn } from "@/lib/cn";
import { SECONDARY_LINKS, WORKSPACE_LINKS } from "./nav-links";

function NavItem({
  href,
  label,
  Icon,
  active,
  collapsed,
}: {
  href: string;
  label: string;
  Icon: (props: { className?: string }) => ReactNode;
  active: boolean;
  collapsed: boolean;
}) {
  const item = (
    <Link
      href={href}
      aria-current={active ? "page" : undefined}
      className={cn(
        "relative flex items-center gap-2 rounded-(--radius-nav) px-3 py-2 text-sm font-medium transition-colors",
        active
          ? "bg-(--color-accent-pale) text-(--color-accent)"
          : "text-(--color-body) hover:bg-(--color-cloud) hover:text-(--color-heading)",
        collapsed && "justify-center px-0",
      )}
    >
      {active ? (
        <span className="absolute -left-4 h-5 w-1 rounded-full bg-(--color-accent)" />
      ) : null}
      <Icon />
      {collapsed ? null : label}
    </Link>
  );
  return collapsed ? <Tooltip label={label}>{item}</Tooltip> : item;
}

/** Desktop-only collapsible rail. Collapse state is session-local (not persisted). */
export function WorkspaceRail() {
  const [collapsed, setCollapsed] = useState(false);
  const pathname = usePathname();

  return (
    <nav
      aria-label="Workspace navigation"
      className={cn(
        "hidden shrink-0 flex-col gap-1 border-r border-(--color-border) bg-(--color-canvas) p-4 pl-5 transition-[width] sm:flex",
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

      {!collapsed ? (
        <p className="px-3 pb-1 text-xs font-medium tracking-wide text-(--color-fog) uppercase">
          Menu
        </p>
      ) : null}
      {WORKSPACE_LINKS.map((link) => (
        <NavItem
          key={link.href}
          href={link.href}
          label={link.label}
          Icon={link.icon}
          active={pathname === link.href}
          collapsed={collapsed}
        />
      ))}

      {!collapsed ? (
        <p className="px-3 pt-4 pb-1 text-xs font-medium tracking-wide text-(--color-fog) uppercase">
          General
        </p>
      ) : (
        <div className="my-2 border-t border-(--color-border)" />
      )}
      {SECONDARY_LINKS.map((link) => (
        <NavItem
          key={link.href}
          href={link.href}
          label={link.label}
          Icon={link.icon}
          active={pathname === link.href}
          collapsed={collapsed}
        />
      ))}

      <div className="mt-auto flex flex-col gap-2">
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
