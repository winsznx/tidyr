# Security Addendum Findings — Pre-Phase-7 Review

Date: 2026-07-17. Triggered by an external review of a Multicall3 approval-drain
vulnerability class, requesting a mandatory audit of Phases 0–6 before Phase 7.

Severity legend: **P0** direct fund-loss/arbitrary-drain; **P1** authorization/replay/
approval/routing/balance-isolation issue; **P2** correctness/incomplete capability;
**P3** documentation/minor.

| ID   | Severity                                | Existing implementation                                                                                                                                                                                    | Required state                                                      | Fix                                                                                                                                                        | Test                                                                                                                             |
| ---- | --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| F-1  | — (not applicable)                      | No Multicall3 reference exists anywhere in TIDYR's own production code; the RA-01 remediation additionally removed the adapter registry Multicall3 could ever have been registered into                    | Multicall3 must never be approved/spender/adapter/router/recipient  | No fix needed. RA-01 superseded the earlier named test with a structural guarantee (see below).                                                            | `SweepExecutor.t.sol::test_registerAdapterSelector_noLongerExists`, `test_removeAdapterSelector_noLongerExists`                  |
| F-2  | — (not applicable)                      | `SweepExecutor` only accepts typed `SwapAction`/`TransferAction`/`DiscardAction`/`BurnAction`; no generic `Call{target,callData}` exists (grep confirmed)                                                  | No arbitrary execution targets                                      | No fix needed                                                                                                                                              | `test_invalidAdapterKindOrdinal_revertsAtAbiDecode`, structural (no such struct exists to test against)                          |
| F-3  | — (not applicable)                      | Permit2 integration uses `SignatureTransfer.permitWitnessTransferFrom` exclusively, never `AllowanceTransfer`                                                                                              | SignatureTransfer only                                              | No fix needed                                                                                                                                              | `Permit2Witness.t.sol` (7 tests), `SweepExecutor.t.sol` signing helper                                                           |
| F-4  | — (not applicable)                      | `aggregateTokenAmounts` requests exact per-token sums; no `type(uint256).max` request exists in contracts                                                                                                  | Exact amounts, never unlimited                                      | No fix needed                                                                                                                                              | `Permit2Witness.t.sol::test_aggregateTokenAmounts_dedupesAndSums`, `test_excessivePull_fails`                                    |
| F-5  | P1-adjacent (hardening, not an exploit) | `executionPlanHash` did not explicitly include `chainId`/`executor`, though Permit2's own domain separator and `msg.sender` binding already made cross-chain/cross-executor replay structurally impossible | Explicit binding per the review's request, for audit clarity        | Added `chainId` and `executor` as the first two parameters to `SweepPlanLib.hashPlan`, mirrored in TypeScript; regenerated and re-verified golden vector A | `SweepPlanLib.t.sol` (new chainId/executor tests via `TEST_CHAIN_ID`/`TEST_EXECUTOR`), `executionPlanHash.test.ts` (2 new tests) |
| F-6  | P1-adjacent (hardening, not an exploit) | Adapter/output-token registries were mutable by the owner indefinitely                                                                                                                                     | Ability to permanently lock configuration, per the review's request | Added `freezeConfiguration()` to `SweepExecutor`, `PancakeV2Adapter`, `UniswapV3Adapter`, each with a `whenNotFrozen` modifier on its mutation functions   | 3 new tests on `SweepExecutor`, 2 each on both adapters                                                                          |
| F-7  | — (not applicable)                      | `msg.sender == plan.owner` already enforced                                                                                                                                                                | No delegated execution in V1                                        | No fix needed                                                                                                                                              | `test_notPlanOwner_reverts`                                                                                                      |
| F-8  | — (not applicable)                      | No executor-side `token.approve(spender, 0)` on a user's behalf exists (grep confirmed); revocations are direct EOA transactions per PRD §19.2                                                             | No executor-side revoke                                             | No fix needed                                                                                                                                              | Established in Phase 2; re-confirmed by grep this review                                                                         |
| F-9  | — (not applicable)                      | `displayManifestHash` and `executionPlanHash` are two distinct hashes with cross-language golden vectors                                                                                                   | Two independent hashes                                              | No fix needed (vector re-verified after F-5's change)                                                                                                      | `SweepPlanLib.t.sol`, `executionPlanHash.test.ts`/`displayManifestHash.test.ts`                                                  |
| F-10 | — (not applicable)                      | Balance-delta isolation from pre-existing/other-plan balances, extensively tested including an 8,192-call invariant suite                                                                                  | Plan-fund isolation                                                 | No fix needed                                                                                                                                              | Phase 4 unit/fuzz/invariant suite                                                                                                |
| F-11 | — (not applicable)                      | `allowFailure` cannot rescue a "successful-but-low-output" swap — always fatal via `AdapterInvariantViolation`                                                                                             | Correct `allowFailure` semantics                                    | No fix needed                                                                                                                                              | `test_adapterUnderDelivers_revertsInvariantViolation_regardlessOfAllowFailure`                                                   |
| F-12 | — (not applicable)                      | `TokenAssessment` is already a capability-flag model (`tradable`/`transferable`/`burnable`), not an exclusive enum                                                                                         | Honest, non-exclusive capability model                              | No fix needed                                                                                                                                              | `packages/shared/src/actions.test.ts`                                                                                            |
| F-13 | P2 (not yet reached)                    | No dynamic token-discovery pipeline exists yet                                                                                                                                                             | Production support for any ERC-20, not just demo tokens             | Documented design intent in `docs/token-support-model.md`; implementation is Phase 11/12                                                                   | none yet — tracked, not faked                                                                                                    |
| F-14 | P2 (not yet reached)                    | No PriceService/oracle integration exists yet                                                                                                                                                              | Executable-value pricing distinct from oracle reference price       | Documented design intent in `docs/pricing-and-oracle-model.md`; implementation is Phase 11                                                                 | none yet — tracked, not faked                                                                                                    |
| F-15 | P2 (not yet reached)                    | No three-layer transaction-review signing gate exists in a UI yet (the two hashing layers it depends on do exist)                                                                                          | Manifest / calldata-decode / simulation as a mandatory signing gate | Deferred to Phase 11, dependency (`packages/routing` quotes) doesn't exist yet                                                                             | none yet — tracked, not faked                                                                                                    |
| F-16 | P3                                      | No TypeScript-level approval/transaction builder exists yet, so `approvalBuilder_rejectsMulticall3AsSpender` (as literally named in the review request) cannot be written against real code                | Explicit test once the builder exists                               | Recorded as a mandatory Phase 11 requirement in `docs/implementation-plan.md`'s Phase 11 row, rather than writing a test against nonexistent code          | deferred, tracked                                                                                                                |
| F-17 | P3                                      | 0x integration doesn't exist yet                                                                                                                                                                           | Spender allowlisting for 0x-returned spenders                       | Documented design intent in `docs/approval-architecture.md`; implementation is Phase 11/12                                                                 | none yet — tracked, not faked                                                                                                    |

## Disposition (as of this document's original review pass)

- **P0: none found.**
- **P1: none found as exploitable gaps.** Two P1-adjacent hardening items (F-5, F-6)
  were identified as reasonable additions and both are fixed and tested.
- **P2:** three items (F-13, F-14, F-15), all belonging to phases not yet reached;
  documented as binding design intent rather than implemented out of sequence.
- **P3:** two items (F-16, F-17), tracked as explicit future requirements.

**Correction (Codex addendum audit finding CA-10):** an earlier version of this
disposition miscounted F-17 as P2 in this summary while the table above correctly
labeled it P3; the counts above are now consistent with the table.

## Independent audit findings (Codex, 2026-07-17) — see `audit/` for full detail

An independent audit of this document and the branch's three commits found **one real
P1** this document's own review pass missed: **CA-01** — `registerAdapter` accepted any
nonzero address (including Multicall3's real address), and `freezeConfiguration` did
not verify registered adapters' own configuration was itself frozen, so a "frozen"
`SweepExecutor` did not actually establish that only reviewed, immutable adapters were
reachable. The named Multicall3 test (`test_multicall3_rejectedAsUnregisteredAdapter`)
proved only the default unregistered state, not that registration itself was blocked.

This has been fixed: `registerAdapter` now explicitly reverts (`AdapterIsMulticall3`)
for Multicall3's address, and `freezeConfiguration` now requires every currently
registered adapter to itself report `configurationFrozen() == true` (reverting
`RegisteredAdapterNotFrozen` otherwise). See `docs/approval-architecture.md` and
`docs/requirements-traceability.md` for full detail, and
`packages/contracts/test/SweepExecutor.t.sol`'s
`test_registerAdapter_rejectsMulticall3Explicitly`,
`test_freezeConfiguration_revertsIfRegisteredAdapterNotFrozen`,
`test_freezeConfiguration_succeedsWhenAllRegisteredAdaptersFrozen`, and
`test_freezeConfiguration_ignoresRemovedAdapters` for the regression tests.

The independent audit also found **nine** P2/P3 documentation-accuracy and
test-completeness gaps (CA-02 through CA-10, excluding CA-01), all resolved in the same
remediation pass: freeze-readiness (CA-02, same fix as CA-01), an overclaimed
recipient restriction (CA-03, corrected — see conflict C-8 in
`docs/requirements-traceability.md`), incomplete hash-mutation regression coverage
(CA-04, closed with 6 new Solidity tests and 4 new TypeScript tests), untracked
Phase 11/12 acceptance gates for pricing/oracle and generic-token deferrals (CA-05/CA-06,
now explicit in `docs/implementation-plan.md`), inaccurate grep-evidence claims (CA-07,
corrected throughout this evidence package), a real `forge fmt` failure (CA-08, fixed),
a stale vector/count reference in `docs/requirements-traceability.md` (CA-09, corrected),
and this document's own count mismatch (CA-10 — an earlier version of this document's
disposition summary miscounted findings; corrected). (**RA-04 correction:** an earlier
version of this paragraph itself said "eight" — CA-02 through CA-10 is nine items, not
eight; this is that correction.)

**Superseded by a subsequent independent re-audit (RA-01, P1):** the CA-01/CA-02 fix
described above — `AdapterIsMulticall3` rejection plus adapter-readiness-gated
freezing — was found insufficient. Registration still accepted arbitrary contracts,
and freeze trusted an arbitrary contract's self-reported `configurationFrozen()`
value, which a malicious or mutable adapter could forge. This has since been
remediated by removing the adapter registry entirely in favor of a closed
`AdapterKind` enum resolving to two immutable, constructor-fixed adapter addresses —
see the "Addendum: RA-01 remediation" section at the top of
`docs/security-addendum-review.md` and `packages/contracts/src/SweepExecutor.sol` for
the current design. `test_registerAdapter_rejectsMulticall3Explicitly` and
`test_multicall3_rejectedAsUnregisteredAdapter`, referenced throughout this document,
no longer exist — replaced by `test_registerAdapterSelector_noLongerExists`,
`test_removeAdapterSelector_noLongerExists`, and
`test_invalidAdapterKindOrdinal_revertsAtAbiDecode`.

Phase 7 may proceed once this remediation pass's own validation commands all pass
(see the bottom of `artifacts/security-addendum/test-results.md`) and an independent
re-audit confirms no P0/P1 remains. See `artifacts/security-addendum/test-results.md` for the exact
commands and output substantiating every "no fix needed" and "fixed" row above.
