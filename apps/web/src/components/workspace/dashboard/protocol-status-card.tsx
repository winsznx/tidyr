import { Badge } from "@/components/ui/badge";
import { AddressText } from "@/components/ui/address";
import { IconShield } from "@/components/ui/icon";
import { MAINNET_DEPLOYMENT } from "@/lib/deployment";

/** Every value here is read directly from the generated deployment record. */
export function ProtocolStatusCard() {
  const executor = MAINNET_DEPLOYMENT.addresses.sweepExecutor;

  return (
    <div className="flex flex-col gap-4 rounded-(--radius-card) bg-(--color-terminal) p-5 text-white">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-base font-medium">Protocol status</h2>
        <IconShield className="text-(--color-accent-wash)" />
      </div>

      <div className="flex items-center justify-between text-sm">
        <span className="text-white/60">Chain</span>
        <span className="font-mono">Monad · {MAINNET_DEPLOYMENT.chainId}</span>
      </div>

      <div className="flex items-center justify-between text-sm">
        <span className="text-white/60">SweepExecutor</span>
        <AddressText
          value={executor}
          chars={4}
          className="text-white"
          explorerUrl={`https://monadscan.com/address/${executor}`}
        />
      </div>

      <div className="flex items-center justify-between text-sm">
        <span className="text-white/60">Configuration</span>
        {MAINNET_DEPLOYMENT.configurationFrozen ? (
          <Badge tone="accent">Frozen</Badge>
        ) : (
          <Badge tone="warning">Not frozen</Badge>
        )}
      </div>
    </div>
  );
}
