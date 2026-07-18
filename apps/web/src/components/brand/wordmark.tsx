import Image from "next/image";

import { cn } from "@/lib/cn";

export function Wordmark({ className }: { className?: string }) {
  return (
    <Image
      src="/tidyr-logo-transparent.svg"
      alt="TIDYR"
      width={120}
      height={32}
      priority
      className={cn("h-8 w-auto", className)}
    />
  );
}
