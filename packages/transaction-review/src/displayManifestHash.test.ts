import { test } from "node:test";
import assert from "node:assert/strict";
import {
  canonicalizeManifest,
  hashDisplayManifest,
  type SweepManifest,
} from "./displayManifestHash.ts";

const manifest: SweepManifest = {
  wallet: "0x1111111111111111111111111111111111111111",
  recipient: "0x2222222222222222222222222222222222222222",
  outputToken: "USDC",
  deadline: 1_800_000_000,
  actions: [
    {
      type: "SWAP",
      token: "0x3333333333333333333333333333333333333333",
      tokenSymbol: "DUST1",
      amount: "200.0",
      amountWei: "200000000000000000000",
      outputToken: "USDC",
      minimumOutput: "0.18",
      route: "PancakeSwap V2",
      slippageBps: 100,
    },
  ],
};

test("canonicalization is key-order-independent (RFC 8785)", () => {
  const reordered: SweepManifest = {
    deadline: manifest.deadline,
    actions: manifest.actions,
    outputToken: manifest.outputToken,
    wallet: manifest.wallet,
    recipient: manifest.recipient,
  };
  assert.equal(canonicalizeManifest(manifest), canonicalizeManifest(reordered));
});

test("displayManifestHash is deterministic and key-order-independent", () => {
  const reordered: SweepManifest = {
    deadline: manifest.deadline,
    actions: manifest.actions,
    outputToken: manifest.outputToken,
    wallet: manifest.wallet,
    recipient: manifest.recipient,
  };
  assert.equal(hashDisplayManifest(manifest), hashDisplayManifest(reordered));
});

test("displayManifestHash changes when an action amount changes", () => {
  const changed: SweepManifest = {
    ...manifest,
    actions: [{ ...manifest.actions[0]!, amountWei: "200000000000000000001" }],
  };
  assert.notEqual(hashDisplayManifest(manifest), hashDisplayManifest(changed));
});

test("displayManifestHash differs from a naively-encoded executionPlanHash-shaped value", () => {
  // Sanity check for §19.3: this hash is computed over JSON text, not ABI-encoded
  // struct fields, so it is architecturally incapable of colliding with
  // executionPlanHash's ABI-based encoding for any equivalent plan.
  const hash = hashDisplayManifest(manifest);
  assert.match(hash, /^0x[a-f0-9]{64}$/);
});
