# TIDYR Token Support Model

Status: **design intent for Phase 11/12 — not yet implemented.** This document exists so
the "demo tokens are the production allowlist" misreading is impossible to make later,
not to claim discovery/classification code exists today.

## The five demo tokens are a fixture, not an allowlist

DUST1–DUST5 (`packages/contracts/src/tokens/DemoToken.sol`,
`BurnableDemoToken.sol`) exist so judges/testers have a guaranteed, real, claimable
dataset to exercise every product state (`DemoDistributor.sol`). They must never become
the set of tokens TIDYR is willing to discover, classify, or sweep in production.

## What is genuinely hardcoded (infrastructure only)

The only addresses TIDYR's contracts and future services should ever hardcode are
protocol/infrastructure constants, already recorded in
`docs/research/external-addresses.md`:

- Monad chain configuration (chain ID 143, RPC endpoints);
- canonical WMON, USDC, Permit2, Multicall3;
- verified DEX factories/routers (PancakeSwap V2 Factory, Uniswap V3 Factory,
  SwapRouter02);
- TIDYR's own deployed `SweepExecutor` and adapter addresses (Phase 9);
- the demo-token addresses, but _only_ inside the demo-claim flow
  (`DemoDistributor`), never as a production input-token filter.

Everything else — which ERC-20s a connected wallet holds, which of those have a route
to MON/USDC, which support `burn`, which are safe to transfer — must be determined
dynamically, per the pipeline below.

## Planned discovery pipeline (Phase 11/12)

```
Connect wallet
     |
Indexer discovers candidate ERC-20s (Moralis, per PRD §7) OR user manually enters an address
     |
Multicall3 batch reads verify balance/decimals/symbol/name on-chain (read-only — see docs/approval-architecture.md)
     |
Route engine checks PancakeSwap V2 / Uniswap V3 / 0x for an executable quote
     |
Transfer + (if applicable) burn simulation from the exact wallet
     |
Capability assessment (see below)
```

Any ERC-20 discovered in the wallet, or manually pasted by the user, is a valid
candidate — there is no input-token allowlist. A token needs usable liquidity in one of
the checked sources to produce a trade; that's a market-liquidity fact about the token,
not a TIDYR-imposed restriction.

## Capability model (already implemented at the type level — Phase 2)

`packages/shared/src/actions.ts`'s `TokenAssessment` already reflects this correctly,
ahead of the discovery pipeline that will populate it:

```typescript
interface TokenAssessment {
  riskState: "VERIFIED" | "UNKNOWN";
  capabilities: {
    tradable: boolean;
    transferable: boolean;
    burnable: boolean;
  };
  failureReasons: string[];
}
```

A token is not forced into one mutually-exclusive bucket — DUST4 is simultaneously
`tradable` and `burnable`, exactly like a real token could be. Rules the discovery
pipeline must follow when it populates this type:

| Situation                                                             | Behavior                                                                    |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Fresh executable quote + successful transfer simulation               | `tradable: true` — sell enabled                                             |
| No quote, but transfer simulation succeeds                            | `transferable: true` only — consolidate/discard, not sell                   |
| Real `burn(uint256)` present and simulates successfully               | `burnable: true`                                                            |
| Transfer restrictions, blacklists, or honeypot-like behavior detected | sell blocked, reason recorded in `failureReasons`                           |
| Metadata call fails, times out, or simulation is inconclusive         | `riskState: "UNKNOWN"` — signing blocked by default, matching PRD §8/§19.16 |
| Indexer misses a real holding                                         | user can always manually enter the contract address                         |

The product promise stays: **every token can be examined; only safely executable
actions are enabled.** No sell route is never treated as "not a real token" — it's
handled as transfer/consolidate/discard/burn, whichever capabilities actually pass
simulation.

## Not implemented by this review

No discovery, classification, or simulation code exists yet — `packages/routing` and
`packages/transaction-review`'s calldata-verification layer are still stubs beyond the
Phase 2/3 hashing work. This document is the binding design constraint Phase 11/12 must
build against, recorded now so it can't be silently narrowed to "the five demo tokens"
later.
