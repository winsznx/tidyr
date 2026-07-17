# TIDYR Security Addendum — Pre-Phase-7 Review

**Date:** 2026-07-17
**Trigger:** an external review (prompted by a public discussion of Multicall3
approval-drain vectors) requesting a mandatory security architecture review of Phases
0–6 before Phase 7 (the PRD's own security-hardening phase) begins.
**Branch:** `fix/security-addendum-before-phase-7`

## Method

Every claim in the review request was checked against the actual repository state —
grepped, read, or exercised with a test — not assumed from the request's own framing.
Where a claim turned out to already be satisfied, the evidence is cited below rather
than re-implemented. Where a claim identified a real gap, it was fixed and tested.
Where a claim described work that belongs to a later, not-yet-reached phase, that is
stated plainly rather than built out of sequence or faked with a stub.

## Summary of findings

**Zero P0 (fund-drain) findings.** The architecture already avoided every mechanism the
review was concerned about, before this review started:

- No generic `Call{target, callData}` execution surface exists anywhere in
  `SweepExecutor` or the adapters — confirmed by `grep -rn "struct Call\b"` across
  `packages/contracts/src` (no matches).
- Before this review, no Multicall3 reference existed anywhere in the codebase; an
  earlier draft of this document claimed `rg -n -i multicall packages apps` produced no
  matches at all. **That claim was imprecise and has been corrected** (Codex addendum
  audit finding CA-07): the command actually returns many matches once vendored
  dependencies are included — OpenZeppelin's own unrelated call-batching `Multicall.sol`
  utility and forge-std's own `IMulticall3`/`MULTICALL3_ADDRESS` helper, both under
  `packages/contracts/lib/`, neither related to TIDYR's adapter/spender risk. Restricting
  the search to TIDYR's own production and test code
  (`rg -n -i multicall packages/contracts/src packages/contracts/test packages/shared packages/routing packages/transaction-review packages/execution apps`)
  found, at the time of the original review, zero matches in production source
  (`packages/contracts/src`) and zero matches anywhere else — Multicall3 could not yet
  be approved, made a spender, or registered as anything, because nothing touched it at
  all. This review's own fix for CA-01 subsequently added a deliberate
  `MULTICALL3_ADDRESS` constant and explicit-rejection check to
  `packages/contracts/src/SweepExecutor.sol`, plus corresponding tests — those are now
  legitimate, intentional matches, not evidence of a gap.
- The only `.call{value: ...}` in `src/` sends the plan's own settled output to
  `plan.recipient` — a user-designated destination for the user's own funds, not an
  attacker-controlled arbitrary call.
- `forceApprove` is only ever called against `action.adapter` (owner-registered,
  allowlisted) or an adapter's own immutable `ROUTER` — never a user-supplied address.

**Two P1-adjacent hardening items identified and fixed** (not exploitable gaps, but
real, worthwhile defense-in-depth):

1. `executionPlanHash` did not explicitly bind `chainId` or the executor's own address.
   Cross-chain and cross-executor replay were already structurally impossible (Permit2's
   own EIP-712 domain separator includes both, and Permit2 binds the spender to
   `msg.sender` at signing time — proven by `Permit2Witness.t.sol::test_wrongSpender_fails`),
   but the review's request to bind them explicitly in TIDYR's own plan hash is reasonable
   audit-clarity hardening. **Fixed** — see "Execution plan hash now binds chainId and
   executor" below.
2. The adapter/output-token registries were mutable by the owner indefinitely.
   **Fixed** — `freezeConfiguration()` added to `SweepExecutor`, `PancakeV2Adapter`, and
   `UniswapV3Adapter`.

**One documentation/test-completeness item added:** an explicit test proving the real,
verified Multicall3 address is rejected as an adapter the same way any other
unregistered address would be — not because it was previously reachable, but because
audit clarity benefits from a named test rather than relying on "it's just not in the
allowlist."

**Everything else in the review request is either already correct or belongs to a phase
this repository hasn't reached yet** (dynamic token discovery, the pricing/oracle
service, the three-layer transaction-review UI security boundary — all Phase 11+).
Those are documented as design intent in the four companion docs below, not implemented
now, since implementing them without the routing/quote infrastructure they depend on
would mean building disconnected, untestable code.

## What changed

