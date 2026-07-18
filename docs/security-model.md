# TIDYR Security Model — Phase 7 Task 7.1

This document describes the defensive mechanisms TIDYR's contracts rely on, as a
single reference distinct from `docs/threat-model.md` (which maps threats to
defenses) and `docs/approval-architecture.md` (which focuses specifically on
approval/spender safety). See those two documents for threat-specific and
approval-specific detail respectively; this document is the architectural summary.

## 1. Closed adapter set (no generic registry)

`SweepExecutor` resolves every swap to one of exactly two immutable addresses
(`PANCAKE_V2_ADAPTER`, `UNISWAP_V3_ADAPTER`) fixed at construction, via a closed
`SweepPlanLib.AdapterKind` enum. There is no `registerAdapter`, no mutable adapter
mapping, and no way to express an arbitrary adapter address in a `SwapAction` at all.
Solidity's own ABI decoder rejects any out-of-range `AdapterKind` ordinal before
`executeSweep`'s body ever runs. See `SweepExecutor.sol`'s contract-level doc comment
for the full history (this superseded an earlier owner-managed-registry design, per
Codex re-audit finding RA-01).

## 2. Never-trust-adapter-return-values (balance-delta accounting)

Every swap's actual output is measured as a balance delta
(`balanceOf(this)` before vs. after the adapter call), never taken from the
adapter's own return value. This defeats an entire class of malicious/buggy adapter
behavior (reporting a fake output, sending output elsewhere, reentering) without
needing to trust the adapter's honesty at all.

## 3. Exact, single-use approvals (`forceApprove`, never unlimited)

The executor approves each adapter for exactly `action.amountIn` immediately before
the swap call and resets the approval to zero immediately after (success or
failure). No adapter is ever granted a standing/unlimited approval.

## 4. Permit2 witness binding (total plan commitment)

Every field of a `SweepPlan` that matters for authorization - owner, recipient,
outputToken, deadline, nonce, every action (including `adapterKind`, `routeData`,
`minAmountOut`), plus `chainId` and the executor's own address - is bound into a
single `executionPlanHash`, which is itself bound into the Permit2 witness signed via
`permitWitnessTransferFrom`. There is no field a signature "doesn't cover" - changing
any single field invalidates the signature entirely (proven exhaustively in
`SweepPlanLib.t.sol`/`executionPlanHash.test.ts`'s mutation-sensitivity suite and
`SweepExecutorAdversarial.t.sol`'s substitution tests).

## 5. Plan-fund isolation (baseline/delta accounting for every token)

Every token a plan touches (input, output, or otherwise) has its balance snapshotted
immediately before the Permit2 pull. Every subsequent accounting decision - what
counts as "this plan's output," what counts as "unconsumed remainder to return" - is
computed as a delta against that baseline, never an absolute balance. This means
pre-existing/forced/stray balances are never attributed to a plan, and a plan's own
unconsumed input is never lost.

## 6. Reentrancy guard shared across the execution/recovery boundary

`executeSweep` and `recoverStrayTokens` share a single `nonReentrant` lock, so stray
funds can never be "recovered" mid-execution, and no reentrant call from an adapter
or token can re-enter either function.

## 7. Irreversible configuration freeze, coupled to adapter-level state

`SweepExecutor.freezeConfiguration()` permanently locks the output-token allowlist
and additionally requires both fixed adapters to have already frozen their own
intermediate-asset allowlists - so a "frozen" deployment's entire reachable execution
surface (not just the executor's own directly-owned state) is locked, not merely the
executor's own top-level mapping.

## 8. Constructor-time validation of immutable dependencies

`SweepExecutor`'s constructor rejects a zero address, an EOA (no code), a duplicate
adapter pair, or Multicall3's real verified address in either adapter slot. This
narrows _which_ addresses can occupy the two immutable slots; it cannot itself prove
the deployed bytecode is the audited adapter source (see `docs/threat-model.md`
threat 6) - that residual trust boundary is closed at the deployment-process level
by the strengthened Phase 9 gate (`docs/requirements-traceability.md`).

## 9. Two independent hashes (execution vs. display)

`executionPlanHash` (what Permit2 actually authorizes) and `displayManifestHash`
(what a wallet UI could show a user) are structurally distinct and proven never to
collide for the same plan. This is the precondition for a future wallet-side
transaction-review boundary to work at all (Phase 11) - not yet a complete defense
on its own (see `docs/threat-model.md` threat 3's residual risk).

## 10. No delegatecall, no proxies, no arbitrary execution targets

Every contract in scope is immutable and non-upgradeable by construction - no
`delegatecall` exists anywhere in `packages/contracts/src` (verified by direct grep,
recorded in `artifacts/security/manual-review.md`), no proxy pattern is used, and the
only external call surfaces from `SweepExecutor` are: the two fixed adapters'
`swap()`, Permit2's `permitWitnessTransferFrom`, ERC-20 `transfer`/`transferFrom`/
`approve` on plan-specified token addresses, native MON send to `plan.recipient`, and
WMON's `withdraw`. No generic `Call{target, callData}` structure exists.

## Independent verification commands

```bash
cd packages/contracts
grep -rn "delegatecall" src/                       # expect: only doc comments stating its absence, zero actual opcodes/calls
grep -rn "struct Call\b" src/                      # expect: no matches
forge test                                          # 152/152 (as of this Phase 7 pass)
```
