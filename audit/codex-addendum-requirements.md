# Codex Security Addendum Requirements Matrix

Audit scope: Phases 0–6 and commits `ab3d458`, `9de4c84`, `0276555`. Phase 7–16 deliverables were not treated as currently required.

| Area | Independent result | Evidence / finding |
| --- | --- | --- |
| Branch range | Exactly three linear commits after `124c0b9`; no unrelated application feature detected | `git rev-list --count` = 3; per-commit inspection |
| Rewritten history | Not independently provable without a trusted remote/ref history | Local graph is linear; merge-base is `124c0b9` |
| Secrets / suppressions / disabled tests | No added secret detected; no blanket lint/security suppression or disabled test found | secret scan, diff search, tracked inventory |
| Execution hash chain/executor | Implemented with `block.chainid` and `address(this)` | `SweepExecutor.sol:175`; `SweepPlanLib.sol:134` |
| Hash field binding | Implementation binds all plan fields and action arrays without packed dynamic-data ambiguity | Element hashes + `abi.encode`; independent all-field TS mutation run passed |
| Solidity/TypeScript parity | Golden vector reproduced by both suites | Solidity 12-test suite and TS vector test pass |
| Complete mutation regression suite | Incomplete | CA-04 |
| Display vs execution hash | Intentionally distinct and tested | Solidity and TS tests pass |
| Permit2 primitive | Canonical vendored `ISignatureTransfer`; witness transfer path | `SweepExecutor.sol:7,223-237` |
| Exact amounts / duplicates | Exact aggregated amounts; Solidity 0.8 checked addition | `SweepPlanLib.aggregateTokenAmounts`; tests pass |
| Spender / recipient / caller | Permit spender is executor call context; pulls go to executor; owner caller enforced | `SweepExecutor.sol:166,228,235`; wrong-spender test passes |
| Replay / expiry / substitution | Nonce, deadline, and witness checks reproduce | Permit2 7-test suite passes |
| AllowanceTransfer core path | Not used by TIDYR production source | source inspection |
| Unlimited initial approvals | No production builder exists yet; shared type permits exact amount; policy deferred | No current production transaction generator to audit |
| Multicall3 read-only boundary | Not enforced as claimed | CA-01, CA-03, CA-07 |
| Arbitrary target/callData | No generic target + callData or delegatecall production surface found | full-repository search + interface/control-flow inspection |
| Freeze irreversibility | Boolean cannot be unset; registry mutation blocked | freeze tests pass |
| Freeze safety/readiness | Incomplete | CA-01, CA-02 |
| Ownership bypass | No alternate registry mutator found; Ownable2Step transfer changes authorized owner only | source/inheritance inspection |
| Balance isolation | Baselines precede Permit2 pull; settlement and input deltas used | `SweepExecutor.sol:184-202,322-355`; unit/fuzz/invariants pass |
| Duplicate inputs | Aggregated and returned once per unique token | source + tests |
| Output used as swap input | Explicitly rejected | `SweepExecutor.sol:179-181` |
| Output used by transfer/discard/burn | Delta accounting remains safe | control-flow inspection |
| Native MON / WMON | Separate native and WMON baselines | `SweepExecutor.sol:189-190,328-343` |
| Optional swap failure | Subcall revert is atomic; allowance reset; required failure bubbles; low output is fatal | `SweepExecutor.sol:284-319`; tests pass |
| Executor-side user revocation | Absent | source/type search |
| Demo-token production allowlist | No current contract/shared-type input allowlist found | arbitrary token addresses accepted by plan/action schemas and adapters |
| Dynamic-token future tracking | Architecture permits it, but formal acceptance tracking is incomplete | CA-06 |
| Fake USD oracle / hardcoded $0.50 | No production pricing/oracle dependency or fixed production price found | repository search/source inspection |
| `minAmountOut` | Remains execution safety invariant | adapters + executor delta check |
| PriceService deferral | Narrative design exists; formal phase acceptance tracking incomplete | CA-05 |
| Documentation capability claims | Several addendum evidence/completion claims are inaccurate | CA-03, CA-07–CA-10 |

## Independently observed totals

- TypeScript: 26 passed (shared 6, execution 1, routing 1, API 1, indexer 1, transaction-review 16).
- Deterministic Solidity: 87 passed, 0 failed, 0 skipped.
- Monad fork: 2 passed, 0 failed, 0 skipped with network access.
- Invariants: 2 passed; 128 runs × 64 depth = 8,192 calls per invariant, zero reverts.
- Fuzz: 3 properties passed at 2,048 runs each under the CI profile.

