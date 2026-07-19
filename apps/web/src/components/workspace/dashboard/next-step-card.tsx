import Link from "next/link";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

export function NextStepCard({
  walletsCount,
  actionsCount,
}: {
  walletsCount: number;
  actionsCount: number;
}) {
  const step =
    walletsCount === 0
      ? {
          title: "Add your first wallet",
          body: "Connect a signer-capable wallet, or add a watch-only address, to start scanning for tokens.",
          href: "/app/wallets",
          cta: "Add wallet",
          disabled: false,
        }
      : actionsCount === 0
        ? {
            title: "Assign an action",
            body: "Sell, consolidate, discard, or burn a token in your wallet inventory to build a cleanup plan.",
            href: "/app/wallets",
            cta: "Go to wallets",
            disabled: false,
          }
        : {
            title: "Review your plan",
            body: "See the exact plan that will execute — live quotes, a verified calldata round-trip, and a live precondition check — before you sign anything.",
            href: "/app/review",
            cta: "Review plan",
            disabled: false,
          };

  return (
    <Card className="flex flex-col gap-4">
      <h2 className="font-display text-base font-medium text-(--color-heading)">Next step</h2>
      <div>
        <p className="text-sm font-medium text-(--color-heading)">{step.title}</p>
        <p className="mt-1 text-sm text-(--color-body)">{step.body}</p>
      </div>
      <Link href={step.href} className="self-start">
        <Button disabled={step.disabled}>{step.cta}</Button>
      </Link>
    </Card>
  );
}
