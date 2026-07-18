import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { AddressText } from "@/components/ui/address";
import { Section } from "@/components/layout/section";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";

const EXPLORER_BASE = "https://monadscan.com/address/";

const CONTRACT_ROWS: Array<{
  label: string;
  address: string;
  verificationKey: keyof typeof MAINNET_DEPLOYMENT.sourceVerification;
}> = [
  {
    label: "SweepExecutor",
    address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
    verificationKey: "sweepExecutor",
  },
  {
    label: "PancakeV2Adapter",
    address: MAINNET_DEPLOYMENT.addresses.pancakeV2Adapter,
    verificationKey: "pancakeV2Adapter",
  },
  {
    label: "UniswapV3Adapter",
    address: MAINNET_DEPLOYMENT.addresses.uniswapV3Adapter,
    verificationKey: "uniswapV3Adapter",
  },
  {
    label: "DemoDistributor",
    address: MAINNET_DEPLOYMENT.addresses.demoDistributor,
    verificationKey: "demoDistributor",
  },
];

export function ContractsTable() {
  return (
    <Section>
      <h2 className="font-display text-2xl font-medium text-(--color-heading)">
        Live mainnet contracts
      </h2>
      <p className="mt-2 text-sm text-(--color-body)">
        Chain ID {MAINNET_DEPLOYMENT.chainId} · Monad mainnet
      </p>
      <Card className="mt-6 divide-y divide-(--color-border) p-0">
        {CONTRACT_ROWS.map((row) => {
          const verification = MAINNET_DEPLOYMENT.sourceVerification[row.verificationKey];
          return (
            <div key={row.address} className="flex items-center justify-between gap-3 px-4 py-3">
              <span className="text-sm font-medium text-(--color-heading)">{row.label}</span>
              <div className="flex items-center gap-3">
                {verification?.verified ? <Badge tone="success">Verified</Badge> : null}
                <AddressText value={row.address} explorerUrl={`${EXPLORER_BASE}${row.address}`} />
              </div>
            </div>
          );
        })}
      </Card>
    </Section>
  );
}
