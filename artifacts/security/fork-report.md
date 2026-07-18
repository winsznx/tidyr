# Fork Report — Phase 7 Task 7.9

## RPC availability

`https://rpc.monad.xyz` was reachable throughout this Phase 7 session - all fork
tests below ran against live Monad mainnet state via `vm.createSelectFork`. No
provider limitation was encountered; both the pre-existing
`PancakeV2Adapter.fork.t.sol` and this session's new
`MonadMainnetTopology.fork.t.sol` executed successfully.

**No transaction was ever broadcast.** Every check is a read-only `eth_getCode`/
`eth_call`/`staticcall` against a forked snapshot; `--broadcast` was never used, and
nothing in this repository's Foundry configuration enables it by default.

## `PancakeV2AdapterForkTest` (pre-existing, re-verified this session)

| Test                                                                                                                                 | Result |
| ------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| `test_realFactory_hasLiveWmonUsdcPair` — live WMON/USDC pair exists with non-zero reserves                                           | PASS   |
| `test_realSwap_wmonToUsdc_succeeds` — a real swap against the live pair produces the exact constant-product-formula-predicted output | PASS   |

## `MonadMainnetTopologyForkTest` (new this session, Task 7.9)

| Test                                                                                                                                                                    | Result |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| `test_chainIdIs143` — fork's `block.chainid == 143`                                                                                                                     | PASS   |
| `test_permit2HasCode` — canonical Permit2 address has live bytecode                                                                                                     | PASS   |
| `test_multicall3HasCode` — canonical Multicall3 address has live bytecode                                                                                               | PASS   |
| `test_multicall3Address_matchesSweepExecutorConstant` — the fork-verified Multicall3 address exactly matches `SweepExecutor.MULTICALL3_ADDRESS`                         | PASS   |
| `test_wmonHasCode` — WMON has live bytecode                                                                                                                             | PASS   |
| `test_usdcHasCode` — USDC has live bytecode                                                                                                                             | PASS   |
| `test_usdcDecimalsAndSymbol_matchExpectedCircleUSDC` — live `decimals()==6`, `symbol()=="USDC"`                                                                         | PASS   |
| `test_pancakeV2FactoryHasCode` — PancakeSwap V2 Factory has live bytecode                                                                                               | PASS   |
| `test_uniswapV3FactoryHasCode` — Uniswap V3 Factory has live bytecode                                                                                                   | PASS   |
| `test_uniswapSwapRouter02HasCode` — Uniswap SwapRouter02 has live bytecode                                                                                              | PASS   |
| `test_uniswapSwapRouter02_hasExactInputSelector` — the exact `exactInput` selector `UniswapV3Adapter.sol` calls (`0xb858183f`) is present in the live deployed bytecode | PASS   |

**11/11 passed.**

## What this closes relative to Task 7.9's checklist

| Requested check                             | Status                                                                                                                                                                                                                                                     |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Chain ID 143                                | Verified live                                                                                                                                                                                                                                              |
| Canonical Permit2 bytecode                  | Verified live (non-empty; full bytecode-hash comparison against a specific expected artifact was not performed - see residual note below)                                                                                                                  |
| Canonical Multicall3 bytecode               | Verified live, and cross-checked against `SweepExecutor`'s own constant                                                                                                                                                                                    |
| Canonical WMON bytecode                     | Verified live                                                                                                                                                                                                                                              |
| Canonical USDC bytecode                     | Verified live, plus `decimals`/`symbol` sanity check                                                                                                                                                                                                       |
| Pancake router and factory bytecode         | Factory verified live; PancakeSwap has no classic Router on Monad (documented, `docs/research/external-addresses.md` conflict C-1) - the existing `PancakeV2AdapterForkTest` already proves a real swap succeeds against the live factory/pair without one |
| Uniswap dependencies                        | Factory, SwapRouter02 (with selector-presence check) verified live                                                                                                                                                                                         |
| Router/factory relationships                | Proven functionally by `test_realSwap_wmonToUsdc_succeeds` (a real swap through the live factory-registered pair)                                                                                                                                          |
| Multicall3 cannot be selected as an adapter | Proven at the unit level (`test_constructor_rejectsMulticall3InEitherSlot`), and this fork report additionally confirms the constant being checked against is the _real, live_ Multicall3 address, not a placeholder                                       |
| No mainnet broadcast occurs                 | Confirmed - no `--broadcast` used anywhere in this session                                                                                                                                                                                                 |

## Residual note

"Canonical bytecode" checks above verify **non-empty code exists at the expected
address** (proving the address is genuinely live and not vacant), not a full
bytecode-hash comparison against a specific pinned reference artifact for each
external dependency (Permit2, Multicall3, the DEX factories/routers). A full
hash-pinned comparison for _TIDYR's own_ adapters is exactly what the strengthened
Phase 9 deployment gate (Task 7.14,
`docs/requirements-traceability.md`) now mandates - but pinning and verifying the
_external_ dependencies' (Permit2/Multicall3/DEX) exact bytecode hashes was outside
this session's scope and is better addressed by cross-referencing their own official,
independently-published deployment records at deploy time (Phase 9) rather than
hardcoding a bytecode hash here that could drift if any of these external protocols
redeploy or upgrade.

## Reproducing this report

```bash
cd packages/contracts
forge test --match-contract PancakeV2AdapterForkTest -vv
forge test --match-contract MonadMainnetTopologyForkTest -vv
```

Both require network access to `https://rpc.monad.xyz` and are excluded from the
default CI/offline test filtering (matching the existing fork-test convention).
