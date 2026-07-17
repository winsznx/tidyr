import canonicalize from "canonicalize";
import { keccak256, stringToBytes, type Hex } from "viem";

/**
 * Human-readable intent manifest shown to the user before signing (PRD §11 Layer 1,
 * corrected by §19.3 to be a distinct hash from `executionPlanHash`). This is
 * deliberately a much simpler, display-oriented shape than SweepPlan — it does not
 * carry routeData, adapters, or any ABI-level detail the user isn't meant to read.
 */
export interface SweepManifestAction {
  type: "SWAP" | "CONSOLIDATE" | "DISCARD" | "BURN";
  token: string;
  tokenSymbol: string;
  amount: string;
  amountWei: string;
  outputToken?: string;
  minimumOutput?: string;
  route?: string;
  slippageBps?: number;
}

export interface SweepManifest {
  wallet: string;
  recipient: string;
  outputToken: "MON" | "USDC";
  deadline: number;
  actions: SweepManifestAction[];
}

/**
 * RFC 8785 (JSON Canonicalization Scheme) canonical form of the manifest. Using the
 * `canonicalize` package (a JCS implementation) rather than a hand-rolled
 * `JSON.stringify` with sorted keys, since JCS also fixes number formatting and string
 * escaping edge cases that naive key-sorting does not address.
 */
export function canonicalizeManifest(manifest: SweepManifest): string {
  const canonical = canonicalize(manifest);
  if (canonical === undefined) {
    throw new Error("manifest contains a value RFC 8785 cannot canonicalize (e.g. undefined)");
  }
  return canonical;
}

/** `displayManifestHash` = keccak256(RFC 8785 canonical JSON). Distinct from `executionPlanHash`. */
export function hashDisplayManifest(manifest: SweepManifest): Hex {
  const canonical = canonicalizeManifest(manifest);
  return keccak256(stringToBytes(canonical));
}
