import { Card } from "@/components/ui/card";
import { Section } from "@/components/layout/section";

const STEPS = [
  {
    step: "1",
    title: "Scan",
    body: "Read balances directly from Monad — every connected wallet, every token.",
  },
  {
    step: "2",
    title: "Decide",
    body: "Assign sell, consolidate, discard, burn, or revoke to each asset.",
  },
  {
    step: "3",
    title: "Review",
    body: "See exactly what leaves, what arrives, and every permission granted.",
  },
  {
    step: "4",
    title: "Execute",
    body: "Sign once per wallet; each wallet's transactions run in its own graph.",
  },
  {
    step: "5",
    title: "Verify",
    body: "The final report is built from finalized on-chain evidence, not local state.",
  },
];

export function Workflow() {
  return (
    <Section tone="cloud">
      <h2 className="font-display text-2xl font-medium text-(--color-heading)">How it works</h2>
      <div className="mt-8 grid gap-4 sm:grid-cols-5">
        {STEPS.map((s) => (
          <Card key={s.step}>
            <span className="font-mono text-xs text-(--color-accent)">{s.step}</span>
            <h3 className="mt-1 font-display text-base font-medium text-(--color-heading)">
              {s.title}
            </h3>
            <p className="mt-2 text-sm text-(--color-body)">{s.body}</p>
          </Card>
        ))}
      </div>
    </Section>
  );
}
