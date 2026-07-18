import { Card } from "@/components/ui/card";
import { Section } from "@/components/layout/section";

const PROBLEMS = [
  {
    title: "Fragmented wallets",
    body: "Dust and stray balances spread across dev, airdrop, and hackathon wallets with no single view.",
  },
  {
    title: "Repeated signing",
    body: "Cleaning up by hand means a fresh approval and a fresh transaction for every token, in every wallet.",
  },
  {
    title: "Unreadable calldata",
    body: "Most wallets show a hex blob at signing time — not what leaves, what arrives, or where it goes.",
  },
  {
    title: "Forgotten approvals",
    body: "Unlimited allowances granted months ago and never revoked stay live long after you stopped using them.",
  },
];

export function Problem() {
  return (
    <Section>
      <h2 className="font-display text-2xl font-medium text-(--color-heading)">
        Wallet cleanup is a manual, unreadable chore
      </h2>
      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        {PROBLEMS.map((p) => (
          <Card key={p.title}>
            <h3 className="font-display text-lg font-medium text-(--color-heading)">{p.title}</h3>
            <p className="mt-2 text-sm text-(--color-body)">{p.body}</p>
          </Card>
        ))}
      </div>
    </Section>
  );
}
