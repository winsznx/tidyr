import { defineChain } from "viem";

import { MAINNET_CHAIN_ID } from "./deployment";

/**
 * Monad mainnet chain definition. Chain ID and RPC verified in Phase 7's
 * MonadMainnetTopology.fork.t.sol and reused unchanged here.
 */
export const monadMainnet = defineChain({
  id: MAINNET_CHAIN_ID,
  name: "Monad",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.monad.xyz"] },
  },
  blockExplorers: {
    default: { name: "MonadScan", url: "https://monadscan.com" },
  },
});
