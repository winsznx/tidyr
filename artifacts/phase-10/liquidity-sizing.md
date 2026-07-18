# Phase 10 — DUST3/WMON Liquidity Sizing

All figures below are computed from real, live-read Monad mainnet state
(chain ID 143, read at block 88584368 / 88590779, 2026-07-18) and cross-
validated against an actual local-fork mint + swap
(`packages/contracts/script/Phase10RouteSimulation.s.sol`, run against
`anvil --fork-url https://rpc.monad.xyz`, never broadcast to real mainnet).
No figure here is fabricated or extrapolated without a stated model.

## Inputs

| Input                                     | Value                                          | Source                                                                                       |
| ----------------------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Deployer MON balance                      | 43.018882540000000000 MON                      | live `cast balance`                                                                          |
| Deployer DUST3 balance                    | 600,000 DUST3                                  | live `cast call balanceOf`                                                                   |
| DemoDistributor.CLAIM_AMOUNT              | 200 ether (200 DUST3 per claim, per token)     | `packages/contracts/src/tokens/DemoDistributor.sol:18`                                       |
| DemoDistributor remaining DUST3 inventory | 400,000 DUST3 (2,000 claims worth)             | live `cast call balanceOf(distributor)`                                                      |
| Chosen initial price                      | 1 DUST3 = 0.0001 WMON                          | reused unchanged from the already-proven fork simulation (same tick math, same sqrtPriceX96) |
| Tick range                                | `[-98160, -86160]` (0.3% fee tier, spacing 60) | reused unchanged, already proven valid on-chain via a real mint                              |
| WMON/USDC current price                   | ≈0.0215 USDC per WMON                          | derived from live `slot0()` on `0x659bD0BC4167BA25c62E05656F78043E7eD4a9da`                  |
| Uniswap V3 fee (both legs)                | 0.30%                                          | live-confirmed pool tier                                                                     |
| Current gas price                         | 102 gwei                                       | live `cast gas-price`                                                                        |

## Candidate modeling

For each candidate WMON deposit, DUST3 required is computed from the exact
liquidity math of the proven tick range (not a naive ratio): liquidity `L`
is derived from the real fork mint's actual token consumption
(`amount0Used`/`amount1Used`), then scaled linearly (`L` scales linearly
with deposit size for a fixed tick range and starting price).

