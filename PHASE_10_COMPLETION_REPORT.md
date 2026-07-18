# Phase 10 Completion Report — DUST3/WMON Route, Smoke Test, and Freeze

Branch: `protocol/phase-10-mainnet-smoke` (branched from `security/phase-7-verification` @ `0204180`)
Network: Monad mainnet, chain ID 143

## Summary

Phase 10 proved the DUST3→WMON→USDC multihop route end-to-end on real
Monad mainnet, using the deployed `SweepExecutor` and `UniswapV3Adapter`,
then permanently froze all three contracts' configuration. This is an
**engineering proof**, not a finished consumer product — the smoke
sweep's $0.000423 output is not a meaningful consumer-facing value (see
`artifacts/phase-10/economics-review.md`), and that question remains
explicitly deferred to future frontend/product work.

## Timeline

1. **Fork-only route proof** (`security/phase-7-verification`, commit `5c05cbe`) —
   `Phase10RouteSimulation.s.sol` and `Phase10RouteSmoke.fork.t.sol` proved the
   route, minAmountOut enforcement, and deadline enforcement on an
   `anvil`-forked snapshot of real mainnet state. No broadcast.
2. **Confirmation packet** (commits `db6d963`, `0204180`) — re-verified live
   state, modeled liquidity sizing (recommended 5 MON), and produced a full
   transaction-by-transaction packet. No broadcast.
3. **Economics review** (commit `0204180`) — found the smoke output ($0.000426)
   would render as $0.00 under a standard formatter; tightened
   `minAmountOut` from 10% to 2%; compared consumer-demo architectures and
   found none of them solved the display problem economically — deferred to
   frontend work.
4. **Real mainnet execution** (commits `08e34ec`, `b69338f`, this report) —
   8 transactions broadcast on `protocol/phase-10-mainnet-smoke`, each
   approved individually and independently verified by reading state back:

   | #   | Action                                | Tx hash                                                              | Block    | Gas used  |
   | --- | ------------------------------------- | -------------------------------------------------------------------- | -------- | --------- |
   | 1   | `WMON.deposit()` (5 MON)              | `0xf423a4b49b037b5b82defba04c7bf03648c5ccf3d81cecf4c6fcacd073e63490` | 88602315 | 65,000    |
   | 2   | `Factory.createPool(DUST3,WMON,3000)` | `0x229244ba22225c01114436194c099a60f128fb831e6a86df2438e2cf43246b12` | 88605154 | 5,400,000 |
   | 3   | `Pool.initialize(sqrtPriceX96)`       | `0xa4a3e20092589850a6968690506f1286f140790c9e6078073f25fffd44b09ebe` | 88606515 | 100,000   |
   | 4   | `DUST3.approve(NFPM, 50000 ether)`    | `0xc7393cd7f953d54840f92308324ba8d198ffa1e31531739ee4e40b52c31aec52` | 88606748 | 65,000    |
   | 5   | `WMON.approve(NFPM, 5 ether)`         | `0x6eee0ddc2a84b4bda26a60f8346b688cc3dd57d35722e397492e64e35e2e5a9c` | 88606911 | 65,000    |
   | 6   | `NFPM.mint(...)` → position #44076    | `0x7f7177abcc95c60a7b137a6d2cff9af043aec4226558fa6646a956ba319d3c8e` | 88607309 | 1,050,000 |
   | 7   | `DUST3.approve(Permit2, 200 ether)`   | `0x71fc6f57b952160377c0abde1b4b582935d270e435b645f78015624ad989baf0` | 88607767 | 65,000    |
   | 8   | `SweepExecutor.executeSweep(...)`     | `0xc2396b545c1b7fa9a068c42fbcebfaaf0f87203365cc4e87a6ca21301fbd4363` | 88608592 | 950,000   |

   A real bug was caught before broadcast: the originally-planned 99%
   `amount0Min` for the mint was tighter than the pool's actual achievable
   ~98.52% DUST3 utilization at the approved tick range — `cast estimate`
   correctly reverted with "Price slippage check." Fixed via a staticcall to
   the exact expected mint amounts before resubmitting with corrected
   minimums (49,200/4.999 ether).

5. **Freeze** (this report) — 3 transactions, in required order:

   | #   | Action                                   | Tx hash                                                              | Block    | Gas used |
   | --- | ---------------------------------------- | -------------------------------------------------------------------- | -------- | -------- |
   | F1  | `PancakeV2Adapter.freezeConfiguration()` | `0xa812372ff9cb9220fa3f4c9876b16c7c441370772aaab51f6a527c58f2281d27` | 88614826 | 75,000   |
   | F2  | `UniswapV3Adapter.freezeConfiguration()` | `0x3dd1e8aa9b12510aa6b1a82b6aa74099524d52db952fed99710c16868fe5efdc` | 88618447 | 75,000   |
   | F3  | `SweepExecutor.freezeConfiguration()`    | `0x68317c9292361bf8fbfc9441b9284f4e801e42447b4685e058924f34f0b6b6b6` | 88618636 | 125,000  |

## Final on-chain state (independently re-read after each transaction)

- `SweepExecutor.configurationFrozen() == true`
- `PancakeV2Adapter.configurationFrozen() == true`
- `UniswapV3Adapter.configurationFrozen() == true`
- `allowedOutputTokens`: MON_SENTINEL = `true`, USDC = `true`, WMON and all 5 DUST tokens = `false` — permanently locked
- Post-freeze mutation attempts (`registerOutputToken`, `allowIntermediateAsset`) confirmed reverting with `ConfigurationIsFrozen()`
- DUST3/WMON pool `0x78dDb77b9B9A821042A79AC77d7EF2726978eE83`: liquidity 1,915.02 (human units), position NFT #44076 owned by deployer
- `SweepExecutor` and `UniswapV3Adapter` retain zero DUST3/WMON/USDC
- Executor plan nonce: 1 (consumed exactly once). Permit2 nonce 0: consumed exactly once.

Full transaction-level detail, gas costs, and calldata are in
`deployments/mainnet.json` → `phase10`, `artifacts/phase-10/`.

## What Phase 10 does NOT establish

- **Not a consumer-facing demo economics decision.** 423 raw USDC
  ($0.000423) is real but not visually meaningful; see
  `artifacts/phase-10/economics-review.md` and `demo-options.md` for why pool
  size alone can't fix this and what the actual options are.
- **Not a backend.** No API, indexer, or pricing service was built.
- **Not F11–F20.** Frontend review/signing/execution/report surfaces remain
  paused pending those backend services (unrelated to this phase).
