import { MAINNET_CHAIN_ID, MAINNET_DEPLOYMENT } from "./deployment.generated";

/**
 * External dependency addresses that are not part of TIDYR's own deployment
 * record (deployments/mainnet.json only records contracts TIDYR deployed).
 * Sourced from docs/research/external-addresses.md — each entry there is
 * independently verified on-chain, not taken from a single unverified source.
 */
export const EXTERNAL_ADDRESSES = {
  usdc: "0x754704Bc059F8C67012fEd69BC8A327a5aafb603",
  uniswapV3Factory: "0x204FAca1764B154221e35c0d20aBb3c525710498",
  uniswapV3QuoterV2: "0x661E93cCA42afaCb172121EF892830CA3B70f08D",
  uniswapV3SwapRouter02: "0xfE31F71C1b106EAc32F1A19239c9a9A72ddfb900",
  pancakeV2Factory: "0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E",
  permit2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
  wmon: "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A",
} as const;

export { MAINNET_CHAIN_ID, MAINNET_DEPLOYMENT };

export const DEMO_TOKENS = [
  { key: "dust1", address: MAINNET_DEPLOYMENT.addresses.dust1 },
  { key: "dust2", address: MAINNET_DEPLOYMENT.addresses.dust2 },
  { key: "dust3", address: MAINNET_DEPLOYMENT.addresses.dust3 },
  { key: "dust4", address: MAINNET_DEPLOYMENT.addresses.dust4 },
  { key: "dust5", address: MAINNET_DEPLOYMENT.addresses.dust5 },
] as const;
