# Validation Command Log — Phase 7

Every command and its exact observed result, run on branch
`security/phase-7-verification`, baseline commit `1a5f70c43b4189e084f2367c9ca71c9539846404`
(tag `security-addendum-candidate`).

## TypeScript / repo-wide

| Command                            | Exit                                | Result                                                                                                                                                                                 |
| ---------------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm install --frozen-lockfile`   | 0                                   | Lockfile up to date, resolution skipped                                                                                                                                                |
| `pnpm format` (prettier `--check`) | 0 (after fixing 7 newly-added docs) | All matched files use Prettier code style                                                                                                                                              |
| `pnpm lint` (eslint)               | 0                                   | clean                                                                                                                                                                                  |
| `pnpm typecheck`                   | 0                                   | 6/6 workspaces pass                                                                                                                                                                    |
| `pnpm build`                       | 0                                   | 6/6 workspaces pass                                                                                                                                                                    |
| `pnpm test`                        | 0                                   | **30/30 TypeScript tests pass**, 0 skipped (`packages/shared`: 6, `packages/routing`: 1, `packages/execution`: 1, `apps/indexer`: 1, `apps/api`: 1, `packages/transaction-review`: 20) |
| `bash scripts/scan-secrets.sh`     | 0                                   | No secret patterns found in tracked files                                                                                                                                              |
| `pnpm audit`                       | 0 (informational)                   | **39 vulnerabilities found: 7 high, 29 moderate, 3 low** — see "Dependency audit finding" below                                                                                        |

## Solidity (`packages/contracts`)

| Command                                                                                        | Exit                                              | Result                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `forge fmt --check`                                                                            | 0 (after `forge fmt` on 3 newly-added test files) | clean                                                                                                                                                                                    |
| `forge clean`                                                                                  | 0                                                 | —                                                                                                                                                                                        |
| `forge build`                                                                                  | 0                                                 | Compiler run successful (pre-existing lint warnings only — block-timestamp, erc20-unchecked-transfer in mocks, none new)                                                                 |
| `forge test -vvv`                                                                              | 0                                                 | **152/152 deterministic + invariant tests pass, 0 skipped**, across 17 test suites (was 103 at the start of this Phase 7 pass — +49 new tests this session)                              |
| `forge test --match-test "testFuzz_" --fuzz-runs 10000 -vv`                                    | 0                                                 | 4/4 fuzz properties pass at 10,000 runs each — see `fuzz-report.md`                                                                                                                      |
| `forge test --match-contract "SweepExecutorInvariantsTest\|DemoDistributorInvariantsTest" -vv` | 0                                                 | 4 invariants pass, 8,192 calls each — see `invariant-report.md`                                                                                                                          |
| `forge test --match-contract "MonadMainnetTopologyForkTest\|PancakeV2AdapterForkTest"`         | 0                                                 | 13/13 fork tests pass against live Monad mainnet — see `fork-report.md`                                                                                                                  |
| `forge coverage --no-match-path "*.fork.t.sol" --ir-minimum --report summary`                  | 0                                                 | 91.95%+ lines, 93.53% statements, 82.02% branches, 92% funcs across all files — see `coverage-report.md`                                                                                 |
| `forge snapshot`                                                                               | 0                                                 | `.gas-snapshot` regenerated, all 152 tests recorded                                                                                                                                      |
| `slither . --exclude-dependencies`                                                             | 255                                               | **This is Slither's normal "findings present" exit code, not a crash** — 37 findings, all individually triaged, 0 unresolved critical/high — see `slither-report.md`/`slither-triage.md` |

## Deterministic Solidity test count breakdown (152 total)

| Suite                                                             | Tests   |
| ----------------------------------------------------------------- | ------- |
| `ToolchainSmoke.t.sol`                                            | 1       |
| `SweepPlanLib.t.sol`                                              | 18      |
| `Permit2Witness.t.sol`                                            | 7       |
| `SweepExecutor.t.sol`                                             | 32      |
| `SweepExecutorAdversarial.t.sol` (new)                            | 13      |
| `SweepExecutorCompleteness.t.sol` (new)                           | 9       |
| `SweepExecutorGas.t.sol` (new)                                    | 3       |
| `AdapterCompleteness.t.sol` (new)                                 | 10      |
| `PancakeV2Adapter.t.sol`                                          | 12      |
| `UniswapV3Adapter.t.sol`                                          | 13      |
| `SweepExecutorAdapterIntegration.t.sol`                           | 2       |
| `DemoToken.t.sol`                                                 | 6       |
| `DemoDistributor.t.sol`                                           | 8       |
| `SweepExecutorInvariants.t.sol` (3 invariants, 8,192 calls each)  | 3       |
| `DemoDistributorInvariants.t.sol` (new, 1 invariant, 8,192 calls) | 1       |
| `MonadMainnetTopologyForkTest` (new, requires network)            | 11      |
| `PancakeV2Adapter.fork.t.sol` (requires network)                  | 2       |
| **Total**                                                         | **152** |

## Dependency audit finding (pre-existing, out of this phase's contract-security scope)

`pnpm audit` surfaced **39 vulnerabilities** (7 high, 29 moderate, 3 low), almost
entirely from `apps/api`'s `hono` dependency being multiple major/minor versions
behind its patched releases (authorization bypass, JWT algorithm confusion, CORS
origin reflection, and others - each individually documented with its own advisory
URL in the raw `pnpm audit` output). **This predates Phase 7 and is unrelated to any
contract in this phase's scope** (`SweepExecutor`, adapters, `SweepPlanLib`, Permit2
integration, `DemoDistributor`) - `apps/api` is a separate, not-yet-security-reviewed
application package. Recorded here for visibility rather than silently omitted;
**not fixed in this pass**, since upgrading `hono` is a distinct change with its own
testing burden outside this phase's stated component list, and the operating rules
for this phase are scoped to contract security verification, not `apps/api` hardening.
Flagged as a recommended follow-up, not a Phase 7 P0/P1/P2/P3 finding (which are
reserved for the in-scope contracts).

## Reproducing this entire log

```bash
cd /Users/mac/tidyr
pnpm install --frozen-lockfile
pnpm format
pnpm lint
pnpm typecheck
pnpm build
pnpm test
bash scripts/scan-secrets.sh
pnpm audit

cd packages/contracts
forge fmt --check
forge clean
forge build
forge test -vvv
forge test --match-test "testFuzz_" --fuzz-runs 10000 -vv
forge test --match-contract "SweepExecutorInvariantsTest|DemoDistributorInvariantsTest" -vv
forge test --match-contract "MonadMainnetTopologyForkTest|PancakeV2AdapterForkTest"
forge coverage --no-match-path "*.fork.t.sol" --ir-minimum --report summary
forge snapshot
slither . --exclude-dependencies
```
