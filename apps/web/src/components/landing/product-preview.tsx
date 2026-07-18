import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { AddressText } from "@/components/ui/address";
import { Section } from "@/components/layout/section";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";

const ILLUSTRATIVE_ROWS = [
  {
    wallet: "Dev Wallet 1",
    token: "DUST1",
    address: MAINNET_DEPLOYMENT.addresses.dust1,
    balance: "200.0",
    action: "Sell → MON",
  },
  {
    wallet: "Airdrop Wallet",
    token: "DUST3",
    address: MAINNET_DEPLOYMENT.addresses.dust3,
    balance: "1,000.0",
    action: "Sell → USDC",
  },
  {
    wallet: "Hackathon Wallet",
    token: "DUST5",
    address: MAINNET_DEPLOYMENT.addresses.dust5,
    balance: "50.0",
    action: "Consolidate",
  },
];

/**
 * Illustrative-only composition built from real UI primitives — never a
 * screenshot, and never wired to live data. Explicitly labeled so it can
 * never be mistaken for the real application data path.
 */
export function ProductPreview() {
  return (
    <Section id="product" tone="cloud">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-2xl font-medium text-(--color-heading)">
          One workspace, every wallet
        </h2>
        <Badge tone="neutral">Illustrative preview — not live data</Badge>
      </div>
      <Card elevated className="mt-6 overflow-hidden p-0">
        <div className="flex items-center gap-2 border-b border-(--color-border) bg-(--color-cloud) px-4 py-3">
          <span className="h-2.5 w-2.5 rounded-full bg-(--color-border)" />
          <span className="h-2.5 w-2.5 rounded-full bg-(--color-border)" />
          <span className="h-2.5 w-2.5 rounded-full bg-(--color-border)" />
          <span className="ml-2 font-mono text-xs text-(--color-muted)">tidyr.app/app/wallets</span>
        </div>
        <div className="divide-y divide-(--color-border)">
          {ILLUSTRATIVE_ROWS.map((row) => (
            <div
              key={row.address}
              className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
            >
              <div>
                <p className="text-sm font-medium text-(--color-heading)">
                  {row.token} <span className="text-(--color-muted)">· {row.wallet}</span>
                </p>
                <AddressText value={row.address} />
              </div>
              <div className="flex items-center gap-3">
                <span className="font-mono text-sm text-(--color-body)">{row.balance}</span>
                <Badge tone="accent">{row.action}</Badge>
              </div>
            </div>
          ))}
        </div>
      </Card>
    </Section>
  );
}
