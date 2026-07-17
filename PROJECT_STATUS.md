# TIDYR — Project Status

## Phase 0 — Repository and Requirement Discovery

**Objective:** Read the complete production PRD (including the binding Section 19
addendum), inspect the repository, and produce the research, architecture, traceability,
and risk documentation required before any implementation begins.

**Files created:**

- `docs/research/monad-source-map.md`
- `docs/research/external-addresses.md`
- `docs/architecture.md`
- `docs/implementation-plan.md`
- `docs/requirements-traceability.md`
- `docs/risk-register.md`
- `.gitignore`
- `PROJECT_STATUS.md` (this file)

**Requirements satisfied:** Phase 0 acceptance criteria from the operating instructions —
complete traceability matrix, documented architecture, documented verified-source
strategy, no unrecorded implementation assumptions, contradictions between PRD sections
documented with resolutions (see traceability matrix "Contradiction / conflict log").

**Commands executed:**

```
git init
git checkout -b build/pre-frontend-production
eth_chainId against https://rpc.monad.xyz            -> 0x8f (143)
eth_getCode against 9 external contract addresses     -> all non-empty
eth_call decimals()/symbol() against USDC candidate   -> 6 / "USDC"
npm registry + unpkg inspection of @pancakeswap/v2-sdk,
  @pancakeswap/universal-router-sdk, @pancakeswap/chains (official packages)
```

**Test results:** N/A — no application code exists yet. All verification in this phase was
direct on-chain RPC calls and primary-source document/package inspection (see
`docs/research/external-addresses.md` for the full command list and results).

**Unresolved risks:** See `docs/risk-register.md`. Notably R-1 (no classic PancakeSwap
router on Monad — resolved in design), R-3/R-11 (Monad-specific execution nuances not
literally stated in the PRD — resolved in design), R-13 (hackathon deadline vs. full
scope — acknowledged, not a shortcut justification).

**Commit hash:** `e0a11a7`

**Next phase:** Phase 1 — Monorepo Foundation (pnpm workspace, Foundry workspace, CI,
`.env.example`, pinned toolchain versions).

---

## Phase 1 — Monorepo Foundation

**Objective:** Stand up the Railway-ready pnpm monorepo and Foundry workspace with pinned
toolchain versions, shared TypeScript strict-mode configuration, CI, and environment
variable documentation — no product logic yet.

**Files created:**

- `pnpm-workspace.yaml`, `package.json`, `tsconfig.base.json`, `eslint.config.js`,
  `.prettierrc.json`, `.prettierignore`
- `packages/shared`, `packages/routing`, `packages/transaction-review`,
  `packages/execution` — each a strict-TS package with a passing identity test
- `apps/api` — Hono skeleton with a real `/health/live` liveness endpoint (readiness
  deferred to Phase 12/13, not faked)
- `apps/indexer` — skeleton, logic deferred to Phase 13
- `packages/contracts` — Foundry workspace: `forge init`, pinned `solc 0.8.26`; libs
  vendored as real git submodules (not copied source) pinned to exact refs —
  `forge-std@v1.16.2`, `openzeppelin-contracts@v5.1.0`, `permit2@cc56ad0` (Permit2 has no
  version tags; pinned to an exact commit SHA instead); `foundry.toml` pins
  optimizer/fuzz/invariant run counts and a CI profile with higher run counts; a toolchain
  smoke test proves OZ v5 + Permit2 imports resolve and compile
- `.env.example` mirroring PRD §19.18, pre-filled with the addresses verified in Phase 0
  (WMON, Permit2, PancakeSwap V2 Factory/Universal Router, Uniswap V3 Factory/Universal
  Router, USDC, Multicall3); deployment-only and provider-secret fields left blank
- `.github/workflows/contracts.yml` (forge build/test/fuzz/snapshot/Slither) and
  `.github/workflows/typescript.yml` (install/lint/format/typecheck/build/test/secret-scan)
- `scripts/scan-secrets.sh` — dependency-free secret pattern scan used by CI
- `railway.json` — minimal root builder/deploy config; per-service configuration is
  Phase 15 work
- `.gitignore` updated for Foundry artifacts (`out/`, `cache/`, `broadcast/`)

**Requirements satisfied:** Phase 1 acceptance criteria — fresh `pnpm install` succeeds;
every workspace package builds, typechecks, and passes its test; `forge build`/`forge
test` succeed against pinned versions; no secrets in tracked files; no visual frontend
implemented (`apps/web` was not created — nothing in the workspace or Railway wiring
required it yet, and the operating instructions only permit a placeholder `apps/web` when
that dependency exists).

**Additional verified finding (recorded in `docs/research/external-addresses.md`):** the
naive MonadScan V1 verification endpoint (`api.monadscan.com/api`) self-reports as
deprecated in favor of Etherscan's unified V2 multichain API
(`https://api.etherscan.io/v2/api?chainid=143`); confirmed live via direct `curl` and
wired into `foundry.toml`'s `[etherscan]` block and `.env.example`
(`ETHERSCAN_API_KEY`, not a separate MonadScan key).

**Commands executed and results:**

```
pnpm install                    -> success, 129 packages added
pnpm typecheck                  -> 6/6 packages pass
pnpm build                      -> 6/6 packages pass
pnpm test                       -> 6/6 packages pass (5 identity tests + 1 health-endpoint test)
pnpm lint                       -> clean
pnpm format                     -> clean (after prettier --write on docs; no content changes)
forge build (packages/contracts) -> Compiler run successful (solc 0.8.26)
forge test (packages/contracts)  -> 1 passed (ToolchainSmoke — OZ v5 + Permit2 remappings resolve)
```

