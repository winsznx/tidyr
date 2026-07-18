# TIDYR Phase 7 — Independent Adversarial Audit

**Auditor stance:** this report treats the prior Claude session's summaries, test
counts, findings register, and completion report as unverified claims. Every figure
below was independently reproduced by reading source directly and re-running the
underlying commands in this session, not copied from prior artifacts.

**Scope:** `security/phase-7-verification`, baseline `1a5f70c`, claimed final commit
`3290568`. Read-only audit — no production code was modified, no commits/pushes/PRs
were made.

## 1. Git and repository state

Confirmed directly:
- Current branch: `security/phase-7-verification` ✓
- Baseline tag `security-addendum-candidate` at `1a5f70c` ✓
- Final commit `3290568` ✓
- Working tree clean before and after this audit (`git status --short` empty both
  times) ✓
- `git diff 1a5f70c...3290568 --stat`: 33 files changed, all within
  `packages/contracts/{src,test}`, `docs/`, `artifacts/security/`, root-level
  report/status docs, and `.gitignore` — **zero** touches to `apps/`,
  `deployments/`, `packages/routing`, `packages/execution`, or any frontend path ✓
- All six Phase 7 working commits between baseline and final are present and in the
  expected order: `2359bd8`, `cca84fe`, `d2ae834`, `dd67f1d`, `9b0bdcc`, `2a128a5`,
  followed by the final commit `3290568` ✓

## 2. Core contract review (read in full, not sampled)

Read line-by-line: `SweepExecutor.sol`, `PancakeV2Adapter.sol`, `UniswapV3Adapter.sol`,
`SweepPlanLib.sol`, `TidyrWitness.sol`, `UniswapV3Path.sol`, `IAdapter.sol`,
`Permit2Marker.sol`, `DemoDistributor.sol`.

Findings from direct reading (not from trusting the docs):

- **No adapter registry.** `AdapterKind` is a closed 2-value enum; `_adapterFor`
  resolves it to one of two `immutable` fields set once in the constructor. There is
  no setter, no mapping, no `address adapter` field in `SwapAction`. Solidity's ABI
  decoder itself rejects any `uint8` value outside `{0,1}` for this enum before
  `executeSweep`'s body runs — confirmed by a real test constructing raw calldata
  with ordinal `2` and observing revert-at-decode.
- **Adapters cannot select an arbitrary router/target.** Both adapters resolve their
  DEX call target exclusively from their own `immutable` `FACTORY`/`ROUTER` — never
  from `routeData`. `routeData` supplies only a token path, validated endpoint-to-
  endpoint against `tokenIn`/`tokenOut` and intermediate-hop-by-intermediate-hop
  against an owner-controlled (pre-freeze) allowlist.
- **Balance-delta accounting throughout.** `_executeSwap` never trusts an adapter's
  returned `amountOut`; it measures `settlementToken` balance before/after and
  reverts (`AdapterInvariantViolation`) on any shortfall, regardless of
  `allowFailure`. This is the correct, described semantics: `allowFailure` governs
  whether the *adapter's own revert* is tolerated, not whether under-delivery is
  tolerated — under-delivery is always fatal.
- **Plan-fund isolation.** Every touched token (and native MON) has its balance
  snapshotted immediately before the Permit2 pull; every later accounting decision
  is a delta against that baseline, so forced/pre-existing balances can never be
  attributed to a plan.
- **Freeze is irreversible and coupled.** No `unfreeze` function exists anywhere in
  `src/`. `SweepExecutor.freezeConfiguration()` additionally requires both fixed
  adapters to have already frozen their own `allowedIntermediateAssets` state
  before it will freeze itself.
- **No delegatecall, no proxy pattern.** `grep -rn delegatecall src/` returns only a
  doc-comment hit; no `Proxy`/`UUPSUpgradeable` base anywhere. All cross-contract
  dependencies (`PERMIT2`, `WMON`, both adapter addresses, both adapters' own
  `FACTORY`/`ROUTER`/`WMON`) are `immutable`.
- **Permit2 integration is `SignatureTransfer`-only.** `_pullViaPermit2` calls
  `PERMIT2.permitWitnessTransferFrom` exclusively; no `AllowanceTransfer`/standing-
  approval call exists in `SweepExecutor.sol`.
- **`executionPlanHash` binds everything claimed.** Read `SweepPlanLib.hashPlan` and
  `_hashSwapActions`/`_hashTransferActions`/`_hashDiscardActions`/`_hashBurnActions`
  in full: `chainId`, `executor`, `owner`, `recipient`, `outputToken`, `deadline`,
  `nonce`, `displayManifestHash`, and every action field including `adapterKind`,
  `keccak256(routeData)`, `minAmountOut`, `allowFailure` — hashed element-wise per
  array (order-sensitive) then hashed again as an array of hashes, specifically
  avoiding `abi.encode`'s nested-dynamic-bytes ambiguity.

## 3. Solidity vs. TypeScript hash cross-check

