import { Card } from "@/components/ui/card";
import { Section } from "@/components/layout/section";

const POINTS = [
  {
    title: "Exact Permit2 permissions",
    body: "Every signature authorizes Permit2 to pull exactly the amount of exactly the token in the plan — never an unlimited allowance, never a different token.",
  },
  {
    title: "Closed adapter model",
    body: "SweepExecutor only ever calls two constructor-fixed adapters (PancakeV2, UniswapV3). There is no registry and no way to name an arbitrary adapter address in a plan.",
  },
  {
    title: "Simulation and calldata verification",
    body: "Before you sign, the encoded transaction is decoded and compared field-by-field against what you approved, and simulated against live chain state.",
  },
  {
    title: "Finalized on-chain reports",
    body: "The cleanup report is rebuilt from indexed chain events after execution — never from an optimistic local success flag.",
  },
];

export function SecuritySection() {
  return (
    <Section id="security" tone="cloud">
      <h2 className="font-display text-2xl font-medium text-(--color-heading)">Security model</h2>
      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        {POINTS.map((p) => (
          <Card key={p.title}>
            <h3 className="font-display text-base font-medium text-(--color-heading)">{p.title}</h3>
            <p className="mt-2 text-sm text-(--color-body)">{p.body}</p>
          </Card>
        ))}
      </div>
    </Section>
  );
}