**Unresolved risks:** none new. Phase 15 will need to replace `railway.json`'s minimal
placeholder with real per-service configuration once Railway auth is available.

**Commit hash:** `bd53ed1`

**Next phase:** Phase 2 — Chain constants, shared types, and deterministic display/execution
hashing (Solidity + TypeScript golden vectors).

---

## Phase 2 — Action Structs and Deterministic Hashing

**Objective:** Define the corrected `SweepPlan`/action structs (no executor-side
`RevokeAction`, per §19.2) and implement `executionPlanHash` (Solidity) /
`displayManifestHash` (TypeScript, RFC 8785) as two genuinely distinct hashes, with
cross-language golden vectors proving Solidity and TypeScript agree byte-for-byte.

**Files created:**

- `packages/contracts/src/libraries/SweepPlanLib.sol` — `SwapAction`/`TransferAction`/
  `DiscardAction`/`BurnAction`/`SweepPlan` structs (no `RevocationAction[]`),
  `validatePlanShape` (empty/oversized rejection), `hashPlan` (`executionPlanHash`) with
  per-action-array element-wise hashing so nested dynamic `bytes` fields
  (`SwapAction.routeData`) can't introduce ABI-encoding ambiguity
- `packages/contracts/test/SweepPlanLib.t.sol` — 12 tests: determinism, per-field
  sensitivity (amount/recipient/outputToken/deadline/nonce), action-order sensitivity,
  execution-hash-vs-display-hash distinctness, empty/oversized/exactly-max plan shape
  validation
- `packages/shared/src/actions.ts` — branded `Address`/`Hex` types (viem-compatible),
  zod schemas mirroring the Solidity structs exactly, `MAX_ACTIONS`,
  `MON_NATIVE_SENTINEL` (documented rationale: the cross-protocol `0xEeee...EEeE`
  convention, not `address(0)`, so "native asset" stays distinguishable from
  "unset/invalid"), the direct `WalletTransaction` union (revoke / Permit2 approval /
  sweep execution / top-up / multi-send, per §19.2), and the capability-based
  `TokenAssessment` type (§19.16 override — not an exclusive enum)
- `packages/transaction-review/src/executionPlanHash.ts` — TypeScript mirror of
  `SweepPlanLib.hashPlan` using viem's `encodeAbiParameters`/`keccak256`
- `packages/transaction-review/src/displayManifestHash.ts` — RFC 8785 (JCS)
  canonicalization via the `canonicalize` package + `keccak256` of the canonical string
- `packages/transaction-review/src/executionPlanHash.test.ts` and
  `displayManifestHash.test.ts` — 14 tests total, including the cross-language golden
  vector assertion
- `test-vectors/golden-vectors.md` — records Vector A's field values, the verified
  shared hash, and how to reproduce it on both sides

**Requirements satisfied:** all Phase 2 acceptance criteria — Solidity and TypeScript
produce identical `executionPlanHash` for the same plan; action order, amount,
recipient, output token, deadline, and nonce all change the hash; `displayManifestHash`
and `executionPlanHash` are proven distinct for the same logical plan; empty and
oversized (>50 actions) plans are rejected, exactly 50 is accepted.

**Cross-language golden value (Vector A):**
`0x184bb27ccf4286fdd2f69be2433e59715e5ce345badd2ba2f5688bd2368f1de5` — computed once by
the Solidity implementation, independently reproduced by the TypeScript implementation
before being hardcoded as the asserted constant in both test suites (not assumed).

**Also fixed:** `packages/shared`'s `Address`/`Hex` types were initially plain `string`
(zod's default inference), which would not have been type-compatible with viem's
branded `` `0x${string}` `` types once `packages/transaction-review` started consuming
them — caught during this phase and fixed with `.transform()` casts before it could
surface as a real bug in Phase 3+.

**Also fixed (monorepo infra, discovered while wiring this phase):** the original
per-package `tsc` build emitted compiled `.js` via `outDir: dist`, which conflicts with
`allowImportingTsExtensions` (required so Node's native TypeScript support can resolve
`./actions.ts`-style relative imports at test/runtime). Resolved by making all internal
packages resolve directly from `.ts` source (`main`/`types`/`exports` point at
`src/index.ts`), with `tsc` now used purely for typechecking. `apps/api`'s `dev`/`start`
scripts now use Node's built-in `--experimental-strip-types --watch` instead of a `tsx`
dependency, and root `engines.node` was tightened to `>=22.6.0 <25` (the version where
that flag exists).

**Commands executed and results:**

```
forge test --match-contract SweepPlanLibTest   -> 12 passed (packages/contracts)
forge build                                    -> Compiler run successful
pnpm typecheck                                  -> 6/6 packages pass
pnpm build                                      -> 6/6 packages pass
pnpm test                                       -> all packages pass (transaction-review: 14, shared: 6)
pnpm lint                                       -> clean
pnpm format                                     -> clean
```

**Unresolved risks:** none new.

**Commit hash:** recorded after this phase's commit (see `git log`).

**Next phase:** Phase 3 — Permit2 witness binding to `executionPlanHash` (SignatureTransfer,
exact per-token amount aggregation, replay/expiry/wrong-spender rejection tests).
