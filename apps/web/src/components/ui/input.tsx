import type { InputHTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "min-h-11 w-full rounded-(--radius-input) border border-(--color-border) bg-(--color-canvas) px-3 py-2.5",
        "text-sm text-(--color-heading) placeholder:text-(--color-fog)",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--color-accent)",
        className,
      )}
      {...props}
    />
  );
}
