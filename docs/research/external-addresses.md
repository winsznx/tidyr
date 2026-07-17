# External Address Verification — Monad Mainnet (Chain ID 143)

Verification method for every row: (1) locate the address from a primary/official source,
(2) call `eth_getCode` against `https://rpc.monad.xyz`, (3) confirm non-empty bytecode,
(4) confirm `eth_chainId == 0x8f` (143) on the same endpoint, (5) where possible, cross-check
a second on-chain signal (embedded immutable, `symbol()`/`decimals()`, etc).

`eth_chainId` on `https://rpc.monad.xyz` returned `0x8f` (143) at verification time — confirmed live.

All verification below was performed 2026-07-17.

## Core chain

| Item            | Value                                              | Source                                                                                                                                  |
| --------------- | -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Chain ID        | `143` (`0x8f`)                                     | [Monad Network Information](https://docs.monad.xyz/developer-essentials/network-information), cross-checked via live `eth_chainId` call |
| Native currency | `MON`                                              | Monad Network Information                                                                                                               |
| HTTP RPC        | `https://rpc.monad.xyz` (+4 alternates)            | Monad Network Information                                                                                                               |
| WS RPC          | `wss://rpc.monad.xyz` (+4 alternates)              | Monad Network Information                                                                                                               |
| Block explorer  | `https://monadscan.com`, `https://monadvision.com` | Monad Network Information                                                                                                               |

## Verified contracts

| Contract                           | Address                                           | Bytecode non-empty | Cross-check                                                                                                                                                          | Source                                                                                                           |
| ---------------------------------- | ------------------------------------------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| WMON                               | `0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A`      | Yes                | Embedded as immutable inside PancakeSwap Universal Router and Uniswap Universal Router bytecode on Monad (both reference this address)                               | Monad Network Information                                                                                        |
| USDC (Circle canonical)            | `0x754704Bc059F8C67012fEd69BC8A327a5aafb603`      | Yes                | `eth_call` confirms `decimals()==6`, `symbol()=="USDC"`; bytecode matches an EIP-1967/Circle FiatTokenProxy selector layout (`upgradeTo`, `admin`, `implementation`) | [Circle — USDC on Monad](https://www.circle.com/multi-chain-usdc/monad)                                          |
| Multicall3                         | `0xcA11bde05977b3631167028862bE2a173976CA11`      | Yes                | Canonical deterministic-deployment address, identical across all EVM chains that have it deployed                                                                    | Monad Network Information                                                                                        |
| Permit2                            | `0x000000000022D473030F116dDEE9F6B43aC78BA3`      | Yes                | Canonical Uniswap deterministic-deployment address, identical to Ethereum mainnet/Arbitrum/Optimism/Polygon/Base                                                     | Monad Network Information; cross-checked against Uniswap's own Monad deployments page                            |
| Uniswap V3 Factory                 | `0x204FaCa1764B154221E35C0d20aBB3C525710498`      | Yes                | —                                                                                                                                                                    | [Uniswap — Monad Deployments](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-monad-deployments) |
| Uniswap NonfungiblePositionManager | `0x7197e214C0b767CFB76fB734Ab638e2C192F4e53`      | Yes                | —                                                                                                                                                                    | Uniswap Monad Deployments                                                                                        |
| Uniswap SwapRouter02               | `0xfE31F71C1B106EAC32F1a19239c9A9A72DDfB900`      | Yes                | —                                                                                                                                                                    | Uniswap Monad Deployments                                                                                        |
| Uniswap Universal Router           | `0x0D97dc33264BFC1c226207428A79b26757Fb9dC3`      | Yes                | Embedded WMON immutable matches `0x3bd359c1119da7da1d913d1c4d2b7c461115433a` (case-folded)                                                                           | Uniswap Monad Deployments                                                                                        |
| Uniswap QuoterV2                   | `0x661E93cCA42afaCb172121EF892830CA3B70f08D`      | Yes                | —                                                                                                                                                                    | Uniswap Monad Deployments                                                                                        |
| PancakeSwap V2 Factory             | `0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E`      | Yes                | Extracted from official `@pancakeswap/v2-sdk@1.2.1` npm package, `FACTORY_ADDRESS_MAP[ChainId.MONAD_MAINNET]`                                                        | PancakeSwap `v2-sdk` published package (not blog/gist)                                                           |
| PancakeSwap Universal Router       | `0x23682a588CF2601ACa977dF200938634c9F7d552`      | Yes                | Extracted from official `@pancakeswap/universal-router-sdk@1.5.3` npm package, `[ChainId.MONAD_MAINNET]` map                                                         | PancakeSwap `universal-router-sdk` published package                                                             |
| PancakeSwap chain feature flags    | `v2: true, v3: true` for `MONAD_MAINNET` (id 143) | —                  | Extracted from `@pancakeswap/chains@0.9.0` npm package                                                                                                               | PancakeSwap `chains` published package                                                                           |

## Verification commands used (reproducible)

```bash
curl -s -X POST https://rpc.monad.xyz -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
# => {"result":"0x8f"}   (143)

curl -s -X POST https://rpc.monad.xyz -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_getCode","params":["<address>","latest"]}'
# non-empty "0x..." result required; "0x" means no contract
```

## Critical finding: no classic PancakeSwap V2 Router on Monad

The PRD's `PancakeV2Adapter` design (Section 4) assumes a classic `PancakeRouter`
(`swapExactTokensForTokens`, `getAmountsOut`, `addLiquidity`) as exists on BSC. **No such
router contract is deployed by PancakeSwap on Monad.** PancakeSwap's own published SDKs
(`v2-sdk`, `universal-router-sdk`) only expose:

1. a bare `Factory` contract (for reading pairs / reserves, and for our own liquidity
   provisioning via direct `Factory.createPair` + pair-level `mint`), and
2. a `Universal Router` that internally routes V2 and V3 pools together, driven by
   `Commands`-encoded calldata (same architecture as Uniswap's Universal Router).

**Resolution (see `docs/requirements-traceability.md` conflict log, item C-1):** implement
`PancakeV2Adapter` to interact with V2 pairs directly (`IPancakePair.getReserves()` +
`IPancakePair.swap()` using the constant-product formula) rather than depending on a
nonexistent classic router. This preserves the exact product capability described in the
PRD (direct, auditable V2 path swaps) while matching what is actually deployed. Liquidity
provisioning scripts will call `Factory.createPair` + direct pair `mint`, or the Universal
Router's `V2_ADD_LIQUIDITY`-equivalent command if the deployed Universal Router version
supports it (to be confirmed against the router's live `Commands` support during Phase 8
preflight, immediately before any liquidity broadcast).

## Contract verification endpoint

`https://api.monadscan.com/api` (the naive Etherscan-V1-style guess) is live but
self-reports as deprecated: a direct request returns
`{"status":"0","message":"NOTOK","result":"You are using a deprecated V1 endpoint, switch to Etherscan API V2 using https://docs.etherscan.io/v2-migration"}`.
MonadScan is unified under Etherscan's multichain V2 API. Verified working endpoint shape:
`https://api.etherscan.io/v2/api?chainid=143`, authenticated with a standard Etherscan API
key (`ETHERSCAN_API_KEY`), not a separate MonadScan-specific key. `foundry.toml` and CI are
configured against this endpoint. Source: live `curl` response from `api.monadscan.com`,
cross-checked against [Etherscan API V2 Multichain](https://info.etherscan.com/etherscan-api-v2-multichain/).

## Not yet independently addressed by this document

- 0x Swap API: confirmed (via official 0x docs/blog) to support Monad mainnet chain 143,
  aggregating multiple sources including "PancakeSwap v2" and "PancakeSwap v3" — treated as
  indicative-only corroboration, not an address to verify on-chain (0x is an off-chain
  aggregator API, not a contract we call directly).
- Tenderly: confirmed via Tenderly's own docs to list Monad among supported networks for
  node RPC / simulation. Exact simulation API behavior will be validated with a live
  integration test in Phase 11/12, not assumed from search results alone.
- Moralis: confirmed via Moralis's own changelog ("New Chain: Monad EVM Live") and chain
  page to support Monad's Data API / wallet token balance endpoints.
