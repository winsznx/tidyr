# TIDYR — Architecture

Status: reflects the system as actually built and deployed, not the original
PRD's aspirational plan. Where this document differs from `tidyr-production-prd.md`,
this document is authoritative for what exists today; the PRD describes the
longer-term target.

## What actually exists today

| Layer                         | Status                                                                                                                       | Where                                                                          |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Smart contracts               | **Real, deployed, frozen** on Monad mainnet (chain 143)                                                                      | `packages/contracts/`, `deployments/mainnet.json`                              |
| Frontend                      | **Real, chain-only, staging-deployed**                                                                                       | `apps/web/`, live at the Railway staging URL in `STAGING_DEPLOYMENT_REPORT.md` |
| Backend API                   | **Stub only** — a single `/health/live` route, no business logic                                                             | `apps/api/`                                                                    |
| Indexer                       | **Stub only**                                                                                                                | `apps/indexer/`                                                                |
| `packages/routing`            | **Stub only** — the frontend implements its own thin, chain-only route-candidate reads instead (`apps/web/src/lib/routing/`) | `packages/routing/`                                                            |
| `packages/execution`          | **Stub only** — no execution wiring exists yet anywhere                                                                      | `packages/execution/`                                                          |
| `packages/shared`             | Real — plan/action Zod schemas, `MON_NATIVE_SENTINEL`, adapter-kind enum, mirrored exactly from the Solidity source          | `packages/shared/`                                                             |
| `packages/transaction-review` | Real — RFC 8785 canonical manifest hashing and Solidity-matching `executionPlanHash`, golden-vector tested                   | `packages/transaction-review/`                                                 |

This gap between "PRD-envisioned" and "actually built" is intentional and
documented at each decision point — see `docs/frontend-integration-matrix.md`
§0 and `FRONTEND_CHECKPOINT_REPORT.md` for the recalibration that formalized
it: build a real, honest chain-only frontend now rather than fabricate a
backend that doesn't exist.

## Contract layer (real, deployed, frozen)

```
Monad mainnet (chain 143)
┌────────────────────────────────────────────────────────────────┐
│  SweepExecutor  (immutable adapter addresses, frozen)          │
│    ├── PancakeV2Adapter   (frozen)                              │
│    └── UniswapV3Adapter   (frozen)                              │
│  DemoDistributor  (200 DUST1-5 per address, one claim each)     │
│  DUST1..DUST5     (fixed-supply demo tokens; DUST4 is burnable) │
└────────────────────────────────────────────────────────────────┘
```

- **Closed adapter model**: `SweepExecutor`'s constructor fixes exactly two
  adapter addresses. There is no registry and no admin call that can add a
  third. A plan can only select `AdapterKind.PANCAKE_V2` or
  `AdapterKind.UNISWAP_V3` — never an arbitrary address.
- **Permit2 witness binding**: every `executeSweep` call is authorized by a
  Permit2 `SignatureTransfer` witnessed to a specific `executionPlanHash`. A
  signature for one plan cannot be replayed against a different plan, chain,
  or executor deployment.
- **Frozen since Phase 10**: `SweepExecutor`, `PancakeV2Adapter`, and
  `UniswapV3Adapter` are all permanently frozen (`configurationFrozen() ==
true` on all three). The output-token set (native MON + canonical USDC)
  and both adapter identities are now immutable forever — see
  `PHASE_10_COMPLETION_REPORT.md` for the exact freeze transactions.
- Full security verification (fuzzing, invariants, adversarial mocks, fork
  tests, Slither triage, manual review, an independent adversarial audit) is
  in `PHASE_7_SECURITY_COMPLETION_REPORT.md` and `docs/threat-model.md`.

## Frontend layer (real, chain-only)

```
apps/web (Next.js 15, App Router)
┌──────────────────────────────────────────────────────────────┐
│  Landing (/)  — marketing page, real contract addresses,      │
│                 illustrative (labeled) product preview        │
│  Workspace (/app/*)                                            │
│    ├── Wallets     — connect / watch-only, live MON balance,   │
│    │                 EIP-7702 delegation check (real on-chain  │
│    │                 read, not assumed)                        │
│    ├── Inventory   — multicall balance reads over known +      │
│    │                 manually-tracked tokens (no indexer)      │
│    ├── Planning    — Sell/Consolidate/Discard/Burn gated on    │
│    │                 real "route candidate" reads              │
│    ├── Review      — placeholder (paused, see below)           │
│    ├── Execute     — placeholder (paused, see below)           │
│    └── Report      — placeholder (paused, see below)           │
│  Demo (/demo), Security (/security), Contracts (/contracts)    │
└──────────────────────────────────────────────────────────────┘
        │ direct viem/wagmi reads — no custom backend
        ▼
Monad mainnet (chain 143)
```

