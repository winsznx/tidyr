import Link from "next/link";

import { PixelField } from "@/components/brand/pixel-field";
import { Button } from "@/components/ui/button";
import { Container } from "@/components/layout/container";

export function Hero() {
  return (
    <div className="bg-(--color-canvas) py-16 sm:py-24">
      <Container className="grid items-center gap-10 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <h1 className="font-display text-4xl font-semibold tracking-tight text-(--color-heading) sm:text-5xl lg:text-6xl">
            Every Monad wallet.
            <br />
            Cleaned in one verified session.
          </h1>
          <p className="mt-6 max-w-xl text-base text-(--color-body) sm:text-lg">
            Scan every wallet, choose what stays, sell or consolidate what does not, and understand
            every transaction before you sign.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link href="/app">
              <Button size="lg">Open workspace</Button>
            </Link>
            <Link href="/demo">
              <Button size="lg" variant="ghost">
                Claim demo tokens
              </Button>
            </Link>
          </div>
        </div>
        <div className="hidden justify-end sm:flex">
          <PixelField className="h-32 w-32 sm:h-40 sm:w-40" />
        </div>
      </Container>
    </div>
  );
}
