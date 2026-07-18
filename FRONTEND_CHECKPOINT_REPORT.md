# TIDYR Frontend — Pre-Execution Checkpoint Report

Branch: `frontend/production-lifecycle`
Tag: `frontend-pre-execution-checkpoint`
Baseline (protocol side): `security/phase-7-verification` @ `2f47b34` (Phase 9
mainnet deployment + USDC output-token registration), plus the fork-only
Phase 10 route-simulation commit `5c05cbe`.

This report exists because the F0 discovery already found (and the recalibration
instruction re-confirmed) that the backend, routing, indexer, PriceService, and
execution-state packages the frontend brief assumes are real, production
implementations do not exist yet. This checkpoint stops frontend work at the
boundary before those responsibilities would otherwise have been improvised
inside React components.

## 1. Verification (run at checkpoint time)

| Check                         | Result                                                                                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch                        | `frontend/production-lifecycle`                                                                                                                                                                         |
| Working tree                  | Clean except untracked files under `apps/web/public/` (brand assets dropped in externally, not created by this work and not committed as part of this checkpoint)                                       |
| Commits on this branch        | 8 feature/doc commits + 4 tsbuildinfo/gitignore hygiene fixes, all present (see `git log`)                                                                                                              |
| `pnpm typecheck` (repo-wide)  | Pass — all 7 workspace packages incl. `apps/web`                                                                                                                                                        |
| `pnpm run build` (`apps/web`) | Pass — 17 routes, static where possible                                                                                                                                                                 |
| `pnpm lint` (repo-wide)       | Pass, zero errors/warnings in `apps/web` source                                                                                                                                                         |
| Dev-server smoke test         | All routes (`/`, `/app`, `/app/wallets`, `/app/review`, `/app/execute`, `/app/report/[hash]`, `/demo`, `/security`, `/contracts`, OG/icon/manifest/robots/sitemap routes) return 200, no console errors |

## 2. Implemented scope (real, verified)

- **F0** — integration matrix, architecture doc, state-machine doc. Documents
  the stub status of `apps/api`, `apps/indexer`, `packages/routing`,
  `packages/execution`, and the absence of `FRONTEND_HANDOFF.md`.
- **F1** — design system primitives (Button, Card, Badge, Input, Dialog,
  AddressText, Skeleton, EmptyState, ErrorState, layout primitives, brand
  Wordmark/PixelField) from `internal/design.md`.
- **F2** — full landing page with the specified hero copy/CTAs, illustrative
  (labeled, non-live) product preview, contracts table reading live addresses
  from `deployments/mainnet.json`.
- **F3** — metadata, code-generated OG/Twitter images, favicon, robots,
  sitemap, manifest, and `docs/frontend-asset-requests.md`.
- **F4** — responsive app shell (rail nav desktop / top nav mobile), all core
  routes wired into the shell.
- **F5** — multi-wallet workspace: connect-or-watch-only add flow, address
  validation, duplicate detection, primary-wallet selection, live MON
  balance, genuine on-chain EIP-7702 delegation check.
- **F6** — three separated Zustand stores (wallets, plan, execution) with the
  documented storage policy enforced in code (plan state is never persisted;
  execution state persists only tx hashes + coarse status; wallet state
  persists only address/label/watchOnly/isPrimary).
- **F7–F9 (partial — see §3 for exact boundary)** — live balance scanning via
  multicall against **known and manually tracked assets** (not arbitrary
  wallet-wide discovery), a **route-candidate** check against the real
  Uniswap V3/Pancake V2 factories and `SweepExecutor.allowedOutputTokens`,
  and inert local-only action assignment (writes to the plan store; nothing
  downstream consumes it yet).

## 3. Exact incomplete / narrower-than-brief scope

- **Token discovery** is "known and manually tracked assets" — the 5 deployed
  demo tokens plus user-added addresses via `AddTokenDialog`. There is no
  indexer, so a wallet's complete arbitrary ERC-20 holdings cannot be
  enumerated. This is unchanged from the F0 decision, restated here in the
  required wording.
