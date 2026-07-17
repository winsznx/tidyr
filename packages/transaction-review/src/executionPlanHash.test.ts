import { test } from "node:test";
import assert from "node:assert/strict";
import { keccak256, stringToBytes } from "viem";
import { AdapterKind, type SweepPlan } from "@tidyr/shared";
import { hashExecutionPlan } from "./executionPlanHash.ts";

/**
 * Golden vector A — identical field values to
 * packages/contracts/test/SweepPlanLib.t.sol::_vectorA(). The expected hash is recorded
 * in test-vectors/golden-vectors.md and must match the Solidity side's
 * VECTOR_A_EXPECTED_HASH exactly. This is the cross-language proof required by PRD
 * Phase 2 acceptance criteria — Solidity and TypeScript must produce identical
 * `executionPlanHash` values for the same logical plan.
 */
const VECTOR_A_EXPECTED_HASH = "0xc277e8285240c296bf7df135856a7fad4a4e665f94c1f469e9cc6940f71e31d3";
const TEST_CHAIN_ID = 143n; // Monad mainnet
const TEST_EXECUTOR = "0x9999999999999999999999999999999999999999" as const;

function vectorA(): SweepPlan {
  return {
    owner: "0x1111111111111111111111111111111111111111",
    recipient: "0x2222222222222222222222222222222222222222",
    outputToken: "0x754704Bc059F8C67012fEd69BC8A327a5aafb603",
    deadline: 1_800_000_000n,
    nonce: 0n,
    displayManifestHash: keccak256(stringToBytes("display-manifest-vector-a")),
    swaps: [
      {
        tokenIn: "0x3333333333333333333333333333333333333333",
        amountIn: 200_000_000_000_000_000_000n,
        adapterKind: AdapterKind.PANCAKE_V2,
        minAmountOut: 100n,
        routeData: "0x1234",
        allowFailure: false,
      },
    ],
    transfers: [
      {
        token: "0x3333333333333333333333333333333333333333",
        amount: 50_000_000_000_000_000_000n,
        to: "0x2222222222222222222222222222222222222222",
      },
    ],
    discards: [],
    burns: [],
  };
}

test("vector A executionPlanHash matches the Solidity golden value", () => {
  const hash = hashExecutionPlan(vectorA(), TEST_CHAIN_ID, TEST_EXECUTOR);
  assert.equal(hash, VECTOR_A_EXPECTED_HASH);
});

test("executionPlanHash is deterministic", () => {
  assert.equal(
    hashExecutionPlan(vectorA(), TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(vectorA(), TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing amountIn changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.swaps[0]!.amountIn = 201_000_000_000_000_000_000n;
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing recipient changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.recipient = "0x5555555555555555555555555555555555555555";
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing outputToken changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.outputToken = "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A"; // WMON instead of USDC
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing deadline changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.deadline = a.deadline + 1n;
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing nonce changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.nonce = a.nonce + 1n;
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing chainId changes the hash", () => {
  const plan = vectorA();
  assert.notEqual(
    hashExecutionPlan(plan, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(plan, 1n, TEST_EXECUTOR),
  );
});

test("changing executor address changes the hash", () => {
  const plan = vectorA();
  assert.notEqual(
    hashExecutionPlan(plan, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(plan, TEST_CHAIN_ID, "0x8888888888888888888888888888888888888888"),
  );
});

// Codex addendum audit finding CA-04: this and the three tests below close a real gap -
// owner/adapter/routeData/minAmountOut sensitivity was verified once by an ephemeral,
// non-retained mutation run, but never committed as regression coverage.

test("changing owner changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.owner = "0x6666666666666666666666666666666666666666";
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing a swap's adapterKind changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.swaps[0]!.adapterKind = AdapterKind.UNISWAP_V3;
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing a swap's routeData changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.swaps[0]!.routeData = "0x9999";
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("changing a swap's minAmountOut changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.swaps[0]!.minAmountOut = a.swaps[0]!.minAmountOut + 1n;
  assert.notEqual(
    hashExecutionPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("reordering swap actions changes the hash", () => {
  const a = vectorA();
  const secondSwap = {
    tokenIn: a.swaps[0]!.tokenIn,
    amountIn: 10_000_000_000_000_000_000n,
    adapterKind: a.swaps[0]!.adapterKind,
    minAmountOut: 1n,
    routeData: "0x56" as const,
    allowFailure: true,
  };
  const forward: SweepPlan = { ...a, swaps: [a.swaps[0]!, secondSwap] };
  const reversed: SweepPlan = { ...a, swaps: [secondSwap, a.swaps[0]!] };
  assert.notEqual(
    hashExecutionPlan(forward, TEST_CHAIN_ID, TEST_EXECUTOR),
    hashExecutionPlan(reversed, TEST_CHAIN_ID, TEST_EXECUTOR),
  );
});

test("executionPlanHash differs from displayManifestHash for the same plan", () => {
  const plan = vectorA();
  assert.notEqual(hashExecutionPlan(plan, TEST_CHAIN_ID, TEST_EXECUTOR), plan.displayManifestHash);
});
