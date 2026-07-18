import { defineChain } from "viem";

import { MAINNET_CHAIN_ID } from "./deployment";

const rpcUrl = process.env["NEXT_PUBLIC_MONAD_RPC_URL"] ?? "https://rpc.monad.xyz";

/**
 * Monad mainnet chain definition. Chain ID and RPC verified in Phase 7's
 * MonadMainnetTopology.fork.t.sol. RPC URL is overridable via
 * NEXT_PUBLIC_MONAD_RPC_URL (public-safe - never point this at a URL with an
 * embedded private credential; proxy through a server route instead).
 */
export const monadMainnet = defineChain({
  id: MAINNET_CHAIN_ID,
  name: "Monad",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: [rpcUrl] },
  },
  blockExplorers: {
    default: { name: "MonadScan", url: "https://monadscan.com" },
  },
});
