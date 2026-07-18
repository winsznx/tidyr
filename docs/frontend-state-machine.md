# TIDYR Frontend State Machines (Phase F0)

## App-level state

```
BOOT
  → PROVIDER_UNAVAILABLE      (no injected/WalletConnect provider reachable)
  → DISCONNECTED              (provider available, no active connection)
      → CONNECTING
          → WRONG_CHAIN       (connected, chainId !== 143)
              → SWITCHING_CHAIN → WORKSPACE_READY | WRONG_CHAIN (switch rejected)
          → WORKSPACE_READY
              → SCANNING
                  → PARTIAL_SCAN   (some wallets/tokens degraded)
                  → PLANNING
              → PLANNING
                  → REVIEWING
                      → SIGNING
                          → EXECUTING
                              → PARTIALLY_COMPLETE
                              → COMPLETE
                              → FAILED
                          → SIGNING (signature rejected → re-enter queue)
                      → PLANNING (manifest invalidated, must re-review)
              → RESUMED_SESSION (page reload with a persisted manifest ID)
```

Terminal-adjacent states (`COMPLETE`, `FAILED`, `PARTIALLY_COMPLETE`) always
route to `/app/report/[manifestHash]`, which independently re-derives status
from chain logs rather than trusting the in-memory state that got it there.

## Per-wallet execution graph (mirrors PRD §12, chain-only)

```
PENDING
  → SIGNING            (Permit2 witness signature requested)
      → SIGNED
          → BROADCASTING
              → CONFIRMING   (receipt polling, no WS)
                  → CONFIRMED
                  → FAILED → RETRY_AVAILABLE | ABANDONED
      → SIGNING (rejected, stays in queue, user may retry)
```

Rules carried over from the PRD, unchanged by the chain-only decision:

1. All signatures for a broadcast round are collected before anything is sent.
2. Each wallet's first transaction is broadcast together
   (`Promise.allSettled`).
3. Within a wallet, transaction N+1 only broadcasts after N confirms —
   Monad's nonce ordering makes concurrent sends within one wallet unsafe.
4. One wallet's failure never blocks another wallet's graph.
5. A confirmed wallet's queue never re-runs.
6. Confirmation is receipt-polling (`waitForTransactionReceipt`), not a
   WebSocket subscription — the PRD's WS design assumes infra that does not
   exist yet (see `frontend-integration-matrix.md` §0). This is stated in the
   execution-monitor UI, not hidden.

## Quote / route state (per token, per sell action)

```
IDLE
  → CHECKING_OUTPUT_ALLOWED     (allowedOutputTokens read)
      → OUTPUT_UNAVAILABLE      (not allowed on-chain right now)
      → FINDING_ROUTE
          → NO_ROUTE            (no pool at any fee tier / no pair)
          → QUOTING
              → LIVE            (quote in hand, countdown running)
                  → REFRESHING
                  → EXPIRING    (<10s remaining)
                  → EXPIRED     (must re-quote, blocks signing)
              → INSUFFICIENT_LIQUIDITY
              → EXCESSIVE_IMPACT
              → PROVIDER_UNAVAILABLE   (RPC call failed)
```

A quote in `EXPIRED` state hard-blocks the review card's sign button — this
is enforced in `lib/review/`, not just in the UI, so no code path can carry a
stale quote into `executeSweep` encoding.

## Review verification layers (PRD §11, chain-only adaptation)

```
Layer 1 — Intent manifest
  buildManifest(plan) → canonical JSON (RFC 8785 via packages/transaction-review)
    → displayManifestHash

Layer 2 — Calldata decode-and-compare
  encodeExecuteSweep(plan) → decodeFunctionData → compare every field
  against the manifest. Any mismatch → BLOCKED, diff shown.

Layer 3 — Simulation
  eth_call staticcall of executeSweep against current mainnet state
  (real read-only call, not a mocked result) → compare balance deltas
  (pre-call balanceOf reads vs. the staticcall's implied deltas) against
  the manifest's expected leaving/receiving amounts.
  NOTE: this is a lighter-weight substitute for the PRD's Tenderly bundle
  simulation (full trace + storage diff) — labeled "Simulation (on-chain
  read-only call)" in the UI, not "Tenderly", since that integration does
  not exist.

Sign button enables only when all three layers report PASS.
```

## Demo lifecycle (`/demo`, PRD §"Phase 10/Demo")

```
NOT_CONNECTED
  → CONNECTING
      → CHECKING_CLAIM_STATUS      (DemoDistributor.claimed(address))
          → ALREADY_CLAIMED
          → CLAIMABLE
              → CLAIMING           (claim() sent)
                  → CLAIM_FAILED   (reverted — e.g. distributor exhausted)
                  → CLAIM_CONFIRMED
                      → SCANNING_CLAIMED_TOKENS
                          → GUIDED_ACTIONS   (sell tradable, burn-or-sell DUST4,
                                              consolidate-or-discard DUST5)
                              → REVIEWING → SIGNING → EXECUTING → REPORT
```

`DISTRIBUTOR_EXHAUSTED` is its own first-class state (checked via the
relevant DUST token's `balanceOf(distributor)` before claim is offered), not
folded into a generic error.
