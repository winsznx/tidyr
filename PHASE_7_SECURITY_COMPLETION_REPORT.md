# Phase 7 — Contract Security Verification: Completion Report

## Completion gate checklist

- [x] All relevant validation commands pass (see `artifacts/security/test-summary.md`)
- [x] No P0 remains (0 found this pass)
- [x] No P1 remains (0 found this pass)
- [x] No unresolved critical/high Slither issue remains (all 4 High + 2 Medium
      findings individually triaged as false positives or already-mitigated-and-tested
      — `artifacts/security/slither-triage.md`)
- [x] Invariants are meaningful and passing (4 invariants, 8,192 calls each, 0
      reverts — `artifacts/security/invariant-report.md`)
- [x] Fork claims are evidenced (13/13 fork tests against live Monad mainnet,
      including a genuine RPC session this pass — `artifacts/security/fork-report.md`)
- [x] Permit2 substitution tests pass (`test_signedAdapterKind_
cannotBeSubstitutedAtExecution`, `test_planASignature_cannotAuthorizePlanB_*`,
      `test_signature_doesNotSurviveChainIdChange`, `test_signature_
doesNotSurviveCrossExecutorReplay`, plus the pre-existing Permit2Witness.t.sol
      suite)
- [x] Pre-existing balance isolation is proven (`test_preExistingExecutorBalance_
isNotSweptIntoPlan`, `test_preExistingOutputTokenBalance_isNotSweptIntoPlan`,
      `testFuzz_preExistingBalance_neverAttributedToPlan` at 10,000 runs)
- [x] Closed `AdapterKind` architecture remains intact (unchanged this phase; RA-01
      remediation predates Phase 7 and was independently re-verified against
      committed `HEAD` before Phase 7 began)
- [x] Adapter dependencies remain immutable (unchanged; re-verified)
- [x] Configuration freeze is proven (`test_freezeConfiguration_
revertsUnlessBothAdaptersFrozen`, `test_repeatedFreeze_isHarmlessNoOp`,
      `test_swapsUnaffectedByFreezeState`)
- [x] Maximum-action gas is measured (3,605,566 gas isolated cost for the worst-case
      50-distinct-token plan — `artifacts/security/gas-report.md`)
- [x] Security-sensitive branches are covered (branch coverage raised from 87.10%/
      61.54%/75% to 93.55%/92.31%/100% for `SweepExecutor`/`PancakeV2Adapter`/
      `UniswapV3Adapter` respectively — `artifacts/security/coverage-report.md`)
- [x] All evidence artifacts exist (see file list below)
- [x] Requirements traceability is updated (Phase 9 deployment gate strengthened,
      `docs/requirements-traceability.md`)
- [x] Repository is clean (working tree clean after this report's commits — see
      commit list below)

## 1. Branch

`security/phase-7-verification`

## 2. Baseline commit

`1a5f70c43b4189e084f2367c9ca71c9539846404` (tag `security-addendum-candidate`)

## 3. Final commit

The six commits below plus one final small documentation-accuracy commit filling in
their hashes here and in `artifacts/security/findings.md` (a self-reference a commit
cannot make about its own future hash) — see `git log --oneline
security-addendum-candidate..HEAD` for the authoritative, current final commit.

## 4. Commits created this phase

Focused, by root cause, no co-author trailers:

1. `2359bd8` — `test: expand Permit2 authorization coverage and add adversarial cases`
2. `cca84fe` — `test: strengthen executor invariants and add DemoDistributor invariant`
3. `d2ae834` — `fix: rename shadowing local and initialize actionIndex explicitly`
4. `dd67f1d` — `test: close coverage gaps in adapter constructor and path validation`
5. `9b0bdcc` — `test: measure gas at plan-shape extremes and verify Monad mainnet topology`
6. `2a128a5` — `docs: publish TIDYR contract threat model and Phase 7 security evidence`
7. (this commit) — `docs: record Phase 7 commit hashes in completion report and findings register`

See `git log --oneline security-addendum-candidate..HEAD` to reproduce this list
independently.

## 5. Files changed

- **New test files (7):** `test/SweepExecutorAdversarial.t.sol`,
  `test/SweepExecutorCompleteness.t.sol`, `test/SweepExecutorGas.t.sol`,
  `test/AdapterCompleteness.t.sol`, `test/DemoDistributorInvariants.t.sol`,
  `test/MonadMainnetTopology.fork.t.sol`
- **New mock contracts (6):** `test/mocks/MockFalseReturnERC20.sol`,
  `test/mocks/MockNoReturnERC20.sol`, `test/mocks/MockFeeOnTransferERC20.sol`,
  `test/mocks/MockRevertingRecipient.sol`, `test/mocks/MockReentrantERC20.sol`,
  `test/mocks/MockMaliciousAdapter.sol`
- **Modified test files (2):** `test/SweepExecutorInvariants.t.sol` (admin-boundary
  handler + invariant)
- **Modified source (1):** `src/SweepExecutor.sol` (two zero-risk Slither-triage
  renames/initializations — `owner` → `planOwner`, explicit `actionIndex = 0`)
- **New docs (3):** `docs/threat-model.md`, `docs/security-model.md`,
  `docs/audit-preparation.md`
- **New security artifacts (10):** `artifacts/security/findings.md`,
  `test-summary.md`, `fuzz-report.md`, `invariant-report.md`, `fork-report.md`,
  `slither-report.md`, `slither-triage.md`, `slither-raw-output.txt`,
  `gas-report.md`, `coverage-report.md`, `manual-review.md`
- **Modified docs (1):** `docs/requirements-traceability.md` (strengthened Phase 9
  deployment gate)