- **`hasRouteToMon` is a route candidate, not `canSell`.** It proves a pool/
  pair exists. It does not fetch a fresh executable quote, does not compute
  `minAmountOut`, and does not run an exact-wallet simulation. No code path in
  this repository sets or implies `canSell = true`. UI copy was corrected in
  this checkpoint (`token-row.tsx`: "Route candidate: …" / "No route
  candidate found"; action label "Sell (route candidate)").
- **Revoke, Top-up, Multi-send** — not implemented. Correctly absent from the
  planner rather than stubbed with fake data.
- **F11–F14 — not started.** `/app/review`, `/app/execute`,
  `/app/report/[manifestHash]` render static `EmptyState` placeholders naming
  the exact pending work. Nothing in `apps/web` creates a manifest hash,
  execution-plan hash, Permit2 signature, or `executeSweep` call. No calldata
  decoding, no simulation, no execution monitoring, no report reads events.
- **F15–F20 — not started** (demo lifecycle beyond a static info page,
  loading/empty/error state hardening pass, accessibility pass, test suite,
  performance/security hardening, Railway deployment).

## 4. Phase 10 (protocol side) — status and remaining broadcasts

Per the fork-only proof already completed (`packages/contracts/script/
Phase10RouteSimulation.s.sol`, `test/Phase10RouteSmoke.fork.t.sol`, both on
`security/phase-7-verification`):

- Route architecture (DUST3 → WMON → USDC via UniswapV3Adapter's native
  multihop) is **proven on a fork**, not yet on real mainnet.
- Remaining real-mainnet broadcasts, none yet sent: WMON deposit, DUST3/WMON
  Uniswap V3 pool creation + initialization, liquidity mint, one small real
  smoke sweep, recording results in `deployments/mainnet.json`, then — only
  after that smoke sweep is verified — simulating and broadcasting
  `freezeConfiguration()`.
- No mainnet transaction will be sent without a full confirmation packet
  (target, selector, decoded calldata, amounts, fee tier, price, liquidity
  range, minAmountOut, deadline, gas, deployer balance, retained reserve,
  expected state change) and explicit approval first, per the standing
  confirmation-checkpoint pattern used for every prior mainnet action this
  session.

**This work is not resumed in this response** — it belongs on the protocol/
deployment side (`security/phase-7-verification` or a follow-on branch), not
`frontend/production-lifecycle`, and requires a separate go-ahead before any
broadcast.

## 5. Proposed backend branch baseline (not created yet)

`backend/production-services`, branched from `main` after Phase 10 + freeze
are complete and merged, would implement the six required service areas
(dynamic asset discovery, capability assessment, routing/pricing, transaction
preparation, exact-wallet simulation, execution monitoring, finalized
reports) with a real OpenAPI schema and generated clients — not created in
this response, pending the sequencing decision below.

## 6. Backend implementation plan (proposed, not started)

1. Dynamic asset discovery service (indexer or provider-backed balance/
   metadata enumeration + Multicall3 verification), with manual-address
   fallback preserved as a degraded mode.
2. Capability assessment (`canTransfer`/`canSell`/`canBurn`/
   `hasKnownLiquidity`/`simulationStatus`/`riskReasons`) computed server-side
   from live quote + simulation results, not inferred client-side.
3. Routing/pricing: Pancake V2 + Uniswap V3 (single-hop and multihop), fresh
   executable quotes with `minAmountOut`/deadline/price impact, plus a Pyth
   MON/USD and USDC/USD reference for `executableValueUsd` display only
   (never substituting for `minAmountOut`).
4. Transaction preparation: manifest generation, `displayManifestHash`,
   Solidity-matching `executionPlanHash` (must match `SweepPlanLib.hashPlan`
   exactly — golden-vector tested against `packages/transaction-review`),
   Permit2 witness payload, calldata encode + decode-and-compare.
5. Exact-wallet simulation: real sender, real calldata, real native value,
   balance-delta inspection, unexpected target/recipient/spender/amount
   detection.
6. Execution monitoring: submitted-hash tracking, replacement handling,
   finalized-status polling with no automatic resubmission.
7. Finalized reports from indexed events/receipts, with a shareable report
   identifier.
8. OpenAPI schema + generated TypeScript client consumed by `apps/web`,
   replacing the chain-only `lib/routing`, `lib/tokens`, `lib/review` (once
   built) modules currently marked as temporary in
   `docs/frontend-architecture.md`.

## 7. F11–F14 features that remain blocked

All of them, pending the backend acceptance gates in the recalibration
instruction: arbitrary wallet token discovery, `canSell` requiring quote +
simulation, canonical transaction builders outside React components,
Solidity/TypeScript execution-hash parity testing, tested Permit2 typed-data
generation, calldata decode-and-compare, exact-wallet simulation, resumable
execution monitoring, chain-evidence-based finalized reports, and generated/
tested API schemas and clients.

## 8. Is it safe to proceed with the first Phase 10 confirmation packet?

Not from this response — Phase 10 broadcasting is protocol/deployment work
on a different branch (`security/phase-7-verification` or a follow-on), and
this checkpoint is scoped to the frontend branch only. The next action, if
authorized, is switching to the protocol branch and producing the full
confirmation packet described in §4 before any broadcast — not something to
begin automatically here.
