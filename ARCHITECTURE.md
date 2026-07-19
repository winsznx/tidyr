# TIDYR — Architecture

Status: reflects the system as actually built and deployed, not the original
PRD's aspirational plan. Where this document differs from `tidyr-production-prd.md`,
this document is authoritative for what exists today; the PRD describes the
longer-term target.

## What actually exists today

| Layer                         | Status                                                                                                                       | Where                                                                          |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Smart contracts               | **Real, deployed, frozen** on Monad mainnet (chain 143)                                                                      | `packages/contracts/`, `deployments/mainnet.json`                              |
| Frontend                      | **Real, chain-only, staging-deployed, full sweep flow working end to end**                                                  | `apps/web/`, live at the Railway staging URL in `STAGING_DEPLOYMENT_REPORT.md` |
| Backend API                   | **Stub only** — a single `/health/live` route, no business logic                                                             | `apps/api/`                                                                    |
| Indexer                       | **Stub only** — the frontend reconstructs reports itself, see "Report" below                                                 | `apps/indexer/`                                                                |
| `packages/routing`            | **Stub only** — the frontend implements its own thin, chain-only route-candidate reads instead (`apps/web/src/lib/routing/`) | `packages/routing/`                                                            |
| `packages/execution`          | **Stub only** — the frontend drives execution directly (`apps/web/src/lib/review/`), no shared execution package exists yet  | `packages/execution/`                                                          |
| `packages/shared`             | Real — plan/action Zod schemas, `MON_NATIVE_SENTINEL`, adapter-kind enum, mirrored exactly from the Solidity source          | `packages/shared/`                                                             |
| `packages/transaction-review` | Real — RFC 8785 canonical manifest hashing and Solidity-matching `executionPlanHash`, golden-vector tested                   | `packages/transaction-review/`                                                 |

This gap between "PRD-envisioned backend microservices" and "actually built"
is intentional and documented at each decision point — see
`docs/frontend-integration-matrix.md` §0 and `FRONTEND_CHECKPOINT_REPORT.md`
for the recalibration that formalized it: build a real, honest chain-only
frontend rather than fabricate backend services that don't exist. That
recalibration turned out to be sufficient — the entire review → sign →
execute → report flow below is real and chain-only, with no backend anywhere
in the path.

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
  summarized in `SECURITY.md`, with full detail in
  `PHASE_7_SECURITY_COMPLETION_REPORT.md` and `docs/threat-model.md`.

## Frontend layer (real, chain-only, full sweep flow)

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
│    ├── Review      — real SweepPlan built from live balances/  │
│    │                 quotes, calldata round-trip proof, live   │
│    │                 precondition checks (F11)                 │
│    ├── Sign        — real Permit2 EIP-712 signature per        │
│    │                 wallet, wallet-match guarded (F12)        │
│    ├── Execute     — real eth_call staticcall simulation, then │
│    │                 explicit broadcast + receipt polling (F13)│
│    └── Report      — real SweepCompleted/Transfer log          │
│                       reconstruction, no fabricated result (F14)│
│  Demo (/demo), Security (/security), Contracts (/contracts)    │
└──────────────────────────────────────────────────────────────┘
        │ direct viem/wagmi reads/writes — no custom backend
        ▼
