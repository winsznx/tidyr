import { test } from "node:test";
import assert from "node:assert/strict";
import { keccak256, stringToBytes } from "viem";
import type { SweepPlan } from "@tidyr/shared";
import { hashExecutionPlan } from "./executionPlanHash.ts";

/**
 * Golden vector A — identical field values to
 * packages/contracts/test/SweepPlanLib.t.sol::_vectorA(). The expected hash is recorded
 * in test-vectors/golden-vectors.md and must match the Solidity side's
 * VECTOR_A_EXPECTED_HASH exactly. This is the cross-language proof required by PRD
 * Phase 2 acceptance criteria — Solidity and TypeScript must produce identical
 * `executionPlanHash` values for the same logical plan.
 */
const VECTOR_A_EXPECTED_HASH = "0x184bb27ccf4286fdd2f69be2433e59715e5ce345badd2ba2f5688bd2368f1de5";

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
        adapter: "0x4444444444444444444444444444444444444444",
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
  const hash = hashExecutionPlan(vectorA());
  assert.equal(hash, VECTOR_A_EXPECTED_HASH);
});

test("executionPlanHash is deterministic", () => {
  assert.equal(hashExecutionPlan(vectorA()), hashExecutionPlan(vectorA()));
});

test("changing amountIn changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.swaps[0]!.amountIn = 201_000_000_000_000_000_000n;
  assert.notEqual(hashExecutionPlan(a), hashExecutionPlan(b));
});

test("changing recipient changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.recipient = "0x5555555555555555555555555555555555555555";
  assert.notEqual(hashExecutionPlan(a), hashExecutionPlan(b));
});

test("changing outputToken changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.outputToken = "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A"; // WMON instead of USDC
  assert.notEqual(hashExecutionPlan(a), hashExecutionPlan(b));
});

test("changing deadline changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.deadline = a.deadline + 1n;
  assert.notEqual(hashExecutionPlan(a), hashExecutionPlan(b));
});

test("changing nonce changes the hash", () => {
  const a = vectorA();
  const b = vectorA();
  b.nonce = a.nonce + 1n;
  assert.notEqual(hashExecutionPlan(a), hashExecutionPlan(b));
});

test("reordering swap actions changes the hash", () => {
  const a = vectorA();
  const secondSwap = {
    tokenIn: a.swaps[0]!.tokenIn,
    amountIn: 10_000_000_000_000_000_000n,
    adapter: a.swaps[0]!.adapter,
    minAmountOut: 1n,
    routeData: "0x56" as const,
    allowFailure: true,
  };
  const forward: SweepPlan = { ...a, swaps: [a.swaps[0]!, secondSwap] };
  const reversed: SweepPlan = { ...a, swaps: [secondSwap, a.swaps[0]!] };
  assert.notEqual(hashExecutionPlan(forward), hashExecutionPlan(reversed));
});

test("executionPlanHash differs from displayManifestHash for the same plan", () => {
  const plan = vectorA();
  assert.notEqual(hashExecutionPlan(plan), plan.displayManifestHash);
});
