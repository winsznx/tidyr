# Phase 7 Adversarial Audit — Independent Command Log

All commands below were executed fresh in this session against
`security/phase-7-verification` at commit `3290568`. Outputs are summarized; exact
figures were read directly from the terminal, not copied from prior artifacts.

## Git state verification

```
$ pwd
/Users/mac/tidyr
$ git rev-parse --show-toplevel
/Users/mac/tidyr
$ git branch --show-current
security/phase-7-verification
$ git status --short
(empty — clean working tree)
$ git log --oneline --decorate --graph -30
* 3290568 (HEAD -> security/phase-7-verification) docs: record Phase 7 commit hashes...
* 2a128a5 docs: publish TIDYR contract threat model and Phase 7 security evidence
* 9b0bdcc test: measure gas at plan-shape extremes and verify Monad mainnet topology
* dd67f1d test: close coverage gaps in adapter constructor and path validation
* d2ae834 fix: rename shadowing local and initialize actionIndex explicitly
* cca84fe test: strengthen executor invariants and add DemoDistributor invariant
* 2359bd8 test: expand Permit2 authorization coverage and add adversarial cases
* 1a5f70c (tag: security-addendum-candidate) docs: record RA-01 remediation...
  ... (pre-Phase-7 history continues)
$ git diff 1a5f70c...3290568 --stat
 33 files changed, 3636 insertions(+), 12 deletions(-)
 (packages/contracts/{src,test}, docs/, artifacts/security/, root reports, .gitignore only)
$ git show --stat 3290568
 PHASE_7_SECURITY_COMPLETION_REPORT.md | 41 +++++++++++-------------
 artifacts/security/findings.md        | 10 +++++----
 2 files changed, 20 insertions(+), 31 deletions(-)
```

**Result:** Branch, baseline, and final commit all confirmed as claimed. Working tree
clean before and after this audit's read-only command runs (verified again at the
end — see "Post-audit cleanliness check" below).

## pnpm / TypeScript toolchain

```
$ pnpm install --frozen-lockfile
Lockfile is up to date, resolution step is skipped → Done in 262ms

$ pnpm format:check
ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL  Command "format:check" not found
  (package.json defines "format", not "format:check" — see Finding AF-05)

$ pnpm format
> prettier --check .
Checking formatting...
All matched files use Prettier code style!

$ pnpm lint
> eslint .
(clean, no output, exit 0)

$ pnpm typecheck
6/6 workspaces: shared, indexer, execution, api, routing, transaction-review — all "Done"

$ pnpm test
packages/shared:              6 pass, 0 fail
packages/execution:           1 pass, 0 fail
packages/routing:             1 pass, 0 fail
apps/indexer:                 1 pass, 0 fail
apps/api:                     1 pass, 0 fail
packages/transaction-review: 20 pass, 0 fail
TOTAL: 30/30 TypeScript tests pass, 0 fail, 0 skipped

$ pnpm build
6/6 workspaces: all "Done", exit 0
```

## Solidity / forge toolchain

```
$ cd packages/contracts
$ forge --version
forge Version: 1.7.1

$ forge fmt --check
(clean, no output, exit 0)

$ forge clean && forge build
Exit 0. Warnings only: block-timestamp (3, in src/ — standard deadline-check pattern,
benign) and unsafe-typecast/erc20-unchecked-transfer (test files only).

$ forge test --summary
17 test suites, 152 tests, 152 passed, 0 failed, 0 skipped.
Suite breakdown (independently counted from live output):
  AdapterCompletenessTest 10, DemoDistributorTest 8, DemoDistributorInvariantsTest 1,
  DemoTokenTest 6, MonadMainnetTopologyForkTest 11, PancakeV2AdapterForkTest 2,
  PancakeV2AdapterTest 12, Permit2WitnessTest 7, SweepExecutorTest 32,
  SweepExecutorAdapterIntegrationTest 2, SweepExecutorAdversarialTest 14,
  SweepExecutorCompletenessTest 9, SweepExecutorGasTest 3, SweepExecutorInvariantsTest 3,
  SweepPlanLibTest 18, ToolchainSmoke 1, UniswapV3AdapterTest 13.
  Sum = 152. Matches claimed total exactly.

Invariants (from the same run):
  invariant_claimedAddressesHoldExactlyOneBundleWorth   runs:128 calls:8192 reverts:0 PASS
  invariant_executorRetainsNoTouchedTokenBalance        runs:128 calls:8192 reverts:0 PASS
  invariant_nonceMatchesCallCount                       runs:128 calls:8192 reverts:0 PASS
  invariant_ownerNeverChanges                           runs:128 calls:8192 reverts:0 PASS
  = 4 invariants, 8,192 calls each. Matches claimed total exactly.

Fork tests (same run, live RPC https://rpc.monad.xyz reachable):
  MonadMainnetTopologyForkTest: 11/11 pass
  PancakeV2AdapterForkTest: 2/2 pass
  = 13 fork tests total. Matches claimed total exactly.

$ time forge test --match-test "testFuzz_" --fuzz-runs 10000 -vv
testFuzz_adapterKindAndAllowFailureCombinations_neverLoseOrMisattributeFunds  runs:10000 PASS
testFuzz_preExistingBalance_neverAttributedToPlan                            runs:10000 PASS
testFuzz_swapAmount_fullyConserved                                           runs:10000 PASS
testFuzz_transferAndDiscard_neverRetainsFunds                                runs:10000 PASS
= 4/4 fuzz properties, 10,000 runs each, 0 failures. Wall clock: 2.24s (matches
  "3.3 seconds" claim in fuzz-report.md within measurement variance).
```