Everything the frontend shows is either a live chain read (via `viem`
multicall / `wagmi`) or an explicitly-labeled illustrative value on the
marketing page only. Nothing is fabricated. Where a real capability would
require a backend that doesn't exist (indexed event history, aggregated
pricing, off-chain simulation), the UI shows an honest degraded/unavailable
state instead of faking it — see `docs/frontend-integration-matrix.md`.

**Review, Execute, and Report are intentionally paused** — no Permit2
signing, no `executeSweep` call, no calldata decoding, and no event-log
report reconstruction exist anywhere in `apps/web` yet. This is a deliberate
recalibration (`FRONTEND_CHECKPOINT_REPORT.md`), not an oversight: those
surfaces depend on backend services (routing/pricing, exact-wallet
simulation, execution monitoring, indexed reports) that must be built first,
not improvised inside React components.

## Package boundaries

| Package                       | Responsibility                                                                                                        | Must NOT do                                                                |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `packages/contracts`          | Foundry workspace: SweepExecutor, adapters, demo tokens, distributor, deploy/verify scripts, full test suite          | Hold logic that belongs in TS packages                                     |
| `packages/shared`             | Deployed addresses (generated from `deployments/mainnet.json`), Zod schemas, adapter-kind enum, `MON_NATIVE_SENTINEL` | Import server secrets                                                      |
| `packages/transaction-review` | Canonical manifest hashing (`displayManifestHash`), Solidity-matching `executionPlanHash`                             | Diverge from `SweepPlanLib.hashPlan`'s exact encoding                      |
| `packages/routing`            | Stub — real routing logic lives in `apps/web/src/lib/routing/` until a real backend package replaces it               | —                                                                          |
| `packages/execution`          | Stub — no execution wiring exists anywhere yet                                                                        | —                                                                          |
| `apps/api`                    | Stub — a single liveness route                                                                                        | Business logic (not yet built)                                             |
| `apps/indexer`                | Stub                                                                                                                  | Event ingestion (not yet built)                                            |
| `apps/web`                    | The only real, user-facing surface today                                                                              | Fabricate backend-dependent data; sign or broadcast anything (F11+ paused) |

## Data flow today (chain-only, no backend)

1. **Wallet connect** (`apps/web`, wagmi): injected connector or a manually
   entered watch-only address; Monad chain (143) enforced.
2. **Scan** (`apps/web`, viem multicall): balances for the 5 deployed demo
   tokens plus any user-tracked address — never a full arbitrary-wallet
   index, since no indexer exists.
3. **Route candidate check** (`apps/web`, live reads): queries
   `SweepExecutor.allowedOutputTokens` and both the Uniswap V3 and Pancake V2
   factories directly. This proves a pool/pair _exists_ — it is explicitly
   not a claim that a token is executable-sellable (`docs/frontend-integration-matrix.md` §0.5).
4. **Plan** (`apps/web`, local Zustand state): inert — assigning an action
   writes to local state only; nothing downstream consumes it yet.
5. _(Review → Sign → Execute → Report: paused, see above.)_

## Deployment record

`deployments/mainnet.json` is the single source of truth for every contract
address, dependency address, deployment transaction, source-verification
status, and — since Phase 10 — the freeze transactions and final
`configurationFrozen` state. `apps/web/src/lib/deployment.generated.ts` is
generated from it (`apps/web/scripts/generate-deployment-config.mjs`) — no
component ever hardcodes a `0x...` literal.

## Infrastructure

- **Contracts**: Monad mainnet, chain 143, RPC `https://rpc.monad.xyz`.
- **Frontend**: Railway (Nixpacks builder), staging environment — see
  `STAGING_DEPLOYMENT_REPORT.md` for the live URL and configuration. No
  backend services are deployed (there's nothing real to deploy yet).
- **Secrets**: `DEPLOYER_PRIVATE_KEY` lives only in the gitignored,
  untracked `.env.deploy` used for one-time deployment/admin transactions —
  never in any Railway service's environment.
