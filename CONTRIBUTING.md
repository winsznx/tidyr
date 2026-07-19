# Contributing to TIDYR

This is a `pnpm` workspace monorepo. Every package/app is built, typechecked,
linted, and tested from the repo root.

## Requirements

- Node.js `>=22.6.0 <25` (see `engines` in `package.json`)
- `pnpm@10.33.0` (pinned via `packageManager`; enable with `corepack enable`)
- [Foundry](https://getfoundry.sh) for `packages/contracts`

## Setup

```bash
pnpm install --frozen-lockfile
cp .env.example .env.local   # fill in what you actually need, never commit it
```

## Branching

- `main` is the trunk.
- Contract/protocol work happens on `security/*` or `protocol/*` branches.
- Frontend work happens on `frontend/*` branches.
- Releases are merged into `release/*` branches before deployment.

(See git history for the actual pattern used — this isn't a proposal, it's
how this repo has been worked on.)

## Before proposing a change

Run the full local validation:

```bash
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm build

# Contracts specifically
pnpm contracts:build
pnpm contracts:test
```

All of these must pass. If a pre-existing failure is unrelated to your
change, say so explicitly rather than silently working around it.

## Code style

- Prettier + ESLint configs at the repo root apply to every TS/JS package —
  don't hand-format around them.
- Solidity follows `forge fmt`.
- No `as any`, `@ts-ignore`, or `@ts-expect-error` — if a type doesn't fit,
  fix the type, don't suppress the checker.

## Secrets

- Never commit a real secret. `DEPLOYER_PRIVATE_KEY` and any RPC provider key
  belong only in gitignored, untracked `.env.deploy` / `.env.local` files.
- Never put a real credential in a `NEXT_PUBLIC_*` environment variable —
  Next.js bakes that prefix into the client bundle, so it becomes visible to
  every visitor. Route it through a server-only proxy instead (see
  `apps/web/src/app/api/rpc/route.ts` for the pattern this repo already
  uses).
- `scripts/scan-secrets.sh` checks tracked files for common secret patterns —
  run it if you're unsure before committing.

## Contract changes specifically

`SweepExecutor`, `PancakeV2Adapter`, and `UniswapV3Adapter` are permanently
frozen on Monad mainnet (see `ARCHITECTURE.md`, `SECURITY.md`). There is no
`unfreeze` — any change to their logic requires a new deployment, not an
upgrade. Read `SECURITY.md` and `docs/threat-model.md` before touching
anything under `packages/contracts/src/`, and add test evidence (unit, fuzz,
or fork, as appropriate) for any new behavior rather than asserting it works.

## Frontend changes specifically

`apps/web` is chain-only — no backend exists, and none of its real
functionality should be faked to look otherwise. If a capability genuinely
needs a backend that doesn't exist yet, show an honest degraded/unavailable
state rather than fabricating data. See `docs/frontend-integration-matrix.md`
for the established real-vs-stubbed convention per screen.
