# Phase 10.1 — Consumer-Demo Architecture Options

No transaction was broadcast in producing this comparison. All figures are
either live mainnet reads (this session, block 88592731) or exact Uniswap V3
in-range math (constant-sum formula, fees applied), explicitly labeled.

## The core finding, stated first

**Pool depth (more MON) does not change how much a 200-DUST3 claim is worth
— only the initial price ratio does.** This is proven below with real
numbers (§"Option C"): a pool 20× deeper than the recommended size produces
an output within 0.2% of the smaller pool's — because a 200-DUST3 trade is
such a tiny fraction of either pool that depth only affects slippage, not
the fundamental exchange rate. Any option that claims to fix the "$0.00
display" problem through pool size alone is not economically coherent.

## Option A — current DUST3/WMON multihop pool (5 MON / 50,000 DUST3)

| Field                                             | Value                                                                                                                                                                                                                                |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Initial ratio                                     | 1 DUST3 = 0.0001 WMON (1 MON = 10,000 DUST3)                                                                                                                                                                                         |
| Output per 200-DUST3 claim                        | 0.01991926 WMON → **$0.000426** (fresh live quote)                                                                                                                                                                                   |
| Displayed in dollars                              | **$0.00** under any standard 2-decimal USD formatter                                                                                                                                                                                 |
| Single-claim price impact                         | 0.208% (AMM curve only); 0.721% total degradation incl. both pools' fees                                                                                                                                                             |
| Cumulative impact after 5 / 10 / 20 claims        | ≈1.04% / ≈2.08% / ≈4.16% (linear-ish at this small scale; see `economics-review.md` for the 5%-threshold model, ~24 claims)                                                                                                          |
| Number of credible demos before re-seeding needed | ~24 (to 5% cumulative drift)                                                                                                                                                                                                         |
| Capital required                                  | 5 MON (already verified affordable — deployer has 43.02 MON)                                                                                                                                                                         |
| Execution complexity                              | Already fully proven — same 8-transaction sequence from the accepted confirmation packet, no new work                                                                                                                                |
| Effect on existing UniswapV3Adapter flow          | None — this is exactly what was already validated on-fork                                                                                                                                                                            |
| Multihop or direct?                               | **Multihop** — DUST3→WMON→USDC, single `exactInput` call, two pools, one adapter call. This is the only option of the four that demonstrates the multihop capability that was the actual subject of the earlier Phase 10 fork proof. |

## Option B — direct DUST3/USDC pool

A single-hop pool, bypassing WMON entirely. Chosen target rate for this
comparison: **$0.0005 per DUST3** (so 200 DUST3 ≈ $0.10) — an explicitly
arbitrary, clearly-labeled "demo economics" rate, not derived from any real
market reference (DUST3 has no real market).

| USDC funding | DUST3 required | Output per 200-DUST3 claim | Displayed in $ | Single-claim impact | Cumulative impact (5/10/20 claims)                  |
| ------------ | -------------- | -------------------------- | -------------- | ------------------- | --------------------------------------------------- |
| 1 USDC       | 1,975          | $0.097174                  | **$0.10**      | 5.068%              | n/a — too shallow for repeated use                  |
| 5 USDC       | 9,877          | $0.099184                  | **$0.10**      | 1.035%              | ~5.2% / ~10.3% / ~20.3% (too shallow for 20 claims) |
| 10 USDC      | 19,755         | $0.099441                  | **$0.10**      | 0.519%              | ~2.6% / ~5.2% / ~10.3%                              |
| 20 USDC      | 39,510         | $0.099571                  | **$0.10**      | 0.260%              | ~1.3% / ~2.6% / ~5.1% (≈20 claims to 5%)            |

**Capital required — the deployer does NOT currently hold any USDC (confirmed
live, balance = 0).** The only way to acquire it on-chain is swapping
MON→WMON→USDC through the existing real pool, at the fresh live price of
**0.021454739 USDC per WMON**, i.e. **≈46.61 MON per 1 USDC**:

| USDC needed | MON cost to acquire it (live price) | Feasible given 43.02 MON balance?            |
| ----------- | ----------------------------------- | -------------------------------------------- |
| 1 USDC      | ≈46.61 MON                          | **No** — exceeds the entire deployer balance |
| 5 USDC      | ≈233.05 MON                         | No                                           |
| 10 USDC     | ≈466.10 MON                         | No                                           |
| 20 USDC     | ≈932.20 MON                         | No                                           |

**Option B is not capital-feasible today via an on-chain swap at any of the
four funding levels.** It would require USDC sourced externally (a faucet,
bridge, or off-chain transfer) — not something this review can execute or
assume access to.

| Execution complexity | New pool, new fee-tier check (confirmed free at all 4 tiers for DUST3/USDC — not yet checked before this review), new tick-range computation, one new mint |
| Effect on existing UniswapV3Adapter flow | None required — a single-hop path (`DUST3 \| fee \| USDC`) is fully supported by `UniswapV3Adapter`'s existing `_validatePath` (no intermediate-asset check needed for a 1-hop path) |
| Multihop or direct? | **Direct only** — does not exercise or re-prove the multihop capability. If used exclusively, the multihop route would need a separate demonstration (Option A, kept as the engineering pool) to remain proven in a consumer-visible way. |

## Option C — a larger DUST3/WMON pool, same ratio

| WMON deposit     | DUST3 required (~98.5% util.) | Output per 200-DUST3 claim | Impact | Feasible?                                                                                                           |
| ---------------- | ----------------------------- | -------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------- |
| 5 MON (baseline) | ~49,250                       | $0.000427                  | 0.208% | Yes                                                                                                                 |
| 20 MON           | ~197,000                      | $0.000428                  | 0.052% | Yes (43.02 MON balance covers it, leaving little reserve)                                                           |
| 50 MON           | ~492,500                      | $0.000428                  | 0.021% | **No — exceeds deployer's 43.02 MON balance**                                                                       |
| 100 MON          | ~985,000                      | $0.000428                  | 0.010% | **No — exceeds deployer's 43.02 MON balance, and exceeds the deployer's 600,000 DUST3 holdings margin for comfort** |

**Output per claim is identical (to the cent... to the hundredth of a cent)
regardless of pool size** — $0.000427 at 5 MON vs. $0.000428 at 100 MON, a
difference of nothing. Additional MON only buys lower price impact on larger
trades and more sustainable-claim headroom, not a bigger number.

| Execution complexity | Same as Option A, larger `amount0Desired`/`amount1Desired` only |
| Effect on existing UniswapV3Adapter flow | None — same route |
| Multihop or direct? | Multihop, same as Option A |

## Frontend-only fix (not one of the four requested options, but the

economically coherent one given the findings above)

Instead of changing any pool economics, fix the **display**: never round a
nonzero value to `$0.00`. Show additional precision for sub-cent amounts
(e.g. `$0.000426` or a `<$0.01` badge), consistent with DUST3's actual,
intentional near-worthlessness as a "dust" token. This requires no capital,
no new pool, and no redeployment — it is F10 frontend work (not yet built;
`apps/web` has no USD formatter today).

## Summary table

|                          | Option A (5 MON, current) | Option B (direct USDC)                    | Option C (bigger WMON pool)    | Frontend fix         |
| ------------------------ | ------------------------- | ----------------------------------------- | ------------------------------ | -------------------- |
| Fixes $0.00 display      | No                        | Yes (by design choice, not economics)     | **No**                         | Yes                  |
| Capital required         | 5 MON (have it)           | 1–932 MON to acquire USDC (don't have it) | up to 100 MON (don't have it)  | $0                   |
| Preserves multihop proof | Yes                       | No (needs Option A kept alongside)        | Yes                            | Yes (no pool change) |
| Feasible today           | **Yes**                   | **No**                                    | Partially (only up to ~20 MON) | **Yes**              |
