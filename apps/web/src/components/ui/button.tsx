import type { ButtonHTMLAttributes, ReactNode } from "react";

import { cn } from "@/lib/cn";

type ButtonVariant = "primary" | "dark" | "ghost";
type ButtonSize = "md" | "lg";

const variantClasses: Record<ButtonVariant, string> = {
  primary: "bg-(--color-accent) text-white hover:bg-[#4f3ff0]",
  dark: "bg-(--color-dark-surface) text-white hover:bg-(--color-terminal)",
  ghost:
    "border border-(--color-border) bg-transparent text-(--color-heading) hover:border-(--color-muted)",
};

const sizeClasses: Record<ButtonSize, string> = {
  md: "px-5 py-2.5 text-sm",
  lg: "px-6 py-3 text-base",
};

export function Button({
  variant = "primary",
  size = "md",
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
  children: ReactNode;
}) {
  return (
    <button
      className={cn(
        "inline-flex min-h-11 items-center justify-center gap-2 rounded-(--radius-button) font-medium",
        "transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--color-accent)",
        "disabled:cursor-not-allowed disabled:opacity-50",
        variantClasses[variant],
        sizeClasses[size],
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}
