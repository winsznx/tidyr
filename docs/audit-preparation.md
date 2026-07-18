# Audit Preparation — Phase 7 Task 7.1

A practical entry point for an external auditor (human or a fresh-session adversarial
Claude review) picking up this repository. Points to the evidence rather than
restating it.

## Where to start

1. **Architecture and security model:** `docs/security-model.md` (defensive
   mechanisms), `docs/threat-model.md` (threat-to-defense mapping with residual
   risks honestly stated), `docs/approval-architecture.md` (approval/spender safety
   specifically).
2. **The core contract:** `packages/contracts/src/SweepExecutor.sol` - read its
   contract-level doc comment first; it explains the closed-adapter-set design (RA-01
   remediation) and the follow-up constructor/freeze hardening in the auditor's own
   words, not just this document's paraphrase.
3. **What changed and why, in order:** `PROJECT_STATUS.md`'s phase-by-phase log (each
   phase section states objective, files, commands run, and results - not just
   claims), then `docs/security-addendum-review.md` (the original security addendum
   plus its RA-01 remediation addendum plus follow-up hardening section).
4. **Prior independent audit history:** `audit/codex-addendum-audit.md` (original,
   CA-01 through CA-10), `audit/codex-addendum-reaudit.md` (RA-01 through RA-05,
   found the first CA-01 fix insufficient) - both are external, independently-authored
   audit records, not self-assessments. Cross-reference against
   `artifacts/security-addendum/findings.md` for the disposition of each finding.

## Phase 7's own evidence (this pass)

| Artifact                                                     | What it contains                                                                                                                   |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `artifacts/security/findings.md`                             | The Phase 7 finding register - every genuine issue found this pass, with reproduction/root-cause/fix/regression-test/residual-risk |
| `artifacts/security/test-summary.md`                         | Full validation command log with exact exit codes and counts                                                                       |
| `artifacts/security/fuzz-report.md`                          | Fuzz properties and actual run counts (including 10,000-run critical-property runs)                                                |
| `artifacts/security/invariant-report.md`                     | Invariants, exact configuration, runs/depth/calls                                                                                  |
| `artifacts/security/fork-report.md`                          | Mainnet-fork verification results and any provider limitations encountered                                                         |
| `artifacts/security/slither-report.md` + `slither-triage.md` | Every Slither finding, individually triaged (no blanket suppression)                                                               |
| `artifacts/security/gas-report.md`                           | Gas at plan-shape extremes, DoS analysis                                                                                           |
| `artifacts/security/coverage-report.md`                      | Branch coverage, explicitly mapped to security-sensitive areas                                                                     |
| `artifacts/security/manual-review.md`                        | Line-by-line CEI/reentrancy/nonce/hash/route/ownership/freeze/recovery review                                                      |
| `PHASE_7_SECURITY_COMPLETION_REPORT.md`                      | The completion gate checklist and final counts                                                                                     |

## How to independently re-verify (don't take any of the above on faith)

```bash
cd packages/contracts
forge build && forge test                                     # deterministic + invariant suite
forge test --match-contract MonadMainnetTopologyForkTest       # requires network access
forge test --match-contract PancakeV2AdapterForkTest            # requires network access
slither . --exclude-dependencies                                # exit 255 is normal (findings present, not a crash) - see slither-report.md
forge coverage --no-match-path "*.fork.t.sol" --ir-minimum --report summary
forge snapshot
cd /Users/mac/tidyr
pnpm install --frozen-lockfile && pnpm format && pnpm lint && pnpm typecheck && pnpm build && pnpm test
bash scripts/scan-secrets.sh
```

## What this phase deliberately did not do

- **No deployment.** No `--broadcast`, no testnet/mainnet transaction, no
  `deployments/mainnet.json` entries created. Phase 8/9 remain untouched.
- **No frontend.** `apps/web` was not created or modified.
- **No weakening of any existing test.** Every pre-existing passing test still
  passes; the six CA-01-era tests removed in the prior RA-01 remediation session
  were replaced with stronger tests proving the new architecture directly (documented
  in `PROJECT_STATUS.md`), not simply deleted - Phase 7 itself removed zero tests and
  only added/strengthened.
- **No blanket Slither suppression.** Every finding has its own individual triage
  entry.

## Known limitations of this review, stated plainly

- **No wallet-level transaction-review boundary exists yet** (Phase 11 work) - this
  is the single largest residual risk carried forward, not resolved by Phase 7
  (contract-side verification cannot fix a UI-layer trust gap).
- **Deployment-integrity trust boundary** (a compromised deployer wiring a malicious
  contract into an adapter slot) cannot be closed by Solidity code alone - mitigated
  by the strengthened Phase 9 gate, not eliminated.
- **Two coverage-tool anomalies** (`UniswapV3Path.sol`'s branch coverage,
  `DemoDistributor.sol`'s two flagged lines) are documented in
  `artifacts/security/coverage-report.md` as likely `--ir-minimum` instrumentation
  limitations, backed by direct source-code call-chain tracing showing the flagged
  code is in fact reached by passing tests - not asserted without that backing
  evidence.
- **Monad's own block gas limit was not independently re-verified** as part of the
  gas report (`artifacts/security/gas-report.md` notes this explicitly) - the 3.6M
  gas worst-case measurement should be checked against live Monad data before Phase 9.
