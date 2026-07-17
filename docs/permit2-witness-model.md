# TIDYR Permit2 Witness Model

Status: implemented and tested (Phase 3, extended by this security-addendum review).

## What the witness binds

`SweepExecutor` never uses Permit2's `AllowanceTransfer` (standing, time-bound spender
allowances). It uses `SignatureTransfer` exclusively, via
`permitWitnessTransferFrom` with a `PermitBatchTransferFrom` and a custom witness
(`TidyrWitness`, `packages/contracts/src/libraries/TidyrWitness.sol`) bound to the
plan's `executionPlanHash`.

`executionPlanHash = SweepPlanLib.hashPlan(plan, chainId, executor)` covers, directly or
via per-action-array sub-hashes:

| Bound field                                                                                          | Where                                                                                                      |
| ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `chainId`                                                                                            | explicit first parameter (added by this review)                                                            |
| `executor` (SweepExecutor's own address)                                                             | explicit second parameter (added by this review)                                                           |
| `owner`                                                                                              | `plan.owner`                                                                                               |
| `recipient`                                                                                          | `plan.recipient`                                                                                           |
| `outputToken`                                                                                        | `plan.outputToken`                                                                                         |
| `deadline`                                                                                           | `plan.deadline`                                                                                            |
| `nonce`                                                                                              | `plan.nonce` (TIDYR's own sequential per-owner nonce, reused as Permit2's own unordered nonce — see below) |
| `displayManifestHash`                                                                                | `plan.displayManifestHash`                                                                                 |
| every swap: `tokenIn`, `amountIn`, `adapter`, `minAmountOut`, `keccak256(routeData)`, `allowFailure` | `_hashSwapActions`                                                                                         |
| every transfer: `token`, `amount`, `to`                                                              | `_hashTransferActions`                                                                                     |
| every discard: `token`, `amount`                                                                     | `_hashDiscardActions`                                                                                      |
| every burn: `token`, `amount`                                                                        | `_hashBurnActions`                                                                                         |

A signature over one plan cannot authorize a different plan: changing any bound field
changes `executionPlanHash`, changes the witness, and invalidates the signature. Proven
directly by `packages/contracts/test/SweepPlanLib.t.sol` (amount/recipient/outputToken/
deadline/nonce/action-order/chainId/executor sensitivity — 12 tests) and its TypeScript
mirror (`packages/transaction-review/src/executionPlanHash.test.ts`, 16 tests,
byte-identical cross-language golden vector in `test-vectors/golden-vectors.md`).

## Why chainId and executor are bound explicitly (this review's addition)

Before this review, `hashPlan` did not take `chainId` or `executor` as inputs. This was
not an exploitable gap: Permit2's own EIP-712 domain separator (`DOMAIN_SEPARATOR()`)
already includes the chain ID and Permit2's own address, so a signature produced on one
chain's Permit2 domain cannot validate against a different chain's domain separator.
Permit2 also binds the spender to `msg.sender` directly at signing time (see
`PermitHash.sol`'s use of `msg.sender`, not a caller-supplied field) — proven by
`Permit2Witness.t.sol::test_wrongSpender_fails`, where a different calling contract
cannot reuse a signature meant for the original spender.

Binding `chainId` and `executor` inside TIDYR's own `executionPlanHash` is therefore
defense-in-depth and audit clarity, not a fix for a real replay path — it makes an
already-true security property explicit in the plan's own data rather than relying
solely on an implicit property of the upstream Permit2 integration. This matches the
external review's explicit request and costs nothing at runtime (two extra `abi.encode`
words).

## Why TIDYR's own nonce doubles as Permit2's nonce

Permit2's `SignatureTransfer` nonces are an arbitrary, caller-chosen, unordered bitmap
per owner — they don't have to be sequential. TIDYR already maintains its own strictly
sequential `nonces[owner]` counter in `SweepExecutor` for replay protection at the plan
level. Reusing that same value as the Permit2-level nonce is safe (it's already unique
per executed plan for that owner) and avoids a redundant field. This is why
`SweepPlan` has no separate `permit2Nonce`.

## msg.sender must equal plan.owner (V1)

`SweepExecutor.executeSweep` requires `plan.owner == msg.sender` before anything else
happens (`NotPlanOwner` error). A valid Permit2 signature found by a third party cannot
be submitted from a different account, and there is no delegated-execution path in V1.

## Verified against a real Permit2 deployment, not a mock

All of the above is proven in `packages/contracts/test/Permit2Witness.t.sol` (7 tests)
and `packages/contracts/test/SweepExecutor.t.sol`'s signing helper, both against a real,
unmodified Permit2 contract deployed via `deployCode("Permit2.sol:Permit2")` — not an
interface stub. Covered: valid witness succeeds; a tampered witness (different
`executionPlanHash` than what was actually signed) fails; a reused nonce fails; an
expired deadline fails; a different calling contract (wrong spender) fails; an
excessive pull request beyond the signed amount fails; duplicate-token aggregation is
verified correct.

## EIP-1271 (smart-contract-wallet signatures)

Permit2 itself supports EIP-1271 (`SignatureVerification.sol`). TIDYR does not yet
exercise this path — it is exercised if/when smart-contract-wallet support is added to
the multi-wallet execution scheduler (Phase 14), not assumed now.
