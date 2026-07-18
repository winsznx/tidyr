"use client";

import { useState } from "react";
import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { Wordmark } from "@/components/brand/wordmark";
import { IconClose, IconMenu } from "@/components/ui/icon";
import { cn } from "@/lib/cn";
import { SECONDARY_LINKS, WORKSPACE_LINKS } from "./nav-links";

export function MobileNav({ walletSlot }: { walletSlot?: ReactNode }) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Open navigation"
        aria-expanded={open}
        className="flex min-h-11 min-w-11 items-center justify-center rounded-(--radius-button) text-(--color-heading) hover:bg-(--color-cloud)"
      >
        <IconMenu width={20} height={20} />
      </button>

      {open ? (
        <div className="fixed inset-0 z-50 flex sm:hidden">
          <button
            type="button"
            aria-label="Close navigation"
            onClick={() => setOpen(false)}
            className="absolute inset-0 bg-(--color-terminal)/50"
          />
          <div className="relative flex w-full max-w-xs flex-col gap-1 bg-(--color-canvas) p-4">
            <div className="mb-4 flex items-center justify-between">
              <Wordmark />
              <button
                type="button"
                onClick={() => setOpen(false)}
                aria-label="Close navigation"
                className="flex min-h-11 min-w-11 items-center justify-center rounded-(--radius-button) text-(--color-muted) hover:bg-(--color-cloud)"
              >
                <IconClose />
              </button>
            </div>

            <p className="px-3 pb-1 text-xs font-medium tracking-wide text-(--color-fog) uppercase">
              Menu
            </p>
            {WORKSPACE_LINKS.map((link) => {
              const Icon = link.icon;
              const active = pathname === link.href;
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  onClick={() => setOpen(false)}
                  className={cn(
                    "flex min-h-11 items-center gap-2 rounded-(--radius-nav) px-3 text-sm font-medium",
                    active
                      ? "bg-(--color-accent-pale) text-(--color-accent)"
                      : "text-(--color-body) hover:bg-(--color-cloud) hover:text-(--color-heading)",
                  )}
                >
                  <Icon />
                  {link.label}
                </Link>
              );
            })}

            <p className="px-3 pt-4 pb-1 text-xs font-medium tracking-wide text-(--color-fog) uppercase">
              General
            </p>
            {SECONDARY_LINKS.map((link) => {
              const Icon = link.icon;
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  onClick={() => setOpen(false)}
                  className="flex min-h-11 items-center gap-2 rounded-(--radius-nav) px-3 text-sm font-medium text-(--color-body) hover:bg-(--color-cloud) hover:text-(--color-heading)"
                >
                  <Icon />
                  {link.label}
                </Link>
              );
            })}

            <div className="mt-auto border-t border-(--color-border) pt-4">{walletSlot}</div>
          </div>
        </div>
      ) : null}
    </>
  );
}