Compared `packages/contracts/src/libraries/SweepPlanLib.sol::hashPlan` against
`packages/transaction-review/src/executionPlanHash.ts::hashExecutionPlan`
field-for-field: identical parameter order, identical ABI types. Both sides assert
the same golden constant
(`0xc277e8285240c296bf7df135856a7fad4a4e665f94c1f469e9cc6940f71e31d3`) for the same
hand-built plan (Vector A). Ran both suites independently — `SweepPlanLibTest`
18/18 pass, TypeScript `executionPlanHash.test.ts` (part of the transaction-review
20-test suite) pass, including the exact assertion
`assert.equal(hash, VECTOR_A_EXPECTED_HASH)`.

## 4. Independent command re-execution (full detail in `phase-7-command-log.md`)

Every command below was run fresh in this session (not assumed from prior reports):

| Check | Result |
|---|---|
| `pnpm install --frozen-lockfile` | clean |
| `pnpm format` (prettier `--check`) | clean (`pnpm format:check` as literally named does not exist — see Finding AF-05) |
| `pnpm lint` (eslint) | clean |
| `pnpm typecheck` | 6/6 workspaces pass |
| `pnpm test` | **30/30 TypeScript tests pass** (independently tallied: 6+1+1+1+1+20) |
| `pnpm build` | 6/6 workspaces pass |
| `forge fmt --check` | clean |
| `forge clean && forge build` | exit 0; only benign `block-timestamp` deadline-check warnings in `src/`, rest in test files |
| `forge test --summary` | **152/152 Solidity tests pass** (independently tallied across all 17 suites) |
| `forge test --match-test "testFuzz_" --fuzz-runs 10000 -vv` | **4/4 fuzz properties, 10,000 runs each, all PASS** |
| invariant suites (same `forge test` run) | **4 invariants, 8,192 calls each, 0 reverts, all PASS** |
| fork suites (same run, live `https://rpc.monad.xyz`) | **13/13 fork tests pass** against genuinely live Monad mainnet state |
| `forge coverage --ir-minimum --report summary` | figures **exactly match** `coverage-report.md`'s claimed numbers |
| `forge snapshot` vs. committed `.gas-snapshot` | **zero diff** — byte-identical |
| `SweepExecutorGasTest` worst case | **3,605,566 gas** — matches "near 3.6M" claim |
| `slither . --exclude-dependencies --json` | **37 findings**, exactly matching claimed total; category breakdown independently parsed from JSON |
| `pnpm audit` | **39 vulnerabilities (7 high, 29 moderate, 3 low)**, all `apps/api > hono`, matching the claimed figure exactly |
| `bash scripts/scan-secrets.sh` | no secret patterns found |

**No command produced a result inconsistent with what the prior session's artifacts
claimed**, with the exception of the `pnpm format:check` naming mismatch (Finding
AF-05, cosmetic) and two internal documentation counting inconsistencies in the
Slither triage/findings register (Findings AF-01, AF-02, both cosmetic, both fully
covered in substance by the underlying per-finding reasoning).

## 5. Deep-dive checks the brief specifically asked for

**Do invariant handlers genuinely reach sensitive functions?** Yes. Read
`SweepExecutorInvariants.t.sol`'s `SweepExecutorHandler.attemptUnauthorizedAdmin` in
full: it drives `registerOutputToken`, `removeOutputToken`, `freezeConfiguration`,
and `recoverStrayTokens` from a pseudo-random non-owner `address`, and each branch
wraps the call in its own `try { revert("unauthorized X succeeded"); } catch {}` so
a regression that silently loosened `onlyOwner` would fail the *entire* invariant
campaign (`fail_on_revert = true`), not merely fail to be caught by an external
assertion. This is a real, meaningful check, not a shape-only harness.

**Do fork tests use live Monad state and never broadcast?** Yes. Both
`MonadMainnetTopology.fork.t.sol` and `PancakeV2Adapter.fork.t.sol` use
`vm.createSelectFork("https://rpc.monad.xyz")` in `setUp()` — a local, read-only
fork snapshot, never `--broadcast`. All 13 tests passed against genuinely live RPC
data in this session (confirmed by the RPC actually being reachable and returning
real bytecode/reserve data during my own `forge test` run — not a cached/mocked
response). `test_realSwap_wmonToUsdc_succeeds` computes its expected output from
live-read reserves and asserts an exact match, which could not pass against stale
or fabricated data.

**Do fuzz assumptions filter out most meaningful cases?** No. All four fuzz
properties use `bound()` (remap, not reject) for their amount ranges; the only
`vm.assume` in the four properties is
`vm.assume(transferAmount + discardAmount > 0)` in
`testFuzz_transferAndDiscard_neverRetainsFunds`, which rejects only the single
degenerate zero/zero case. Rejection ratio is effectively 0%, matching the
fuzz-report's own claim.

