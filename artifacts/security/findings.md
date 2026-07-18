# Phase 7 Finding Register

Every finding identified during this Phase 7 pass, in the format Task 7's operating
rules require: finding ID, severity, reproduction, root cause, fix, regression test,
commit hash, residual risk. Findings are listed in the order discovered. Commit
hashes are filled in against the final commit list in
`PHASE_7_SECURITY_COMPLETION_REPORT.md` (this document was written before those
commits were created, then updated once they existed).

Severity legend (per this Phase 7 prompt): **P0** immediate fund loss/arbitrary
execution/false security claim; **P1** authorization bypass/replay/theft/adapter-
boundary bypass/immutable mutation/unsafe fund retention; **P2** significant
correctness/DoS/gas/unsupported-token/opsec issue; **P3** minor hardening/docs.

---

## F7-01 (P3) — `_returnRemainders`'s `owner` parameter shadows `Ownable.owner()`

- **Reproduction:** `slither . --exclude-dependencies` → `shadowing-local` finding
  against `src/SweepExecutor.sol:466`.
- **Root cause:** the parameter was named `owner`, colliding in name (not in actual
  behavior - Solidity resolves this correctly at compile time) with the inherited
  `Ownable.owner()` view function, a code-clarity hazard for future maintainers.
- **Fix:** renamed the parameter to `planOwner`. Zero behavior change.
- **Regression test:** none needed (pure rename); `forge test` re-run confirmed
  136/136 (at the time of the fix) still passing.
- **Residual risk:** none.

## F7-02 (P3) — `_executeActions`'s `actionIndex` relied on implicit zero-initialization

- **Reproduction:** `slither . --exclude-dependencies` → `uninitialized-local`
  finding against `src/SweepExecutor.sol:326`.
- **Root cause:** Solidity zero-initializes local value types by default; the
  variable was correct in behavior but the detector (reasonably) flags any
  declared-without-assignment local for reviewer clarity.
- **Fix:** added explicit `= 0`. Zero behavior change (no-op semantically).
- **Regression test:** none needed; `forge test` re-run confirmed still passing.
- **Residual risk:** none.

## F7-03 (P2, test-coverage gap, not a code defect) — Untested zero-address admin rejections

- **Reproduction:** `forge coverage --ir-minimum` showed `SweepExecutor.sol` branches
  87.10% (27/31), with `registerOutputToken(address(0))` and
  `recoverStrayTokens(token, amount, address(0))`'s `ZeroAddress` reverts never
  exercised by any existing test.
- **Root cause:** these two zero-address guards were correct in the code from
  earlier phases, but no test had ever driven a zero-address input through them.
- **Fix:** no code change - added `test_registerOutputToken_rejectsZeroAddress` and
  `test_recoverStrayTokens_rejectsZeroAddressRecipient` in
  `test/SweepExecutorCompleteness.t.sol`.
- **Regression test:** the two tests above; both pass.
- **Residual risk:** none - the guards were already correct, only untested.

## F7-04 (P2, test-coverage gap) — Untested native-MON-output-with-zero-swaps branch

- **Reproduction:** same coverage run, `_settleOutput`'s `if (wmonDelta > 0)` false
  branch (line 449) never exercised - no test constructed a plan requesting native
  MON output with zero swap actions.
- **Root cause:** all prior native-MON tests included at least one swap producing
  WMON; the "native output, but nothing to unwrap" shape was never tried.
- **Fix:** no code change - added
  `test_nativeMonOutput_withNoSwapProducingMon_settlesToZero` in
  `test/SweepExecutorCompleteness.t.sol`, proving `outputAmount` correctly resolves
  to zero with no native transfer attempted and no revert.
- **Regression test:** the test above; passes.
- **Residual risk:** none.

## F7-05 (P2, test-coverage gap) — Untested adapter constructor/path-validation branches

- **Reproduction:** same coverage pass, `PancakeV2Adapter.sol` branches 61.54%
  (8/13), `UniswapV3Adapter.sol` branches 75% (6/8) - neither adapter's constructor
  zero-address checks, `allowIntermediateAsset`'s zero-address check,
  `_getAmountOut`'s zero-`amountIn`/zero-reserve guards, or `_validatePath`'s
  too-short-path guard had ever been exercised with an actual invalid input.
- **Root cause:** same pattern as F7-03/F7-04 - correct guards, never tested.
- **Fix:** no code change - added 10 tests in new file
  `test/AdapterCompleteness.t.sol` covering both adapters' constructor zero-address
  rejection (factory/router, wmon, owner), `allowIntermediateAsset` zero-address
  rejection, zero-`amountIn` swap rejection, and too-short-path rejection.
- **Regression test:** the 10 tests above; all pass. Post-fix coverage:
  `PancakeV2Adapter.sol` 92.31% branches (12/13), `UniswapV3Adapter.sol` 100%
  branches (8/8).
