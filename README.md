# TIDYR

Multi-wallet cleanup for Monad mainnet — scan every wallet, decide what to
sell, consolidate, discard, or burn, and understand every transaction before
you sign.

**Live status:** contracts deployed and permanently frozen on Monad mainnet
(chain 143). The full sweep flow — scan wallets, plan actions, review the
exact plan with live quotes, sign a real Permit2 message, simulate and
broadcast execution, and reconstruct a report from real on-chain logs — is
built end to end and staging-deployed, entirely chain-only with no backend.
See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full picture.

| Doc                                                                                                | What it's for                                                                            |
| -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [`ARCHITECTURE.md`](ARCHITECTURE.md)                                                               | System architecture — what's real vs. stubbed, contract layer, frontend layer, data flow |
| [`SECURITY.md`](SECURITY.md)                                                                        | Security model, threat coverage, and audit trail summary                                 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md)                                                                | How this repo is worked on — branches, validation, secret handling                        |
| [`tidyr-production-prd.md`](tidyr-production-prd.md)                                               | Full product requirements (the long-term target)                                         |
| [`docs/threat-model.md`](docs/threat-model.md), [`docs/security-model.md`](docs/security-model.md) | Full-detail security design (summarized in `SECURITY.md`)                                |
| [`PHASE_7_SECURITY_COMPLETION_REPORT.md`](PHASE_7_SECURITY_COMPLETION_REPORT.md)                   | Independent contract security audit                                                      |
| [`PHASE_10_COMPLETION_REPORT.md`](PHASE_10_COMPLETION_REPORT.md)                                   | Real mainnet route proof, smoke test, and freeze                                         |
| [`STAGING_DEPLOYMENT_REPORT.md`](STAGING_DEPLOYMENT_REPORT.md)                                     | Live frontend staging deployment details                                                 |
| [`docs/frontend-integration-matrix.md`](docs/frontend-integration-matrix.md)                       | Frontend: real vs. stubbed capability, per screen                                        |
| [`deployments/mainnet.json`](deployments/mainnet.json)                                             | Canonical deployed contract addresses and transaction history                            |

## Repository layout

```
apps/
  web/        Next.js frontend (real, chain-only, staging-deployed)
  api/        Backend API (stub — liveness endpoint only)
  indexer/    Event indexer (stub)
packages/
  contracts/            Foundry workspace — SweepExecutor, adapters, tests
  shared/                Deployed addresses, Zod schemas, adapter-kind enum
  transaction-review/    Canonical manifest + execution-plan hashing
  routing/               Stub (frontend has its own chain-only routing reads)
  execution/             Stub (no execution wiring built yet)
deployments/
  mainnet.json           Source of truth for every deployed address/tx
docs/                     Detailed architecture/security/PRD-support documents
artifacts/                Phase-by-phase verification evidence (security, Phase 10, frontend)
```

This is a `pnpm` workspace monorepo (see `pnpm-workspace.yaml`). Every
package/app is built, typechecked, linted, and tested from the repo root.

## Requirements

- Node.js `>=22.6.0 <25` (see `engines` in `package.json`)
- `pnpm@10.33.0` (pinned via `packageManager`; enable with `corepack enable`)
- [Foundry](https://getfoundry.sh) for `packages/contracts`

## Quickstart

```bash
pnpm install --frozen-lockfile

# Frontend (apps/web)
pnpm --filter @tidyr/web dev          # http://localhost:3000

# Whole workspace
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm build

# Contracts (packages/contracts)
pnpm contracts:build
pnpm contracts:test
```

Copy `.env.example` for the shape of every environment variable this project
uses. Real secrets (`DEPLOYER_PRIVATE_KEY`, API keys) belong only in
gitignored, untracked `.env.deploy` / `.env.local` files — never commit
them, and never add a private key to any hosting provider's environment
configuration. See `ARCHITECTURE.md`'s Infrastructure section.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Security

See [`SECURITY.md`](SECURITY.md).

## License

MIT — see [`LICENSE`](LICENSE).
