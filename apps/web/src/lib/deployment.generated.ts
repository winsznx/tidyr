// GENERATED FILE — do not hand-edit.
// Regenerate with `pnpm --filter @tidyr/web generate:deployment` after any
// change to deployments/mainnet.json. This is the single place a Monad
// mainnet contract address enters the frontend — components must import
// from here, never inline a literal 0x address.

export const MAINNET_CHAIN_ID = 143 as const;

export const MAINNET_DEPLOYMENT = {
  chainId: 143,
  addresses: {
    sweepExecutor: "0x7a844005998e896967A8b2BdA13c7826F387E9c3",
    pancakeV2Adapter: "0xBB86D6ef057F03Ca0bcaB9f87B61894977B0dBcb",
    uniswapV3Adapter: "0xE80d042fBDC03Da8262ED0669c75a394d2437D27",
    dust1: "0x196f8a0d53fC71ccbc672D81b55754fA5B9438A5",
    dust2: "0x4825cb1FCb1D3bB39bFbE15F477115937D46D960",
    dust3: "0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3",
    dust4: "0x645d6a93919362477Cf625Bd2Db9D802B27097E2",
    dust5: "0xB9b200e7b56B6180e87c7F927a040647D8529E2F",
    demoDistributor: "0x49552A355cCB700E8Ab18e392F1B05F0005C2d9E",
  },
  dependencies: {
    permit2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
    wmon: "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A",
    pancakeV2Factory: "0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E",
    uniswapV3SwapRouter02: "0xfE31F71C1b106EAc32F1A19239c9a9A72ddfb900",
  },
  outputTokensAllowed: [
    "MON_NATIVE_SENTINEL (0xEeee...EEeE)",
    "USDC (0x754704Bc059F8C67012fEd69BC8A327a5aafb603)",
  ],
  sourceVerification: {
    sweepExecutor: {
      verified: true,
      url: "https://monadscan.com/address/0x7a844005998e896967a8b2bda13c7826f387e9c3",
    },
    pancakeV2Adapter: {
      verified: true,
      url: "https://monadscan.com/address/0xbb86d6ef057f03ca0bcab9f87b61894977b0dbcb",
    },
    uniswapV3Adapter: {
      verified: true,
      url: "https://monadscan.com/address/0xe80d042fbdc03da8262ed0669c75a394d2437d27",
    },
    dust1: {
      verified: true,
      url: "https://monadscan.com/address/0x196f8a0d53fc71ccbc672d81b55754fa5b9438a5",
    },
    dust2: {
      verified: true,
      url: "https://monadscan.com/address/0x4825cb1fcb1d3bb39bfbe15f477115937d46d960",
    },
    dust3: {
      verified: true,
      url: "https://monadscan.com/address/0x1b7eb110bdc1d0b7f85046ec812be77958e8b3c3",
    },
    dust4: {
      verified: true,
      url: "https://monadscan.com/address/0x645d6a93919362477cf625bd2db9d802b27097e2",
    },
    dust5: {
      verified: true,
      url: "https://monadscan.com/address/0xb9b200e7b56b6180e87c7f927a040647d8529e2f",
    },
    demoDistributor: {
      verified: true,
      url: "https://monadscan.com/address/0x49552a355ccb700e8ab18e392f1b05f0005c2d9e",
    },
  },
} as const;
