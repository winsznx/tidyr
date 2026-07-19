# TIDYR — Security

TIDYR's contracts move real user funds on Monad mainnet. This document is the
short, root-level summary of the security model, the verification that was
actually performed, and where to find full detail. It is a summary, not a
substitute — every claim below is backed by a real artifact linked at the end.

## Scope

`SweepExecutor`, `PancakeV2Adapter`, `UniswapV3Adapter`, `SweepPlanLib`,
`TidyrWitness`, the Permit2 integration, and `DemoDistributor` —
`packages/contracts/src/`. All three core contracts are **immutable,
non-upgradeable, and permanently frozen** on Monad mainnet as of Phase 10
(`configurationFrozen() == true` on all three; no `unfreeze` exists).

## Defensive design (summary — full detail in `docs/security-model.md`)

1. **Closed adapter set, no registry.** `SweepExecutor` resolves every swap to
   one of exactly two immutable addresses fixed at construction. A plan can
   only select `AdapterKind.PANCAKE_V2` or `AdapterKind.UNISWAP_V3` — there is
   no way to name an arbitrary adapter address, and Solidity's ABI decoder
   itself rejects any out-of-range enum ordinal before execution begins.
2. **Never trust adapter return values.** Every swap's actual output is
   measured as a balance delta (before/after), never taken from what the
   adapter claims it returned.
3. **Exact, single-use approvals.** Each adapter is approved for exactly
   `amountIn` immediately before its call and reset to zero immediately after
   — never a standing or unlimited approval.
4. **Total Permit2 witness binding.** Every field that matters for
   authorization — owner, recipient, outputToken, deadline, nonce, and every
   action including `adapterKind`/`routeData`/`minAmountOut` — plus `chainId`
   and the executor's own address, is bound into a single
   `executionPlanHash`, itself bound into the signed Permit2 witness. Changing
   any single field invalidates the signature entirely.
5. **Plan-fund isolation.** Every token a plan touches is balance-snapshotted
   immediately before the Permit2 pull; all downstream accounting is a delta
   against that baseline, so pre-existing or stray balances can never be
   attributed to a plan.
6. **Shared reentrancy guard** across `executeSweep` and `recoverStrayTokens`
   — stray-fund recovery can never run mid-execution.
7. **Irreversible configuration freeze**, coupled to both adapters' own freeze
   state — a "frozen" executor can't keep routing through an adapter whose own
   routing surface an owner could still change.
8. **Constructor-time validation** of immutable dependencies (rejects zero
   address, EOAs, duplicate adapters).
9. **Two structurally distinct hashes** — `executionPlanHash` (what Permit2
   actually authorizes) and `displayManifestHash` (what a wallet UI shows a
   user) — proven never to collide for the same plan, so a signed plan and its
   human-readable summary can't silently diverge.
10. **No delegatecall, no proxies, no arbitrary call target.** Every external
    call surface from `SweepExecutor` is enumerable: the two fixed adapters'
    `swap()`, Permit2's `permitWitnessTransferFrom`, ERC-20
    `transfer`/`transferFrom`/`approve` on plan-specified tokens, a native MON
    send to `plan.recipient`, and WMON's `withdraw`. No generic
    `Call{target, callData}` structure exists anywhere.

## Verification performed (real, reproduced numbers)

| Check | Result |
| --- | --- |
| Solidity tests | 152/152 pass |
| TypeScript tests | 30/30 pass |
| Fuzz properties | 4 properties × 10,000 runs each, all pass |
| Invariants | 4 invariants × 8,192 calls each, 0 reverts |
| Fork tests against live Monad mainnet | 13/13 pass (read-only, `vm.createSelectFork`, never broadcast) |
| Slither | 37 findings reproduced; 0 unresolved critical/high after manual triage (false positives or already-tested-and-mitigated) |
| Branch coverage | `SweepExecutor` 93.55%, `PancakeV2Adapter` 92.31%, `UniswapV3Adapter` 100% |
| Max-action gas | 3,605,566 gas for the worst-case 50-distinct-token plan |
| P0 / P1 findings outstanding | 0 / 0 |

## Independent adversarial audit

Beyond the primary verification pass, a separate, independent adversarial
audit (`audit/phase-7-adversarial-audit.md`) explicitly treated every prior
claim above as unverified and re-derived it from source and live command
output rather than trusting the completion report. Its verdict:
**CONDITIONAL PASS** — zero P0/P1 findings, all 20 requirements-brief claims
independently re-verified, five P3 documentation-accuracy nits found (none
touching contract logic, fund safety, or the authorization boundary). Full
finding-by-finding detail: `audit/phase-7-adversarial-audit.md`,
`audit/phase-7-adversarial-findings.json`, `audit/phase-7-requirements-matrix.md`,
`audit/phase-7-command-log.md`.

## Independently reproducible checks

```bash
cd packages/contracts
grep -rn "delegatecall" src/     # expect: only doc comments stating its absence
grep -rn "struct Call\b" src/    # expect: no matches
forge test                       # expect: 152/152
```

## Known, honestly-stated residual risk

- **Deployment bytecode trust.** The constructor narrows which addresses can
  occupy the two immutable adapter slots, but cannot itself prove the
  deployed bytecode is the audited adapter source. This is closed at the
  deployment-process level (bytecode/constructor-argument/immutable-dependency
  verification), documented in `docs/requirements-traceability.md`.
- **Frontend simulation, not a full pre-signature `executeSweep` staticcall.**
  The Review step (`apps/web`) simulates the DEX leg of a sell via a real
  on-chain quoter call and re-checks live preconditions (nonce, deadline,
  allow-listing), but cannot staticcall `executeSweep` itself before a
  signature exists (Permit2 verification would simply revert with no
  signature to check). The full `executeSweep` staticcall runs at the
  Execute step, after a real signature exists and before broadcast — see
  `ARCHITECTURE.md`.
- **No permanent event indexer.** The Report step reconstructs outcomes from
  a locally persisted transaction record or a bounded recent-block log scan;
  a manifest whose transaction falls outside both is reported as genuinely
  "not found," not fabricated.

## Reporting a vulnerability

This is a hackathon-stage project without a dedicated disclosure program yet.
If you find a security issue, open a GitHub issue marked clearly as a
security concern, or reach the maintainer directly if the issue is sensitive
enough that public disclosure before a fix would be harmful.

## Full documentation

- `docs/security-model.md` — the full architectural summary this file condenses
- `docs/threat-model.md` — per-threat asset/entry-point/defense/test-evidence mapping
- `docs/approval-architecture.md` — approval/spender-safety-specific detail
- `PHASE_7_SECURITY_COMPLETION_REPORT.md` — the full primary verification report
- `audit/` — the independent adversarial audit and its supporting artifacts
- `artifacts/security/` — raw evidence (test summaries, Slither triage, fork/gas/coverage reports)
