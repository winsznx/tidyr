import Link from "next/link";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Section } from "@/components/layout/section";

export function DemoCta() {
  return (
    <Section tone="cloud">
      <Card
        elevated
        className="flex flex-col items-start gap-4 sm:flex-row sm:items-center sm:justify-between"
      >
        <div>
          <h2 className="font-display text-xl font-medium text-(--color-heading)">
            Claim a demo bundle
          </h2>
          <p className="mt-2 max-w-lg text-sm text-(--color-body)">
            The demo claims real tokens from a real, deployed contract and involves real Monad
            mainnet transactions and gas — it is not a simulation.
          </p>
        </div>
        <Link href="/demo">
          <Button size="lg">Claim demo bundle</Button>
        </Link>
      </Card>
    </Section>
  );
}