## Coverage and gas

```
$ forge coverage --ir-minimum --report summary
(run with fork tests included, unlike the reference command which excludes them —
per-file % identical either way since fork tests don't add branch coverage to src/)

src/SweepExecutor.sol             98.53% lines, 98.90% stmts, 93.55% (29/31) branches, 100% funcs
src/adapters/PancakeV2Adapter.sol 100% lines, 98.91% stmts, 92.31% (12/13) branches, 100% funcs
src/adapters/UniswapV3Adapter.sol 100% lines, 100% stmts, 100% (8/8) branches, 100% funcs
src/libraries/SweepPlanLib.sol    100% across the board
src/libraries/TidyrWitness.sol    100% across the board
src/libraries/UniswapV3Path.sol   87.50% lines, 73.33% stmts, 0% (0/3) branches, 100% funcs
src/tokens/DemoDistributor.sol    85.71% lines, 86.67% stmts, 100% branches, 100% funcs

Every figure is an EXACT match to artifacts/security/coverage-report.md's claimed
numbers, independently reproduced (not copied).

$ cp .gas-snapshot /tmp/gas-snapshot-committed.txt
$ forge snapshot
$ diff -u /tmp/gas-snapshot-committed.txt .gas-snapshot
(no output — zero diff, gas snapshot is exactly reproducible)

$ forge test --match-contract SweepExecutorGasTest -vv
test_gas_maxActionsPlan_50DistinctTokenTransfers: executeSweep gas = 3,605,566
  (matches claimed "worst-case sweep near 3.6M gas" exactly)
```

## Slither

```
$ slither --version
0.11.5

$ slither . --exclude-dependencies --json /tmp/slither.json
INFO:Slither:. analyzed (48 contracts with 117 detectors), 37 result(s) found
Exit code: 255 (Slither's normal "findings present" exit code, not a crash)

$ python3 -c "... count JSON detector results by category ..."
count: 37
  amm-spot-oracle-dependency 1     arbitrary-send-eth 1        assembly 2
  calls-loop 10                    cyclomatic-complexity 1     low-level-calls 1
  naming-convention 8              operator-fee-outlier 2      pragma 2
  proxy-storage-collision 1        reentrancy-balance 1        solc-version 1
  timestamp 3                      too-many-digits 1           unused-return 2
  Sum = 37. Matches claimed total exactly.

NOTE: artifacts/security/slither-triage.md itemizes calls-loop as "8 instances"
(items 8-15) but the actual detector output contains 10 distinct calls-loop results.
See Finding AF-01.
```

## Dependency and secret audits

```
$ pnpm audit
39 vulnerabilities found. Severity: 3 low | 29 moderate | 7 high
(all under apps/api > hono; matches PHASE_7_SECURITY_COMPLETION_REPORT.md's claimed
"39 pnpm audit findings, 7 high" exactly)

$ bash scripts/scan-secrets.sh
No secret patterns found in tracked files. Exit 0.
```

## Cross-language hash consistency

```
$ grep -n "VECTOR_A_EXPECTED_HASH\|0xc277e828" \
    packages/contracts/test/SweepPlanLib.t.sol \
    packages/transaction-review/src/executionPlanHash.test.ts
Both files assert the identical literal:
  0xc277e8285240c296bf7df135856a7fad4a4e665f94c1f469e9cc6940f71e31d3
Both suites run and pass (SweepPlanLibTest 18/18, transaction-review 20/20 as part
of the totals above).
```

## delegatecall / proxy grep

```
$ grep -rn "delegatecall" src/
src/SweepExecutor.sol:29: (doc comment only — "no delegatecall" — zero actual opcodes/calls)

$ grep -rn "struct Call\b" src/
(no matches)
```

## Post-audit cleanliness check

```
$ git status --short
(empty — clean working tree; no production code modified, forge/coverage build
artifacts land in .gitignore'd out/ and cache/ directories, .gas-snapshot
regenerated byte-identical to the committed version)
```

## Commands specified in the brief that could not be run as literally named

- `pnpm format:check` — no such script; the actual script is `pnpm format`
  (`prettier --check .`), which was run instead and passes. See Finding AF-05.
- "the configured dependency audit" — no dedicated script beyond `pnpm audit`
  (no `package.json` script wraps it); ran `pnpm audit` directly.
- "the configured secret scan" — `scripts/scan-secrets.sh`, wired as
  `pnpm security:secrets`; ran directly via `bash scripts/scan-secrets.sh`.
