# TIDYR Pricing and Oracle Model

Status: **design intent for Phase 11 — not yet implemented.** No `PriceService`, quote
integration, or oracle client exists in this repository yet. This document records the
binding design so the distinction below is never collapsed later.

## Two different prices, two different sources

### 1. Swap execution price — from an executable DEX quote, never an oracle

The amount a sweep actually delivers is determined by a live, executable quote from
PancakeSwap V2, Uniswap V3, or 0x — the same quote `PancakeV2Adapter`/`UniswapV3Adapter`
already enforce on-chain via `minAmountOut` and balance-delta accounting (Phase 4/5).
An oracle must never substitute for `minAmountOut`: most tokens TIDYR will ever
encounter (arbitrary wallet holdings) will never have an oracle feed, and the contract's
safety already comes from exact amounts, a verified route, an enforced minimum output,
and a short deadline — not from a price reference.

### 2. USD display value — from an executable quote combined with an oracle reference

For UI/report display only:

```text
executable token value (USD)
  = quoted MON or USDC output (from the same executable quote used for execution)
    x
    MON/USD or USDC/USD oracle reference price
```

Pyth publishes sponsored Monad-mainnet feeds for both `MON/USD` and `USDC/USD` (among
others). When Phase 11 builds this, the oracle client must surface:

- the reference price;
- publish timestamp / feed freshness;
- confidence interval;
- explicit stale-feed detection (never silently use a stale price).

## Honest labeling

For obscure or thinly-liquid tokens, the UI/report must call this **"executable
value"**, never **"market price"** — it represents what the route says the wallet could
actually receive right now, at the quoted route's liquidity depth and slippage, not an
independent valuation. Example shape (illustrative, not implemented):

```text
Balance:             4,200 RANDOM
Indicative output:   17.82 MON
MON/USD reference:   $0.0215 (Pyth, published 3s ago, confidence ±0.4%)
Executable value:    ~$0.38
Minimum received:    17.46 MON
Price impact:        7.8%
Quote age:           9 seconds
```

## Oracle usage boundary

Pyth (or an equivalent Monad-supported oracle) is used only for:

- MON/USD and USDC/USD reference conversion for display;
- sanity-checking wildly divergent quotes for UI warnings;
- deployment-time liquidity budgeting (Phase 8/10's dynamically-sized demo liquidity —
  already documented in `docs/requirements-traceability.md` conflict C-2).

It is never used by `SweepExecutor` or the adapters to authorize or size an execution —
those remain governed entirely by the signed plan's exact amounts and enforced
`minAmountOut`, matching PRD §5.4/§19.9's balance-delta accounting model. An oracle
snapshot may be stored alongside a finalized report for historical USD context, but it
is never treated as proof that an arbitrary token has tradable value.

## Not implemented by this review

No `PriceService`, no 0x/PancakeV2/UniswapV3 quote client, and no Pyth integration
exist yet. This document is the binding constraint for whoever builds Phase 11's
`packages/routing` pricing logic — recorded now, before that phase starts, so "just use
an oracle for everything" can never quietly replace the execution-safety model that
Phases 2–5 already implemented and tested.
