"use client";

import { useState } from "react";
import { isAddress } from "viem";

import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useTrackedTokensStore } from "@/store/tracked-tokens";

export function AddTokenDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const addToken = useTrackedTokensStore((s) => s.addToken);
  const [address, setAddress] = useState("");
  const [error, setError] = useState<string | null>(null);

  function handleSubmit() {
    const trimmed = address.trim();
    if (!isAddress(trimmed)) {
      setError("Enter a valid 0x-prefixed token address.");
      return;
    }
    const result = addToken(trimmed);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setAddress("");
    setError(null);
    onClose();
  }

  return (
    <Dialog open={open} onClose={onClose} title="Track a token">
      <div className="flex flex-col gap-4">
        <p className="text-sm text-(--color-body)">
          There is no wallet-wide token indexer in this build — add a token&apos;s contract address
          to check every wallet&apos;s balance for it.
        </p>
        <Input
          value={address}
          onChange={(e) => setAddress(e.target.value)}
          placeholder="0x…"
          aria-label="Token address"
        />
        {error ? <p className="text-sm text-[#8a1f1f]">{error}</p> : null}
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" size="md" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" size="md" onClick={handleSubmit}>
            Track token
          </Button>
        </div>
      </div>
    </Dialog>
  );
}
