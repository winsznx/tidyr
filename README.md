# TIDYR

Multi-wallet cleanup for Monad mainnet — scan every wallet, decide what to
sell, consolidate, discard, or burn, and understand every transaction before
you sign.

**Live status:** contracts deployed and permanently frozen on Monad mainnet
(chain 143). Frontend staging preview deployed. No backend exists yet, and
the frontend's review/sign/execute/report surfaces are intentionally paused
until it does. See [`docs/architecture.md`](docs/architecture.md) for the
full picture and why that gap is deliberate, not an oversight.

| Doc                                                                                                | What it's for                                                                            |
| -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [`docs/architecture.md`](docs/architecture.md)                                                     | System architecture — what's real vs. stubbed, contract layer, frontend layer, data flow |
| [`tidyr-production-prd.md`](tidyr-production-prd.md)                                               | Full product requirements (the long-term target)                                         |
| [`docs/threat-model.md`](docs/threat-model.md), [`docs/security-model.md`](docs/security-model.md) | Security design                                                                          |
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
docs/                     Architecture, security, PRD-support documents
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
configuration. See `docs/architecture.md`'s Infrastructure section.

## Contributing

- `main` is the trunk. Protocol work happens on `security/*` /
  `protocol/*` branches; frontend work on `frontend/*`; releases are merged
  into `release/*` branches (see git history for the actual pattern used).
- Follow the existing code style (Prettier + ESLint configs at the repo
  root apply to every TS/JS package). Solidity follows `forge fmt`.
- Run the full local validation (`format:check`, `lint`, `typecheck`,
  `test`, `build`, plus `contracts:test`) before proposing a change.
- Never commit real secrets. `scripts/scan-secrets.sh` checks tracked files
  for common secret patterns.

## License

MIT — see [`LICENSE`](LICENSE).
