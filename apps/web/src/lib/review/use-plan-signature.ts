import { useCallback, useState } from "react";
import { useAccount, useSignTypedData } from "wagmi";
import type { Hex, SweepPlan } from "@tidyr/shared";

import { MAINNET_CHAIN_ID } from "@/lib/deployment";
import { buildPermit2TypedData } from "@/lib/review/permit2-typed-data";
import { useSignatureStore } from "@/store/signatures";

/**
 * An EOA `signTypedData` signature is exactly 65 bytes: 32-byte `r` + 32-byte
 * `s` + 1-byte `v`, hex-encoded as `0x` + 130 hex chars. Permit2's
 * `permitWitnessTransferFrom` expects precisely this shape for an EOA signer —
 * this app only supports connecting an EOA today (see add-wallet-dialog.tsx),
 * so a smart-contract-wallet signature shape is out of scope and, if it ever
 * appeared, should be rejected rather than silently accepted.
 */
function isEoaSignature(value: string): value is Hex {
  return /^0x[0-9a-fA-F]{130}$/.test(value);
}

export interface UsePlanSignatureResult {
  connectedAddress: `0x${string}` | undefined;
  ownerMismatch: boolean;
  isPending: boolean;
  error: string | null;
  requestSignature: () => Promise<void>;
}

/**
 * Requests a real Permit2 EIP-712 signature from the currently connected
 * wallet for one wallet's sweep plan. Refuses to sign if the connected
 * account does not match `plan.owner` — otherwise the resulting signature
 * would either revert on-chain (Permit2 checks the recovered signer against
 * `plan.owner`) or, worse, appear to succeed while authorizing the wrong
 * wallet's funds.
 */
export function usePlanSignature(
  plan: SweepPlan | null,
  executionPlanHash: Hex | null,
): UsePlanSignatureResult {
  const { address: connectedAddress } = useAccount();
  const { signTypedDataAsync } = useSignTypedData();
  const setSignature = useSignatureStore((s) => s.setSignature);
  const [isPending, setIsPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const ownerMismatch = Boolean(
    plan && connectedAddress && connectedAddress.toLowerCase() !== plan.owner.toLowerCase(),
  );

  const requestSignature = useCallback(async () => {
    if (!plan || !executionPlanHash) {
      setError("No plan available to sign.");
      return;
    }
    if (!connectedAddress) {
      setError("No wallet connected.");
      return;
    }
    if (connectedAddress.toLowerCase() !== plan.owner.toLowerCase()) {
      setError(
        `Connected wallet (${connectedAddress}) does not match this plan's wallet (${plan.owner}). Switch accounts in your wallet extension before signing.`,
      );
      return;
    }

    setIsPending(true);
    setError(null);
    try {
      const typedData = buildPermit2TypedData(plan, executionPlanHash, MAINNET_CHAIN_ID);
      const signature = await signTypedDataAsync(typedData);

      if (!isEoaSignature(signature)) {
        setError(
          "Received a signature in an unexpected format (not a 65-byte EOA signature). Refusing to queue it.",
        );
        return;
      }

      setSignature(plan.owner, {
        signature,
        executionPlanHash,
        signedAt: Date.now(),
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Signature request failed.");
    } finally {
      setIsPending(false);
    }
  }, [plan, executionPlanHash, connectedAddress, signTypedDataAsync, setSignature]);

  return { connectedAddress, ownerMismatch, isPending, error, requestSignature };
}
