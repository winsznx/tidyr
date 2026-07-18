import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";
import { zeroAddress } from "viem";

import { pancakeV2FactoryAbi } from "@/lib/abi/factories";
import { sweepExecutorAbi } from "@/lib/abi/sweep-executor";
import { EXTERNAL_ADDRESSES, MAINNET_DEPLOYMENT } from "@/lib/deployment";
import { findUniswapV3DirectRoute } from "@/lib/routing/find-route";

export interface SellCapability {
  monOutputAllowed: boolean;
  usdcOutputAllowed: boolean;
  hasRouteToMon: boolean;
  routeVia: "uniswap-v3" | "pancake-v2" | null;
}

const MON_SENTINEL = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE" as const;

/**
 * Reads the real, current on-chain state needed to decide whether "Sell" can
 * be offered for a token at all: is the output token actually allowed on
 * SweepExecutor right now, and does a route to WMON actually exist. Never
 * infers availability from a token merely existing on Monad.
 */
export function useSellCapability(tokenIn: Address | undefined) {
  const publicClient = usePublicClient();

  return useQuery({
    queryKey: ["sell-capability", tokenIn],
    enabled: Boolean(tokenIn && publicClient),
    queryFn: async (): Promise<SellCapability> => {
      if (!tokenIn || !publicClient) throw new Error("not ready");

      const [monAllowed, usdcAllowed, uniswapRoute, pancakePair] = await Promise.all([
        publicClient.readContract({
          address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
          abi: sweepExecutorAbi,
          functionName: "allowedOutputTokens",
          args: [MON_SENTINEL],
        }),
        publicClient.readContract({
          address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
          abi: sweepExecutorAbi,
          functionName: "allowedOutputTokens",
          args: [EXTERNAL_ADDRESSES.usdc],
        }),
        findUniswapV3DirectRoute(publicClient, tokenIn, EXTERNAL_ADDRESSES.wmon),
        publicClient.readContract({
          address: EXTERNAL_ADDRESSES.pancakeV2Factory,
          abi: pancakeV2FactoryAbi,
          functionName: "getPair",
          args: [tokenIn, EXTERNAL_ADDRESSES.wmon],
        }),
      ]);

      const hasPancakeRoute = pancakePair !== zeroAddress;

      return {
        monOutputAllowed: monAllowed,
        usdcOutputAllowed: usdcAllowed,
        hasRouteToMon: Boolean(uniswapRoute) || hasPancakeRoute,
        routeVia: uniswapRoute ? "uniswap-v3" : hasPancakeRoute ? "pancake-v2" : null,
      };
    },
    staleTime: 15_000,
  });
}
