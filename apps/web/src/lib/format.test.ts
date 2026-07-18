import { describe, expect, it } from "vitest";

import { truncateAddress, truncateHash } from "./format";

describe("truncateAddress", () => {
  it("truncates a full address to the default 4 chars each side", () => {
    // #given a full 20-byte address
    const address = "0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3";
    // #when truncated with the default char count
    const result = truncateAddress(address);
    // #then it keeps the 0x prefix + 4 chars, an ellipsis, and the last 4 chars
    expect(result).toBe("0x1B7E…b3c3");
  });

  it("leaves a short value unchanged", () => {
    // #given a value shorter than the truncation threshold
    const address = "0x1234";
    // #when truncated
    const result = truncateAddress(address);
    // #then it is returned as-is
    expect(result).toBe(address);
  });
});

describe("truncateHash", () => {
  it("truncates a full tx hash to the default 6 chars each side", () => {
    // #given a full 32-byte transaction hash
    const hash = "0xc2396b545c1b7fa9a068c42fbcebfaaf0f87203365cc4e87a6ca21301fbd4363";
    // #when truncated with the default char count
    const result = truncateHash(hash);
    // #then it keeps the 0x prefix + 6 chars, an ellipsis, and the last 6 chars
    expect(result).toBe("0xc2396b…bd4363");
  });
});
