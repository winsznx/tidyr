import { AddressText } from "@/components/ui/address";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Container } from "@/components/layout/container";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";

export default function DemoPage() {
  return (
    <Container className="py-16">
      <h1 className="font-display text-2xl font-medium text-(--color-heading)">Demo</h1>
      <Card className="mt-6">
        <p className="text-sm text-(--color-body)">
          The demo claims real tokens from the deployed DemoDistributor contract on Monad mainnet
          and involves real transactions and gas — it is not a simulation.
        </p>
        <p className="mt-3">
          <AddressText
            value={MAINNET_DEPLOYMENT.addresses.demoDistributor}
            explorerUrl={`https://monadscan.com/address/${MAINNET_DEPLOYMENT.addresses.demoDistributor}`}
          />
        </p>
      </Card>
      <div className="mt-6">
        <EmptyState
          title="Guided claim flow ships in F15"
          description="Connect → claim → scan → sell/burn/consolidate → review → execute → report. Built against the same real contract shown above, once the workspace flow (F5–F14) exists to guide it."
        />
      </div>
    </Container>
  );
}