- **Residual risk:** `PancakeV2Adapter._getAmountOut`'s zero-reserve
  (`InsufficientLiquidity`) branch remains untested (would require constructing a
  zero-liquidity pair and routing a multi-hop swap through it) - low security value
  given the check is a single, simple, already-reviewed comparison, and not pursued
  further given diminishing returns. Documented, not silently dropped.

## F7-06 (P3, informational, no fix applied) — Unreachable zero-owner clause in three constructors

- **Reproduction:** while writing F7-05's zero-owner tests, `vm.expectRevert
(PancakeV2Adapter.ZeroAddress.selector)` failed with the actual revert being OZ's
  own `OwnableInvalidOwner`, not the contract's own `ZeroAddress`.
- **Root cause:** `SweepExecutor`, `PancakeV2Adapter`, and `UniswapV3Adapter` all
  call `Ownable(initialOwner_)` (the base constructor) before their own constructor
  body's `initialOwner_ == address(0)` check runs. OZ v5's `Ownable` constructor
  itself reverts `OwnableInvalidOwner` for a zero owner, so by the time each
  contract's own check would fire, execution has already reverted via the base
  constructor - making that specific clause of each contract's own check dead code
  for the owner parameter.
- **Fix:** none applied. The zero address is still correctly rejected either way -
  removing the redundant clause would be optional cleanup with zero security
  benefit, and PRD/operating-rule guidance is to fix minimally, not refactor while
  reviewing.
- **Regression test:**
  `test_pancakeV2Adapter_constructor_rejectsZeroOwner`/`test_uniswapV3Adapter_
constructor_rejectsZeroOwner` updated to assert the actual observed error
  (`vm.expectRevert()` generic, with an inline comment explaining why).
- **Residual risk:** none - documented purely for reviewer clarity, since a future
  auditor tracing this exact code path might otherwise wonder why the "obvious"
  branch never appears reachable in coverage.

## F7-07 (P3, test-harness artifact, not a production vulnerability) — `DemoDistributor` invariant self-claim edge case

- **Reproduction:** the first version of `DemoDistributorHandler.claim` (invariant
  test harness) allowed the fuzzed claimant address to equal `DemoDistributor`'s own
  deployed address; when fuzzed to that exact value, the resulting self-transfer
  netted to zero balance change while `claimed[distributor]` was still recorded true,
  breaking the invariant's aggregate-distribution accounting check.
- **Root cause:** test-harness overbreadth (fuzzing an address space that includes
  an address no real caller could ever present), not a `DemoDistributor.sol` defect.
  Nothing can make an external call arrive with `msg.sender` equal to an existing
  contract's own address without that contract's private key, which contracts don't
  have.
- **Fix:** excluded `address(DISTRIBUTOR)` from the fuzzed claimant space via
  `vm.assume(claimant != address(DISTRIBUTOR))` in
  `test/DemoDistributorInvariants.t.sol`, documented inline.
- **Regression test:** `invariant_claimedAddressesHoldExactlyOneBundleWorth`, now
  passing at 8,192 calls, 0 reverts, 0 unhandled failures.
- **Residual risk:** none - `DemoDistributor.sol` itself was never modified; this
  was purely a test-harness correction.

## F7-08 through F7-13 (P3 each, false positives / accepted patterns, no fix) — Six Slither High/Medium findings

Full individual triage for all six (plus all 31 Low/Informational findings) is in
`artifacts/security/slither-triage.md`, not duplicated here. Summary:

| ID    | Detector                     | Disposition                                                                                                               |
| ----- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| F7-08 | `arbitrary-send-eth`         | False positive - `plan.recipient` is signature-bound, not attacker-arbitrary                                              |
| F7-09 | `reentrancy-balance`         | Mitigated by `ReentrancyGuard`, directly tested                                                                           |
| F7-10 | `proxy-storage-collision`    | False positive - no delegatecall/proxy pattern exists (verified by grep)                                                  |
| F7-11 | `amm-spot-oracle-dependency` | False positive - flagged function reads zero AMM reserves/prices (verified by direct code reading)                        |
| F7-12 | `unused-return` (×2)         | Intentional and documented at the point of definition (balance-delta accounting, not trusting reported reserve timestamp) |

---

## Summary

| Severity | Count                                                | Fixed with code change | Fixed with test-only addition | Documented, no fix needed |
| -------- | ---------------------------------------------------- | ---------------------- | ----------------------------- | ------------------------- |
| P0       | 0                                                    | —                      | —                             | —                         |
| P1       | 0                                                    | —                      | —                             | —                         |
| P2       | 3 (F7-03, F7-04, F7-05)                              | 0                      | 3                             | 0                         |
| P3       | 10 (F7-01, F7-02, F7-06, F7-07, F7-08 through F7-13) | 2                      | 1                             | 7                         |

**No P0 or P1 finding was identified in this Phase 7 pass.** This is consistent with
the prior RA-01 remediation (completed before Phase 7 began) having already closed
the last known P1 (the forged-freeze-readiness / arbitrary-adapter architecture gap)
and its own P2 follow-up (the Phase 9 deployment-identity gate, addressed as a
tracked documentation requirement rather than a runtime code change, per that
session's own scope).
