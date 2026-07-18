# Fuzz Report — Phase 7 Task 7.7

## Default and CI fuzz configuration (`foundry.toml`)

```toml
[fuzz]
runs = 256

[profile.ci.fuzz]
runs = 2048
```

## Critical-property runs at 10,000 (this session)

Per Task 7.7's "at least 10,000 runs for critical authorization and hashing
properties where practical," the four fuzz properties touching the executor's core
safety invariants were run explicitly at 10,000 runs each:

```bash
cd packages/contracts
forge test --match-test "testFuzz_" --fuzz-runs 10000 -vv
```

| Property                                                                                                                                                                                                                                                                                                      | Runs   | Result | Mean gas |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ------ | -------- |
| `testFuzz_swapAmount_fullyConserved(uint96)` — swap output fully conserved across arbitrary input amounts                                                                                                                                                                                                     | 10,000 | PASS   | 263,075  |
| `testFuzz_transferAndDiscard_neverRetainsFunds(uint96,uint96)` — transfer+discard combinations never leave residual balance                                                                                                                                                                                   | 10,000 | PASS   | 219,618  |
| `testFuzz_preExistingBalance_neverAttributedToPlan(uint96,uint96)` — stray pre-existing balance never attributed to an unrelated plan                                                                                                                                                                         | 10,000 | PASS   | 212,522  |
| `testFuzz_adapterKindAndAllowFailureCombinations_neverLoseOrMisattributeFunds(bool,uint96,bool,bool)` (this session) — both `AdapterKind` values × wide amount range × both `allowFailure` settings × under/over-delivery, asserting funds are never silently lost or misattributed regardless of combination | 10,000 | PASS   | 244,179  |

Total wall-clock for all four at 10,000 runs each: **3.3 seconds** (parallelized
across available cores by `forge test`'s own runner).

## What each fuzzed dimension covers, mapped to Task 7.7's checklist

| Requested dimension                                                                                          | Covered by                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Amounts                                                                                                      | All four properties (`uint96` amount ranges, bounded to realistic values via `bound()`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| AdapterKind                                                                                                  | `testFuzz_adapterKindAndAllowFailureCombinations_...` (`bool useUniswapKind` selects between the two closed values)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Optional/required failure combinations                                                                       | Same property (`bool allowFailure` × `bool underDeliver`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Pre-existing balances                                                                                        | `testFuzz_preExistingBalance_neverAttributedToPlan`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Action combinations (transfer+discard)                                                                       | `testFuzz_transferAndDiscard_neverRetainsFunds`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Deadlines, nonces, recipients, token combinations, duplicate tokens, action order, route bytes, minAmountOut | **Not independently fuzzed as standalone properties** - covered instead by the exhaustive _deterministic_ mutation-sensitivity suite in `SweepPlanLib.t.sol`/`executionPlanHash.test.ts` (one test per field, proving each independently changes the hash) and the invariant campaign's `runSweep`/`attemptUnauthorizedAdmin` handlers (which do vary amounts, action shape, and caller identity across thousands of pseudo-random invariant calls - see `invariant-report.md`). This is a deliberate scope choice: deadline/nonce/recipient/route-byte _sensitivity_ is a hash-correctness property best proven exhaustively and deterministically (already done), not a property that benefits from additional randomized fuzzing on top of that. |

## Rejected-input ratio

None of the four fuzz properties above use `vm.assume` to reject inputs except via
`bound()` (which remaps rather than discards), so the rejected-input ratio for these
four properties is effectively **0%** - every generated input produces a valid,
assertable test case. (The invariant campaign's handlers do use `vm.assume` for
address exclusions - see `invariant-report.md` for that ratio.)

## Reproducing this report

```bash
cd packages/contracts
forge test --match-test "testFuzz_" --fuzz-runs 10000 -vv
```
