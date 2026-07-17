import { test } from "node:test";
import assert from "node:assert/strict";
import {
  AdapterKind,
  MAX_ACTIONS,
  MON_NATIVE_SENTINEL,
  sweepPlanSchema,
  totalActions,
  walletTransactionSchema,
  type SweepPlan,
} from "./actions.ts";

const basePlan: SweepPlan = {
  owner: "0x1111111111111111111111111111111111111111",
  recipient: "0x2222222222222222222222222222222222222222",
  outputToken: "0x754704Bc059F8C67012fEd69BC8A327a5aafb603",
  deadline: 1_800_000_000n,
  nonce: 0n,
  displayManifestHash: `0x${"ab".repeat(32)}`,
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

test("MAX_ACTIONS matches SweepPlanLib.MAX_ACTIONS", () => {
  assert.equal(MAX_ACTIONS, 50);
});

test("MON_NATIVE_SENTINEL is the standard cross-protocol sentinel address", () => {
  assert.equal(MON_NATIVE_SENTINEL, "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
});

test("sweepPlanSchema accepts a well-formed plan with no revocations field", () => {
  const parsed = sweepPlanSchema.parse(basePlan);
  assert.equal(totalActions(parsed), 2);
  assert.ok(!("revocations" in parsed));
});

test("sweepPlanSchema rejects a malformed address", () => {
  const bad = { ...basePlan, owner: "not-an-address" };
  assert.throws(() => sweepPlanSchema.parse(bad));
});

test("walletTransactionSchema accepts revoke as a standalone transaction, not a plan action", () => {
  const revoke = walletTransactionSchema.parse({
    type: "revoke",
    token: "0x3333333333333333333333333333333333333333",
    spender: "0x4444444444444444444444444444444444444444",
  });
  assert.equal(revoke.type, "revoke");
});
