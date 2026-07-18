import { Card } from "@/components/ui/card";
import { Section } from "@/components/layout/section";

export function MonadSection() {
  return (
    <Section>
      <h2 className="font-display text-2xl font-medium text-(--color-heading)">Built for Monad</h2>
      <Card className="mt-6">
        <p className="text-sm text-(--color-body)">
          Each connected wallet is its own independent execution graph: its transactions run in
          strict nonce order, one after another, inside that wallet. Separate wallets can each have
          a transaction in flight on Monad at the same time — that is separate wallet graphs
          progressing concurrently, not one transaction executing several operations in parallel.
          TIDYR never claims a single <span className="font-mono">executeSweep</span> call performs
          parallel work; it claims that independent wallets don&apos;t have to wait on each other.
        </p>
      </Card>
    </Section>
  );
}
