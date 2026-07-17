# TIDYR — Architecture (Pre-Frontend Baseline)

Status: draft, Phase 0. Reflects PRD Sections 1–18 as corrected by the binding Section 19
addendum and the verified-source findings in `docs/research/`.

## System overview

```
                         ┌─────────────────────┐
                         │  Monad Mainnet (143) │
                         │  SweepExecutor       │
                         │  PancakeV2Adapter    │
                         │  UniswapV3Adapter    │
                         │  DemoToken x5        │
                         │  DemoDistributor     │
                         └─────────▲────────────┘
                                   │ tx / events
        ┌──────────────────────────┼───────────────────────────┐
        │                          │                            │
┌───────┴────────┐        ┌────────┴────────┐          ┌────────┴────────┐
│  tidyr-indexer  │        │   tidyr-api     │          │  packages/       │
│  finalized-event│◄──────►│  Hono           │◄────────►│  execution        │
│  ingestion      │  writes│  discovery/quote│  used by │  (UI-independent  │
│                 │        │  /simulate/report│         │   state machine)  │
└───────┬────────┘        └────────┬────────┘          └────────┬────────┘
        │                          │                            │
   ┌────▼────┐               ┌─────▼─────┐                      │
   │ Postgres │               │   Redis    │                      │
   │ manifests│               │  quotes/   │                      │
   │ reports  │               │  locks     │                      │
   └──────────┘               └───────────┘                      │
                                                                   │
                                                        (frontend consumes this
                                                         package later — not built
                                                         in this phase)
```

## Package boundaries

| Package                       | Responsibility                                                                                                                                                  | Must NOT do                                                                         |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `packages/contracts`          | Foundry workspace: SweepExecutor, adapters, demo tokens, distributor, deploy/verify/liquidity scripts, full test suite                                          | Hold logic that belongs in TS packages (quoting, classification)                    |
| `packages/shared`             | Chain config, deployed addresses, ABIs, Zod schemas, action/report types, error taxonomy                                                                        | Import server secrets; must be safe for eventual frontend use                       |
| `packages/routing`            | PancakeV2 direct-pair quoting, Uniswap V3 quoting, 0x quoting, route comparison                                                                                 | Fabricate quotes when a provider is degraded — must return an honest degraded state |
| `packages/transaction-review` | Display manifest + hash, execution plan + hash, calldata decode-and-compare, Permit2 typed data, gas review, simulation parsing, ERC-7730 descriptor generation | Approve a plan that fails any of the three review layers                            |
| `packages/execution`          | Multi-wallet execution graph/state machine, wallet capability detection, reserve-aware native MON scheduling                                                    | Assume wallets support atomic batching without checking `wallet_getCapabilities`    |
| `apps/api`                    | Hono service: discovery, allowances, quotes, simulation, manifest persistence, report retrieval, health                                                         | Proxy arbitrary RPC methods or arbitrary URLs; hold user keys                       |
| `apps/indexer`                | Finalized-event ingestion, idempotent processing, report reconstruction                                                                                         | Treat unfinalized data as authoritative                                             |
| `apps/web`                    | Reserved for the (later) frontend                                                                                                                               | Contain any UI screens in this phase                                                |

## Data flow: plan → execution → report

1. **Discovery** (`apps/api` + `packages/routing`): Moralis balance fetch → Multicall3
   verification → allowance scan → quote attempt → classification
   (`TokenAssessment { riskState, capabilities }` per PRD §19.16, not an exclusive enum).
2. **Manifest** (`packages/transaction-review`): canonical RFC 8785 JSON →
   `displayManifestHash`; typed execution-plan encoding → `executionPlanHash`. These are
   two distinct hashes per PRD §19.3 — never conflated.
3. **Authorization** (`packages/transaction-review` + wallet): Permit2 `SignatureTransfer`
   witness bound to `executionPlanHash`; direct wallet-level revoke/approval transactions
   are separate, non-executor-side actions per PRD §19.2.
4. **Review** (`packages/transaction-review`): three mandatory layers — intent manifest,
   calldata decode-and-compare, Tenderly simulation. All three must pass before a
   signature card is shown.
5. **Execution** (`packages/execution`): per-wallet execution graph; sequential within a
   wallet, concurrent across wallets; commitment tracked through
   BROADCAST → PROPOSED → VOTED → FINALIZED → VERIFIED (PRD §19.6).
6. **Indexing** (`apps/indexer`): idempotent (`chainId + txHash + logIndex`) ingestion of
   `SweepCompleted` / `ActionExecuted` / `ActionFailed` plus direct-transaction receipts.
7. **Report** (`apps/api`): reconstructed strictly from finalized on-chain data — no
   aggregate-counter-only inference (PRD §19.17).

## Contract boundaries (binding — PRD §19.15)

`SweepExecutor` validates plan fields, consumes exact Permit2-authorized amounts,
executes allowlisted adapter swaps, performs transfers/discards/burns, unwraps WMON,
settles output, isolates plan funds from pre-existing balances, emits action-level events.
It never revokes EOA-owned allowances, never makes arbitrary calls, never stores funds
between transactions.

`PancakeV2Adapter` and `UniswapV3Adapter` are thin, strictly-validated, allowlisted
adapters that always return output to the executor and never hold funds.

`DemoDistributor` holds only demo inventory; one claim per address; no arbitrary
withdrawal.

## Key architectural corrections already applied from PRD §19 (see traceability matrix for full list)

- No `RevokeAction[]` in `SweepPlan` — revocations are direct wallet transactions.
- Two distinct hashes (`displayManifestHash`, `executionPlanHash`), not one shared manifest hash.
- `PancakeV2Adapter` targets direct V2 pair contracts (no classic Router02 exists on Monad — see `docs/research/external-addresses.md` conflict C-1), not a PancakeSwap-hosted router.
- Commitment states modeled as a 4-stage MonadBFT pipeline, not binary pending/confirmed.
- Native MON reserve logic branches on EIP-7702 delegation status, per the precise Monad rule (not a flattened "always 10 MON" floor).
- Atomic batching claims are gated on `wallet_getCapabilities`, never assumed.

## Infrastructure (Railway-only, PRD §19.13)

`tidyr-web`, `tidyr-api`, `tidyr-indexer`, managed Postgres, managed Redis. Postgres/Redis
are never the source of truth for successful execution — finalized Monad receipts/events
are authoritative. `DEPLOYER_PRIVATE_KEY` is a deployment-time-only secret, never present
in any Railway service's runtime environment after ownership transfer.
