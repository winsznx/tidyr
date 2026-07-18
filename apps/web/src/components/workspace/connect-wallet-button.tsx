"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { AddressText } from "@/components/ui/address";
import { MAINNET_CHAIN_ID } from "@/lib/deployment";

/**
 * The one place a signer-capable wallet is connected. Only ever shows real
 * connector capability — no "one click connects everything" claim (a single
 * injected connector authorizes one account at a time; each additional
 * signer wallet must connect and authorize its own actions separately).
 */
export function ConnectWalletButton() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  if (!isConnected || !address) {
    const injected = connectors.find((c) => c.id === "injected") ?? connectors[0];
    return (
      <Button
        size="md"
        disabled={!injected || isPending}
        onClick={() => injected && connect({ connector: injected })}
      >
        {isPending ? "Connecting…" : "Connect wallet"}
      </Button>
    );
  }

  if (chainId !== MAINNET_CHAIN_ID) {
    return (
      <div className="flex items-center gap-2">
        <Badge tone="warning">Wrong network</Badge>
        <Button
          size="md"
          variant="ghost"
          disabled={isSwitching}
          onClick={() => switchChain({ chainId: MAINNET_CHAIN_ID })}
        >
          {isSwitching ? "Switching…" : "Switch to Monad"}
        </Button>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <AddressText value={address} />
      <Button size="md" variant="ghost" onClick={() => disconnect()}>
        Disconnect
      </Button>
    </div>
  );
}
