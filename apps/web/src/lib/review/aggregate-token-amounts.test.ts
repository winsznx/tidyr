import { describe, expect, it } from "vitest";
import type { SweepPlan } from "@tidyr/shared";

import { aggregateTokenAmounts } from "./aggregate-token-amounts";

const OWNER = "0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3";
const RECIPIENT = "0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3";
const OUTPUT_TOKEN = "0x754704Bc059F8C67012fEd69BC8A327a5aafb603";
const TOKEN_A = "0x0000000000000000000000000000000000000A";
const TOKEN_B = "0x0000000000000000000000000000000000000B";
const TOKEN_C = "0x0000000000000000000000000000000000000C";

function basePlan(overrides: Partial<SweepPlan>): SweepPlan {
  return {
    owner: OWNER,
    recipient: RECIPIENT,
    outputToken: OUTPUT_TOKEN,
    deadline: 1n,
    nonce: 0n,
    displayManifestHash: "0x00",
    swaps: [],
    transfers: [],
    discards: [],
    burns: [],
    ...overrides,
  };
}

describe("aggregateTokenAmounts", () => {
  it("preserves first-seen order across swaps, transfers, discards, burns", () => {
    // #given a plan touching four distinct tokens across all four action kinds
    const plan = basePlan({
      swaps: [
        { tokenIn: TOKEN_B, amountIn: 10n, adapterKind: 1, minAmountOut: 1n, routeData: "0x", allowFailure: false },
      ],
      transfers: [{ token: TOKEN_A, amount: 5n, to: RECIPIENT }],
      discards: [{ token: TOKEN_C, amount: 3n }],
      burns: [{ token: TOKEN_A, amount: 2n }],
    });

    // #when aggregated
    const result = aggregateTokenAmounts(plan);

    // #then order follows swaps -> transfers -> discards -> burns first-seen order,
    // and repeated tokens (TOKEN_A in transfers then burns) are summed in place
    expect(result).toEqual([
      { token: TOKEN_B, amount: 10n },
      { token: TOKEN_A, amount: 7n },
      { token: TOKEN_C, amount: 3n },
    ]);
  });

  it("returns an empty array for a plan with no actions", () => {
    // #given an empty plan
    const plan = basePlan({});

    // #when aggregated
    const result = aggregateTokenAmounts(plan);

    // #then no tokens are produced
    expect(result).toEqual([]);
  });

  it("sums repeated amounts for the same token within a single action list", () => {
    // #given two swaps consuming the same token
    const plan = basePlan({
      swaps: [
        { tokenIn: TOKEN_A, amountIn: 10n, adapterKind: 0, minAmountOut: 1n, routeData: "0x", allowFailure: false },
        { tokenIn: TOKEN_A, amountIn: 20n, adapterKind: 0, minAmountOut: 1n, routeData: "0x", allowFailure: false },
      ],
    });

    // #when aggregated
    const result = aggregateTokenAmounts(plan);

    // #then the amounts are summed into a single entry
    expect(result).toEqual([{ token: TOKEN_A, amount: 30n }]);
  });
});
