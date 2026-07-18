"use client";

import { useState } from "react";
import { isAddress } from "viem";
import { useAccount } from "wagmi";

import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useWalletStore } from "@/store/wallets";

export function AddWalletDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { address: connectedAddress } = useAccount();
  const addWallet = useWalletStore((s) => s.addWallet);

  const [mode, setMode] = useState<"connected" | "watch-only">("connected");
  const [manualAddress, setManualAddress] = useState("");
  const [label, setLabel] = useState("");
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setManualAddress("");
    setLabel("");
    setError(null);
    setMode("connected");
  }

  function handleSubmit() {
    const address = mode === "connected" ? connectedAddress : manualAddress.trim();

    if (!address || !isAddress(address)) {
      setError("Enter a valid 0x-prefixed address.");
      return;
    }

    const result = addWallet({
      address,
      label: label.trim() || `Wallet ${address.slice(0, 6)}`,
      watchOnly: mode === "watch-only",
    });

    if (!result.ok) {
      setError(result.error);
      return;
    }

    reset();
    onClose();
  }

  return (
    <Dialog open={open} onClose={onClose} title="Add wallet">
      <div className="flex flex-col gap-4">
        <div className="flex gap-2">
          <Button
            type="button"
            size="md"
            variant={mode === "connected" ? "primary" : "ghost"}
            onClick={() => setMode("connected")}
            disabled={!connectedAddress}
          >
            Use connected wallet
          </Button>
          <Button
            type="button"
            size="md"
            variant={mode === "watch-only" ? "primary" : "ghost"}
            onClick={() => setMode("watch-only")}
          >
            Watch-only address
          </Button>
        </div>

        {mode === "connected" ? (
          <p className="text-sm text-(--color-body)">
            {connectedAddress
              ? `Adding ${connectedAddress} as a signer-capable wallet. It will need to authorize its own actions separately from any other connected wallet.`
              : "No wallet is currently connected. Connect one first, or add a watch-only address instead."}
          </p>
        ) : (
          <Input
            value={manualAddress}
            onChange={(e) => setManualAddress(e.target.value)}
            placeholder="0x…"
            aria-label="Watch-only address"
          />
        )}

        <Input
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder="Label (optional) — e.g. Dev Wallet 1"
          aria-label="Wallet label"
        />

        {error ? <p className="text-sm text-[#8a1f1f]">{error}</p> : null}

        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" size="md" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" size="md" onClick={handleSubmit}>
            Add wallet
          </Button>
        </div>
      </div>
    </Dialog>
  );
}
