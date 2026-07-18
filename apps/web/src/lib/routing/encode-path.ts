import { encodePacked } from "viem";
import type { Address, Hex } from "viem";

/**
 * Packs a Uniswap V3 multihop path exactly as the periphery/adapter expect:
 * `address(20) | uint24 fee(3) | address(20) | uint24 fee(3) | address(20) ...`
 * (see packages/contracts/src/adapters/UniswapV3Adapter.sol's `routeData` doc
 * comment). Only ever called with real, on-chain-verified hops — never
 * fabricates an intermediate token or fee tier.
 */
export function encodeUniswapV3Path(hops: { token: Address; fee?: number }[]): Hex {
  if (hops.length < 2) {
    throw new Error("a Uniswap V3 path needs at least two tokens");
  }

  const types: ("address" | "uint24")[] = [];
  const values: (Address | number)[] = [];

  for (let i = 0; i < hops.length; i++) {
    const hop = hops[i];
    if (!hop) throw new Error("invalid path hop");
    types.push("address");
    values.push(hop.token);

    if (i < hops.length - 1) {
      const fee = hop.fee;
      if (fee === undefined) {
        throw new Error(`missing fee tier for hop ${i} of a Uniswap V3 path`);
      }
      types.push("uint24");
      values.push(fee);
    }
  }

  return encodePacked(types, values);
}
