# TIDYR Implementation Plan (Pre-Frontend)

This restates the phase sequence from the operating instructions with verified
dependencies and phase-local acceptance gates. PRD §19.19's ordered deployment sequence
is binding for Phases 8–10 specifically; this document is the broader phase map including
the surrounding engineering work.

| Phase      | Deliverable                                                                                      | Depends on                                       | Gate before next phase                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ---------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0          | Research docs, architecture, traceability matrix, risk register (this set)                       | PRD read                                         | Committed to `build/pre-frontend-production`                                                                                                                                                                                                                                                                                                                                                                                                  |
| 1          | pnpm monorepo scaffold, Foundry workspace, CI config, `.env.example`                             | Phase 0                                          | Fresh install + build succeeds; no secrets tracked                                                                                                                                                                                                                                                                                                                                                                                            |
| 2          | Action structs (no executor-side revoke), display/execution hash implementations, golden vectors | Phase 1                                          | JS/Solidity hashes match on shared vectors; distinctness proven                                                                                                                                                                                                                                                                                                                                                                               |
| 3          | Permit2 witness binding to `executionPlanHash`                                                   | Phase 2                                          | Modified-plan / reused-nonce / wrong-spender / expired tests pass                                                                                                                                                                                                                                                                                                                                                                             |
| 4          | SweepExecutor core                                                                               | Phase 2/3                                        | Unit+fuzz+invariant suite green                                                                                                                                                                                                                                                                                                                                                                                                               |
| 5          | PancakeV2Adapter (direct pair, per conflict C-1) + UniswapV3Adapter                              | Phase 4                                          | Adapter-level malicious-path/output/expiry tests green                                                                                                                                                                                                                                                                                                                                                                                        |
| 6          | Demo tokens + DemoDistributor                                                                    | Phase 4                                          | Claim/burn/no-pool tests green                                                                                                                                                                                                                                                                                                                                                                                                                |
| 7          | Security hardening: fuzz/invariant/fork, Slither, gas snapshot, threat model docs                | Phase 4–6                                        | No unresolved critical/high finding                                                                                                                                                                                                                                                                                                                                                                                                           |
| 8          | Mainnet deployment tooling + preflight (no broadcast)                                            | Phase 7                                          | **Stop gate** — explicit user approval required before Phase 9                                                                                                                                                                                                                                                                                                                                                                                |
| 9          | Mainnet contract deployment                                                                      | Phase 8 + user approval + `DEPLOYER_PRIVATE_KEY` | All addresses verified, ownership transferred                                                                                                                                                                                                                                                                                                                                                                                                 |
| 10         | Demo liquidity + smoke tests                                                                     | Phase 9                                          | Every tradable DUST has proven live sell path; DUST5 honestly unlisted                                                                                                                                                                                                                                                                                                                                                                        |
| 11         | `packages/shared`, `packages/routing`, `packages/transaction-review`                             | Phase 2/3 (types), Phase 9 (real addresses)      | Schema/degraded-state tests green; **mandatory addition (security addendum, 2026-07-17): the approval/transaction-calldata builder must reject Multicall3's verified address (`0xcA11bde05977b3631167028862bE2a173976CA11`) as a spender, adapter, router, or write-call target, with a test named `approvalBuilder_rejectsMulticall3AsSpender` (or equivalent) — no such builder exists yet, so this cannot be satisfied before this phase** |
| 12         | `apps/api`                                                                                       | Phase 11                                         | Endpoint integration tests green (fixtures until live keys supplied)                                                                                                                                                                                                                                                                                                                                                                          |
| 13         | `apps/indexer`, Postgres schema, report reconstruction                                           | Phase 9 (real events), Phase 12 (shared schema)  | Idempotency/restart tests green                                                                                                                                                                                                                                                                                                                                                                                                               |
| 14         | `packages/execution` multi-wallet scheduler                                                      | Phase 11                                         | Concurrency/failure-isolation/reserve tests green                                                                                                                                                                                                                                                                                                                                                                                             |
| 15         | Railway service configuration                                                                    | Phase 12–14                                      | Config committed; deploy only if Railway auth present                                                                                                                                                                                                                                                                                                                                                                                         |
| 16         | ERC-7730 descriptors, documentation, `FRONTEND_HANDOFF.md`                                       | Phase 9 (addresses), all prior                   | Handoff doc complete                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Final gate | `PRE_FRONTEND_COMPLETION_REPORT.md`                                                              | All phases                                       | All 23 release-gate items checked or documented blocker                                                                                                                                                                                                                                                                                                                                                                                       |

## Mandatory Phase 11/12 acceptance gates (security addendum, added after Codex audit findings CA-05/CA-06)

The design docs `docs/pricing-and-oracle-model.md` and `docs/token-support-model.md`
describe _intent_ for Phase 11/12. An independent audit (2026-07-17) correctly found
that intent alone is not a formal gate — a later phase could satisfy "schema/
degraded-state tests green" (Phase 11's stated gate) without actually implementing the
promised boundaries. These are now explicit, named acceptance criteria Phase 11/12 must
satisfy before either phase can be marked complete:

**PriceService / oracle (CA-05):**

- a named test proving `minAmountOut` enforcement is fully independent of any oracle
  value (an oracle outage or a manipulated oracle price must not change swap execution
  safety);
- a named test proving stale oracle data (publish time beyond a defined freshness
  window) is rejected for display purposes, not silently shown as current;
- a named test proving low-confidence oracle data is flagged, not silently treated as
  precise;
- a named test proving "executable value" (quote x oracle reference) is computed from
  the _same_ quote used for execution, not a separately-fetched value that could diverge.

**Generic/dynamic token support (CA-06):**

- a named test proving a manually-entered arbitrary ERC-20 address (not one of
  DUST1-DUST5, not previously discovered by the indexer) reaches full capability
  assessment;
- a named test proving the five demo-token addresses are _not_ used anywhere as a
  production input-token filter or allowlist — i.e. a wallet holding only non-demo
  tokens is fully assessable and sweepable.

Phase 11/12 is not complete until these tests exist and pass, in addition to whatever
schema/degraded-state coverage was already planned.

## Immediate next actions (Phase 1)

1. Scaffold `pnpm-workspace.yaml`, root `package.json` (lint/typecheck/test/build/format scripts).
2. Scaffold `packages/contracts` as a Foundry project; pin `solc 0.8.26` and OZ v5 per PRD §19.11.
3. Pin `viem`, `wagmi`, `foundry` toolchain versions.
4. `.env.example` mirroring PRD §19.18's variable list, no real values.
5. `.gitignore` covering `.env*`, `out/`, `cache/`, `node_modules/`, `broadcast/` (Foundry deployment artifacts can contain sensitive tx data before redaction).
6. CI workflow: contracts (forge build/test) + TypeScript packages (typecheck/lint/test) as separate jobs.
7. Minimal compile-safe `apps/web` only if the workspace/Railway wiring requires a placeholder package — no product screens.

## Stop conditions honored throughout

- Phase 8→9 boundary: explicit user approval required before any mainnet transaction.
- Any required secret (`DEPLOYER_PRIVATE_KEY`, `MORALIS_API_KEY`, `TENDERLY_*`,
  `ZEROX_API_KEY`, Railway auth) is requested as "place this in `.env.deploy` / Railway
  variables locally," never requested as literal chat input.
- A real technical contradiction (see traceability matrix conflict log) pauses only the
  specific implementation detail affected, not the whole phase, once resolved and recorded.