Monad mainnet (chain 143)
```

Everything the frontend shows is either a live chain read/write (via `viem`
multicall, `wagmi` signing/writing) or an explicitly-labeled illustrative
value on the marketing page only. Nothing is fabricated. Where a real
capability would require a backend that doesn't exist (a permanent event
indexer for reports older than the RPC's queryable log-range window,
aggregated pricing across arbitrary tokens), the UI shows an honest
degraded/unavailable state instead of faking it — see
`docs/frontend-integration-matrix.md`.

**Review, Sign, Execute, and Report are real** — no placeholder remains on
any of these routes. A user can add a wallet, plan sell/consolidate/discard/
burn actions, review the exact plan that will execute (with live quotes and
a proven calldata round-trip), sign a real Permit2 message, simulate and
then broadcast a real `executeSweep` transaction, and see a report
reconstructed from that transaction's own on-chain logs. There is
deliberately no permanent indexer: the report page relies on a locally
persisted record of transactions this browser itself broadcast, falling back
to a bounded recent-block log scan, and it says so honestly when a manifest
falls outside both.

## Package boundaries

| Package                       | Responsibility                                                                                                        | Must NOT do                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `packages/contracts`          | Foundry workspace: SweepExecutor, adapters, demo tokens, distributor, deploy/verify scripts, full test suite          | Hold logic that belongs in TS packages                                     |
| `packages/shared`             | Deployed addresses (generated from `deployments/mainnet.json`), Zod schemas, adapter-kind enum, `MON_NATIVE_SENTINEL` | Import server secrets                                                      |
| `packages/transaction-review` | Canonical manifest hashing (`displayManifestHash`), Solidity-matching `executionPlanHash`                             | Diverge from `SweepPlanLib.hashPlan`'s exact encoding                      |
| `packages/routing`            | Stub — real routing logic lives in `apps/web/src/lib/routing/` until a real backend package replaces it               | —                                                                          |
| `packages/execution`          | Stub — real execution logic lives in `apps/web/src/lib/review/` until a real backend package replaces it              | —                                                                          |
| `apps/api`                    | Stub — a single liveness route                                                                                        | Business logic (not yet built)                                             |
| `apps/indexer`                | Stub — the frontend's own bounded log-scan + locally persisted record substitutes for this today                     | Event ingestion (not yet built)                                            |
| `apps/web`                    | The only real, user-facing surface today — implements the entire sweep flow chain-only                               | Fabricate backend-dependent data (e.g. claim a permanent indexer exists)   |

## Data flow today (chain-only, no backend)

1. **Wallet connect** (`apps/web`, wagmi): injected connector or a manually
   entered watch-only address; Monad chain (143) enforced.
2. **Scan** (`apps/web`, viem multicall): balances for the 5 deployed demo
   tokens plus any user-tracked address — never a full arbitrary-wallet
   index, since no indexer exists.
3. **Route candidate check** (`apps/web`, live reads): queries
   `SweepExecutor.allowedOutputTokens` and both the Uniswap V3 and Pancake V2
   factories directly. This proves a pool/pair _exists_ — it is a separate,
   further step from getting an actual executable quote (see Review below).
4. **Plan** (`apps/web`, local Zustand state): assigning an action writes to
   local state only; nothing broadcasts yet.
5. **Review** (`apps/web/src/lib/review/build-sweep-plans.ts`): builds one
   real `SweepPlan` per wallet from live balances, a live Permit2 nonce, and
   live Uniswap V3 QuoterV2 / Pancake V2 reserve-based quotes for every sell
   action; computes `displayManifestHash`/`executionPlanHash`, proves the
   plan's ABI encode/decode round-trips losslessly, and re-checks
   allow-listing/nonce-freshness/deadline against live chain state.
6. **Sign** (`apps/web/src/lib/review/use-plan-signature.ts`): requests a
   real Permit2 `PermitBatchWitnessTransferFrom` EIP-712 signature from the
   connected wallet for one wallet's plan, refusing to sign if the connected
   account doesn't match the plan's owner.
7. **Execute** (`apps/web/src/lib/review/use-plan-execution.ts`): a real
   `eth_call` staticcall simulates `executeSweep` with the real signature
   before a distinct, explicit "Broadcast" action sends the real transaction
   and polls for its receipt.
8. **Report** (`apps/web/src/lib/report/use-sweep-report.ts`): once a
   broadcast succeeds, its transaction hash is persisted locally keyed by
   `displayManifestHash`; the report page reads that transaction's own
   `SweepCompleted`/`Transfer` logs directly. Without a local record, it
   falls back to a bounded backward `getLogs` scan (chunked at Monad's
   empirically-measured 100-block range cap) before honestly reporting "not
   found" — there is no permanent indexer to fall back to further.

## Deployment record

`deployments/mainnet.json` is the single source of truth for every contract
address, dependency address, deployment transaction, source-verification
status, and — since Phase 10 — the freeze transactions and final
`configurationFrozen` state. `apps/web/src/lib/deployment.generated.ts` is
generated from it (`apps/web/scripts/generate-deployment-config.mjs`) — no
component ever hardcodes a `0x...` literal.

## Infrastructure

- **Contracts**: Monad mainnet, chain 143, RPC `https://rpc.monad.xyz`
  (production frontend traffic is proxied through a private Alchemy Monad
  mainnet endpoint server-side only — see `apps/web/src/app/api/rpc/route.ts`
  — never exposed to the client bundle).
- **Frontend**: Railway (Nixpacks builder), staging environment — see
  `STAGING_DEPLOYMENT_REPORT.md` for the live URL and configuration. No
  backend services are deployed (there's nothing real to deploy yet).
- **Secrets**: `DEPLOYER_PRIVATE_KEY` lives only in the gitignored,
  untracked `.env.deploy` used for one-time deployment/admin transactions —
  never in any Railway service's environment. The Alchemy RPC key lives only
  in a server-only Railway environment variable, never a `NEXT_PUBLIC_*` one.