Single-swap price impact and output are computed with the exact in-range
Uniswap V3 constant-sum formula (`Δ(1/√P) = Δx / L`, fee deducted from the
input first), not a linear approximation. The DUST3→WMON leg is modeled
(the pool doesn't exist yet); the WMON→USDC leg uses the live `QuoterV2`
quote for the modeled WMON output amount, so total output is
real-quote-anchored, not purely modeled, wherever a live quote could be
taken.

| WMON deposit            | DUST3 required (desired / ~used) | Tick range         | Position utilization | Output for one 200-DUST3 claim swap | Price impact (200 DUST3) | Reasonable sequential 200-DUST3 demo swaps before 5% cumulative drift | Deployer MON after WMON deposit | Deployer MON after WMON deposit + all Phase 10 gas (≈0.607 MON, §"Gas totals" below) | Risks                                                                                                           |
| ----------------------- | -------------------------------- | ------------------ | -------------------- | ----------------------------------- | ------------------------ | --------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| 2 MON                   | 20,000 / ~19,705                 | `[-98160, -86160]` | ~98.5%               | ≈0.019888 WMON → **$0.000428**      | 0.519%                   | 9                                                                     | 41.02 MON                       | 40.41 MON                                                                            | Sustains the fewest future demo sweeps before needing attention; still perfectly safe for the smoke test itself |
| 3 MON                   | 30,000 / ~29,557                 | same               | ~98.5%               | ≈0.019905 WMON → $0.000428          | 0.346%                   | 14                                                                    | 40.02 MON                       | 39.41 MON                                                                            | Modest headroom                                                                                                 |
| **5 MON (recommended)** | **50,000 / ~49,262**             | same               | ~98.5%               | **≈0.019919 WMON → $0.000428**      | **0.208%**               | **24**                                                                | **38.02 MON**                   | **37.41 MON**                                                                        | Best balance of demo longevity vs. capital committed                                                            |
| 8 MON                   | 80,000 / ~78,820                 | same               | ~98.5%               | ≈0.019927 WMON → $0.000428          | 0.130%                   | 39                                                                    | 35.02 MON                       | 34.41 MON                                                                            | More headroom than needed for a hackathon demo window                                                           |
| 10 MON                  | 100,000 / ~98,525                | same               | ~98.5%               | ≈0.019930 WMON → $0.000428          | 0.104%                   | 49                                                                    | 33.02 MON                       | 32.41 MON                                                                            | Commits ~23% of deployer MON balance for marginal extra runway over 5/8 MON                                     |

("Output for one 200-DUST3 claim swap" is effectively identical across
candidates because 200 DUST3 is such a small fraction of any of these pool
sizes — the meaningful differentiator between candidates is long-run demo
capacity, not single-swap quality.)

## Recommendation: 5 MON

**Rationale:**

1. **Single-swap quality is already excellent at every candidate size** — even
   the smallest (2 MON) gives 0.519% impact on a realistic 200-DUST3 demo
   sweep, far below any reasonable "excessive impact" threshold. Candidate
   size is not chosen for single-swap safety; it's chosen for demo longevity.
2. **5 MON sustains ~24 full sequential demo-claim sweeps** before cumulative
   price drift reaches 5% — comfortably enough for a hackathon/demo period
   without requiring re-seeding, while committing only ~11.6% of the
   deployer's current MON balance.
3. **8 or 10 MON extend runway further (39/49 swaps) but at diminishing
   relative value** — the brief explicitly asks for "a credible hackathon
   demo pool, not production-grade market liquidity," and 5 MON already
   clears that bar with room to spare.
4. **Reserve preservation**: after the WMON deposit and the full Phase 10 gas
   budget (pool creation, liquidity mint, smoke sweep, and the freeze
   sequence — see the confirmation packet), the deployer retains **37.41 MON
   (≈87% of the current balance)** — ample for future demos, gas, and
   contingencies.

## Gas totals (measured, not estimated, via the local-fork run at the

recommended 5 MON / 50,000 DUST3 / 200 DUST3 configuration)

| Step                                     | Gas used          | Source                                                              |
| ---------------------------------------- | ----------------- | ------------------------------------------------------------------- |
| `WMON.deposit()`                         | 44,942            | fork run (cold slot)                                                |
| `Factory.createPool(...)`                | 4,558,970         | fork run                                                            |
| `Pool.initialize(...)`                   | 70,386            | fork run                                                            |
| `DUST3.approve(NFPM, ...)`               | 45,981            | fork run                                                            |
| `WMON.approve(NFPM, ...)`                | 46,123            | fork run                                                            |
| `NFPM.mint(...)`                         | 582,511           | fork run                                                            |
| `DUST3.approve(Permit2, 200 ether)`      | 45,909            | fork run                                                            |
| `SweepExecutor.executeSweep(...)`        | 401,532           | fork run                                                            |
| **Subtotal (Phase 10 core sequence)**    | **5,796,354**     |                                                                     |
| `PancakeV2Adapter.freezeConfiguration()` | 46,336            | measured on a separate fork check                                   |
| `UniswapV3Adapter.freezeConfiguration()` | 46,348            | measured on a separate fork check                                   |
| `SweepExecutor.freezeConfiguration()`    | 57,333            | estimated (`cast estimate`) after both adapters frozen on that fork |
| **Grand total**                          | **5,946,371 gas** |                                                                     |
| **Grand total cost @ 102 gwei**          | **≈0.6065 MON**   |                                                                     |
