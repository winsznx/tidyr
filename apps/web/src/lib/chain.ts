import { defineChain } from "viem";

import { MAINNET_CHAIN_ID } from "./deployment";

/**
 * Requests go through /api/rpc (a same-origin server route) rather than
 * directly to a provider URL. That route holds the real upstream RPC URL
 * server-side only (see app/api/rpc/route.ts) - this keeps a paid/private
 * RPC provider key (e.g. Alchemy) out of the browser bundle entirely,
 * because a NEXT_PUBLIC_ env var would otherwise bake it into client JS
 * where any visitor could read it via dev tools.
 */
const rpcUrl = "/api/rpc";

/**
 * Monad mainnet chain definition. Chain ID verified in Phase 7's
 * MonadMainnetTopology.fork.t.sol.
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
  contracts: {
    // Canonical Multicall3, verified deployed on Monad mainnet (real
    // bytecode confirmed live, and in Phase 7's MonadMainnetTopology fork
    // test). Without this, viem's publicClient.multicall() throws
    // "chain not configured for multicall3" - the exact cause of the
    // "Could not read token balances" error in useTokenInventory.
    multicall3: {
      address: "0xcA11bde05977b3631167028862bE2a173976CA11",
    },
  },
});
