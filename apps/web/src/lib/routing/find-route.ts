import type { Address, PublicClient } from "viem";

import { uniswapV3FactoryAbi, UNISWAP_V3_FEE_TIERS } from "@/lib/abi/factories";
import { EXTERNAL_ADDRESSES } from "@/lib/deployment";

export interface UniswapV3RouteHop {
  pool: Address;
  fee: (typeof UNISWAP_V3_FEE_TIERS)[number];
}

/**
 * Queries the real Uniswap V3 factory for a direct tokenIn/tokenOut pool
 * across all four fee tiers and returns the first one that exists on-chain.
 * Never fabricates a route — `null` means no pool was found at any tier.
 */
export async function findUniswapV3DirectRoute(
  client: PublicClient,
  tokenIn: Address,
  tokenOut: Address,
): Promise<UniswapV3RouteHop | null> {
  const results = await Promise.all(
    UNISWAP_V3_FEE_TIERS.map((fee) =>
      client.readContract({
        address: EXTERNAL_ADDRESSES.uniswapV3Factory,
        abi: uniswapV3FactoryAbi,
        functionName: "getPool",
        args: [tokenIn, tokenOut, fee],
      }),
    ),
  );

  for (let i = 0; i < UNISWAP_V3_FEE_TIERS.length; i++) {
    const pool = results[i];
    const fee = UNISWAP_V3_FEE_TIERS[i];
    if (pool && pool !== "0x0000000000000000000000000000000000000000" && fee !== undefined) {
      return { pool, fee };
    }
  }
  return null;
}