- **New root doc (1):** `PHASE_7_SECURITY_COMPLETION_REPORT.md` (this file)
- **Regenerated:** `packages/contracts/.gas-snapshot`

## 6. Deterministic test total

**152** (Solidity, `forge test`, was 103 at Phase 7's start — +49 this phase; 0
failed, 0 skipped)

## 7. TypeScript test total

**30** (`pnpm test`, unchanged this phase — no TypeScript code was touched)

## 8. Fuzz tests and runs

4 properties, each run explicitly at **10,000 runs** (see `fuzz-report.md`):
`testFuzz_swapAmount_fullyConserved`, `testFuzz_transferAndDiscard_neverRetainsFunds`,
`testFuzz_preExistingBalance_neverAttributedToPlan`,
`testFuzz_adapterKindAndAllowFailureCombinations_neverLoseOrMisattributeFunds` (new
this phase). Default profile: 256 runs; CI profile: 2,048 runs.

## 9. Invariants and exact configuration

`[invariant] runs = 128, depth = 64, fail_on_revert = true` (CI profile: 512×128).
4 invariants: `invariant_executorRetainsNoTouchedTokenBalance`,
`invariant_nonceMatchesCallCount`, `invariant_ownerNeverChanges` (new),
`invariant_claimedAddressesHoldExactlyOneBundleWorth` (new,
`DemoDistributorInvariants.t.sol`). All pass at 8,192 calls each, 0 reverts. See
`invariant-report.md` for the handler-function breakdown and the one genuine
test-harness finding (F7-07) discovered and fixed while writing the new
DemoDistributor invariant.

## 10. Fork tests

**13/13 pass** against live Monad mainnet (2 pre-existing + 11 new this phase — see
`fork-report.md`). No transaction broadcast.

## 11. Coverage

Deterministic-suite branch coverage: `SweepExecutor.sol` 93.55% (was 87.10%),
`PancakeV2Adapter.sol` 92.31% (was 61.54%), `UniswapV3Adapter.sol` 100% (was 75%).
Full breakdown, including two documented likely tool-instrumentation anomalies, in
`coverage-report.md`.

## 12. Slither result

37 findings (down from 39 after two zero-risk fixes), **0 unresolved critical/high**
— every finding individually triaged in `slither-triage.md` (4 High: 3 false
positives + 1 already-mitigated-and-tested; 2 Medium: both intentional/documented
patterns; 15 Low + 16 Informational: reviewed and accepted or fixed). No blanket
suppression used.

## 13. Gas measurements

Worst-case `executeSweep` (50 distinct-token transfers, the maximum `MAX_ACTIONS`
shape): **3,605,566 gas** (isolated, excluding test-harness setup) — well within
normal single-transaction bounds. Full breakdown in `gas-report.md`, including the
recommendation that Monad gas-limit estimation use a narrow buffer (10-15%, not a
blanket 2x) since Monad charges against the submitted gas limit.

## 14. P0/P1/P2/P3 counts

| Severity | Count                                                                                                                                                     |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0       | 0                                                                                                                                                         |
| P1       | 0                                                                                                                                                         |
| P2       | 3 (all test-coverage gaps against already-correct code, closed with new tests — F7-03, F7-04, F7-05)                                                      |
| P3       | 10 (2 fixed with code changes, 1 fixed with a test-harness correction, 7 documented with no fix needed — F7-01, F7-02, F7-06, F7-07, F7-08 through F7-13) |

Full detail in `artifacts/security/findings.md`.

## 15. Findings fixed

- F7-01: `shadowing-local` (renamed parameter)
- F7-02: `uninitialized-local` (explicit initialization)
- F7-03: untested zero-address admin rejections (added 2 tests)
- F7-04: untested native-MON-zero-swaps branch (added 1 test)
- F7-05: untested adapter constructor/path-validation branches (added 10 tests)
- F7-07: DemoDistributor invariant self-claim test-harness artifact (excluded
  self-address from fuzzed claimant space)

## 16. Remaining accepted risks

1. **No wallet-level transaction-review boundary yet** (Phase 11 work) - the single
   largest residual risk, explicitly not a Phase 7 deliverable.
2. **Deployment-integrity trust boundary** cannot be closed by contract code alone -
   mitigated by the strengthened Phase 9 gate (Task 7.14), not eliminated.
3. **`hono` dependency in `apps/api`** is significantly outdated (39 `pnpm audit`
   findings, 7 high) - out of this phase's contract-security scope, flagged as a
   recommended follow-up, not fixed here.
4. **Two coverage-tool anomalies** (`UniswapV3Path.sol`, `DemoDistributor.sol`)
   documented as likely `--ir-minimum` instrumentation limitations, backed by direct
   source-code call-chain tracing.
5. **Monad's own block gas limit was not independently re-verified** against the
   3.6M-gas worst-case measurement - noted in `gas-report.md` as a pre-Phase-9 check.
6. **F7-05's residual:** `PancakeV2Adapter._getAmountOut`'s zero-reserve branch
   remains untested (low security value, documented, not pursued further).

None of these six are P0/P1-severity contract bugs.

## 17. Whether Phase 8 may begin

**No. Phase 8 (mainnet deployment tooling) may not begin.** This report is a
security-verification pass only; no deployment transaction was created, and the
strengthened Phase 9 gate (Task 7.14) must itself be implemented as part of Phase 9's
own deploy script before any deployment proceeds.

## 18. Whether the repository is ready for a fresh-session Claude adversarial audit

**Yes.** `docs/audit-preparation.md` is written specifically for this purpose - it
points a fresh reviewer to the architecture docs, the prior audit history, this
phase's own evidence artifacts, and the exact commands to independently re-verify
every claim in this report rather than take any of it on faith.