**Was Slither's 37 findings individually and correctly triaged?** Substantively
yes — `slither-triage.md` gives a specific, falsifiable rationale for every finding
category, and I independently verified the three claimed false positives by
re-reading the flagged code myself: `arbitrary-send-eth` (recipient is
signature-bound, confirmed by `hashPlan` binding `plan.recipient`),
`proxy-storage-collision` (no delegatecall/proxy base anywhere, confirmed by grep),
and `amm-spot-oracle-dependency` (`_settleOutput` contains zero AMM/reserve reads,
confirmed by direct reading — it only calls `balanceOf` and `WMON.withdraw`).
However, the itemized **count** of `calls-loop` instances is wrong (documented as 8,
actually 10 per my independent JSON parse) — see Finding AF-01. This is a labeling
error, not a missed finding: the category-level rationale (bounded by
`MAX_ACTIONS = 50`) covers all 10 actual instances equally well.

**Were P2/P3 findings improperly dismissed?** No. F7-03/F7-04/F7-05 (P2,
coverage-gap findings) were closed with real new tests, independently confirmed by
my own coverage re-run showing the exact same post-fix percentages. No P2/P3
finding was dismissed without a stated rationale traceable to either a passing test
or direct code inspection.

**Is the outdated Hono dependency accurately tracked?** Yes.
`PHASE_7_SECURITY_COMPLETION_REPORT.md` and `test-summary.md` both correctly state
"39 pnpm audit findings, 7 high," explicitly scope it to `apps/api` (out of Phase
7's contract-security scope), and flag it as a recommended follow-up rather than
silently omitting it or falsely claiming it was fixed. My own `pnpm audit` run
reproduced the exact same figures.

## 6. Findings

Five findings, all **P3**, all documentation/tooling accuracy issues with **zero
fund-safety or security-relevant impact**. Full detail with reproduction steps in
`phase-7-adversarial-findings.json`:

- **AF-01**: `slither-triage.md` undercounts `calls-loop` instances (documented as
  8, actually 10) — category-level rationale still covers all instances.
- **AF-02**: `findings.md`'s F7-08–F7-13 table has only 5 rows for a claimed 6-item
  range (both `unused-return` findings merged into one row).
- **AF-03**: `docs/permit2-witness-model.md` still says "adapter" instead of
  "adapterKind" in one table cell (stale pre-RA-01 terminology).
- **AF-04**: The audit brief requested `docs/fixed-adapter-architecture.md`, which
  does not exist in the repository (closest analog: `docs/approval-architecture.md`).
- **AF-05**: `pnpm format:check` (as literally named in common convention and this
  brief) does not exist as a script; the actual script is `pnpm format`, which
  works and passes.

**No P0 or P1 finding.** No claim in the audit brief was found to be false,
unreproducible, or overstated in a way that affects fund safety, authorization
correctness, or the closed-adapter security boundary.

## 7. Verdict

## **CONDITIONAL PASS**

Rationale: zero P0/P1 findings; all 20 requirements-brief claims independently
verified (see `phase-7-requirements-matrix.md`); all reported test/fuzz/invariant/
fork/coverage/gas/Slither/dependency-audit figures independently reproduced exactly.
The only open items are five P3 documentation-accuracy nits (AF-01 through AF-05),
none of which touch contract logic, fund safety, or the authorization boundary.
**Phase 8 may begin.** The remaining P3 items are recommended cleanup, not blockers.

## 8. Summary answers to the ten required output items

1. **Verdict:** CONDITIONAL PASS
2. **P0/P1/P2/P3 counts:** P0: 0, P1: 0, P2: 0, P3: 5
3. **Observed test totals:** 152 Solidity tests (152/152 pass), 30 TypeScript tests
   (30/30 pass) — both independently tallied from live command output, not copied
4. **Fuzz and invariant configuration:** 4 fuzz properties × 10,000 runs each, all
   PASS; 4 invariants × 8,192 calls each, 0 reverts, all PASS — default
   `foundry.toml` fuzz/invariant runs are 256/128 respectively (the 10,000-run
   figure is a specific `--fuzz-runs` override for the four critical properties,
   correctly documented as such, not a project-wide default)
5. **Fork result:** 13/13 fork tests PASS against live Monad mainnet RPC
   (`https://rpc.monad.xyz`), read-only (`vm.createSelectFork`, never `--broadcast`)
6. **Slither result:** 37 findings (independently reproduced), 0 unresolved
   critical/high after triage; 3 of the 4 "high" findings are false positives from
   detector misclassification (confirmed by direct code reading), the 4th is
   mitigated by `ReentrancyGuard` and directly tested
7. **Failing commands:** none, except the non-existent `pnpm format:check` script
   name (the actual `pnpm format` command it should invoke passes cleanly)
8. **Top findings:** AF-01 (Slither triage calls-loop miscount, 8 vs. actual 10),
   AF-02 (findings.md F7-08–F7-13 row-count mismatch) — both documentation-only,
   zero security impact
9. **Audit report path:** `audit/phase-7-adversarial-audit.md` (this file);
   supporting: `audit/phase-7-requirements-matrix.md`,
   `audit/phase-7-command-log.md`, `audit/phase-7-adversarial-findings.json`
10. **Whether Phase 8 may begin:** **Yes.** No P0/P1 finding exists, and Phase 9's
    deployment-integrity gate (bytecode/constructor-argument/immutable-dependency/
    proxy verification, not mere address equality) is already correctly specified
    in `docs/requirements-traceability.md` for that later phase to implement.
