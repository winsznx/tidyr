"use client";

import { useEffect, useRef } from "react";
import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

/**
 * Built on the native <dialog> element: free focus trapping, ESC-to-close,
 * and a11y semantics without a modal-management dependency.
 */
export function Dialog({
  open,
  onClose,
  title,
  children,
  className,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  className?: string | undefined;
}) {
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    if (open && !node.open) node.showModal();
    if (!open && node.open) node.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onCancel={onClose}
      aria-labelledby="dialog-title"
      className={cn(
        "w-full max-w-md rounded-(--radius-card) border border-(--color-border) p-0 shadow-(--shadow-subtle-3) backdrop:bg-(--color-terminal)/40",
        className,
      )}
    >
      <div className="flex items-center justify-between border-b border-(--color-border) px-4 py-3">
        <h2 id="dialog-title" className="font-display text-base font-medium text-(--color-heading)">
          {title}
        </h2>
        <button
          type="button"
          onClick={onClose}
          aria-label="Close dialog"
          className="min-h-11 min-w-11 rounded-(--radius-button) text-(--color-muted) hover:bg-(--color-cloud)"
        >
          ×
        </button>
      </div>
      <div className="p-4">{children}</div>
    </dialog>
  );
}