| Change                                                                                                       | File(s)                                                                                                     | Reason                                                                                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `hashPlan` now takes `chainId` and `executor` as explicit parameters, included first in the ABI-encoded hash | `packages/contracts/src/libraries/SweepPlanLib.sol`, `packages/transaction-review/src/executionPlanHash.ts` | Explicit defense-in-depth binding (see above); golden vector A's hash changed as a direct, expected, and re-verified consequence — both languages still agree byte-for-byte (`0xdf7a8dd0108003ffa8b036d6471d7a6479a56d02b6b7737737c398e3515100d1`)                                                           |
| `freezeConfiguration()` + `configurationFrozen` + `whenNotFrozen` modifier                                   | `SweepExecutor.sol`, `PancakeV2Adapter.sol`, `UniswapV3Adapter.sol`                                         | Mitigates a compromised/coerced-owner registering a malicious adapter or output token after users have started trusting a live deployment. Irreversible by design — no `unfreeze`. `recoverStrayTokens` deliberately stays available after freezing since it's unrelated to the execution security boundary. |
| `test_multicall3_rejectedAsUnregisteredAdapter`                                                              | `packages/contracts/test/SweepExecutor.t.sol`                                                               | Explicit, named proof using the real verified Multicall3 address, not a placeholder address                                                                                                                                                                                                                  |
| Freeze-mechanism tests (3 on `SweepExecutor`, 2 each on both adapters)                                       | `test/SweepExecutor.t.sol`, `test/PancakeV2Adapter.t.sol`, `test/UniswapV3Adapter.t.sol`                    | Prove adapter/output-token mutation reverts after freezing, recovery still works, freeze is owner-only                                                                                                                                                                                                       |

## What did not change (already correct — cited, not re-implemented)

| Review's requirement                                                                             | Existing evidence                                                                                                                             |
| ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| No arbitrary execution targets                                                                   | `SweepExecutor.sol`'s only actions are `SwapAction`/`TransferAction`/`DiscardAction`/`BurnAction`; swaps route only through `allowedAdapters` |
| Permit2 `SignatureTransfer`, not `AllowanceTransfer`                                             | `SweepExecutor._pullViaPermit2` calls `PERMIT2.permitWitnessTransferFrom` exclusively                                                         |
| Exact Permit2 amounts, never `type(uint256).max`                                                 | `SweepPlanLib.aggregateTokenAmounts` sums exact per-token amounts; `_pullViaPermit2` requests exactly those                                   |
| Witness binds owner/recipient/outputToken/every action/every amount/every adapter/deadline/nonce | `SweepPlanLib.hashPlan` (now also chainId + executor)                                                                                         |
| `require(msg.sender == plan.owner)`                                                              | `SweepExecutor.sol`'s `NotPlanOwner` check                                                                                                    |
| No executor-side `approve(spender, 0)` on a user's behalf                                        | Confirmed absent by grep; revocations are direct EOA transactions per PRD §19.2 (Phase 2)                                                     |
| Two distinct hashes (display vs. execution) with golden vectors                                  | Phase 2 (`test-vectors/golden-vectors.md`), re-verified after this review's hash change                                                       |
| Balance-delta isolation from pre-existing/other-plan balances                                    | Phase 4 unit + fuzz + 8,192-call invariant suite                                                                                              |
| Correct `allowFailure` semantics (no "successful-but-low-output" rescue)                         | `test_adapterUnderDelivers_revertsInvariantViolation_regardlessOfAllowFailure`                                                                |
| Capability-based token assessment, not an exclusive enum                                         | `packages/shared/src/actions.ts`'s `TokenAssessment`                                                                                          |

## Deferred to their already-planned phases (not fixed now — see companion docs)

- **Dynamic token support** (no demo-token production allowlist, manual address entry,
  discovery pipeline) — Phase 11/12. See `docs/token-support-model.md`.
- **PriceService / oracle architecture** (executable value vs. reference USD price,
  Pyth MON/USD and USDC/USD) — Phase 11. See `docs/pricing-and-oracle-model.md`.
- **Three-layer transaction-review security boundary** (manifest / calldata
  decode-and-compare / simulation) as a signing gate — Phase 11, once
  `packages/routing` and quote infrastructure exist to attach it to. The two hashing
  layers it depends on already exist (Phase 2/3).
- **0x / third-party spender allowlisting** — Phase 11/12, when 0x integration is built.

## Full details

- `docs/approval-architecture.md` — Multicall3 read-only boundary, exact-amount Permit2
  approvals, no unlimited approvals policy
- `docs/permit2-witness-model.md` — the witness binding model in full, including the
  chainId/executor addition
- `docs/token-support-model.md` — dynamic token support design (Phase 11/12 intent)
- `docs/pricing-and-oracle-model.md` — pricing/oracle architecture design (Phase 11 intent)
- `artifacts/security-addendum/findings.md` — the full P0–P3 findings table
- `artifacts/security-addendum/test-results.md` — exact commands and test output
