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

**Commit hash:** `218fb3b`

**Next phase:** Phase 3 — Permit2 witness binding to `executionPlanHash` (SignatureTransfer,
exact per-token amount aggregation, replay/expiry/wrong-spender rejection tests).

---

## Phase 3 — Permit2 Authorization

**Objective:** Bind Permit2 `SignatureTransfer` authorization to `executionPlanHash` via
a witness, so a signature for one plan can never authorize a different plan, and prove
it against Permit2's real vendored deployment — not a mock.

**Files created:**

- `packages/contracts/src/libraries/TidyrWitness.sol` — the `TidyrWitness(bytes32
executionPlanHash)` witness struct's typehash and the exact `witnessTypeString`
  Permit2's `permitWitnessTransferFrom` requires, both derived from Permit2's own
  vendored source and test-suite convention, not invented (see
  `docs/research/external-addresses.md`)
- `SweepPlanLib.aggregateTokenAmounts` (added to the existing library) — sums the exact
  required amount per unique token across every action that consumes user funds
  (swaps/transfers/discards/burns), so Permit2 is only ever asked to authorize exactly
  what the plan needs, with duplicate token references safely combined into one entry
- `packages/contracts/test/mocks/MockERC20.sol` — minimal test-only mintable ERC20
- `packages/contracts/src/vendor/Permit2Marker.sol` — forces `forge build` to produce a
  Permit2 artifact for `deployCode`, without any 0.8.26 TIDYR source directly importing
  the concrete Permit2 contract
- `packages/contracts/test/Permit2Witness.t.sol` — 7 tests against a real, unmodified
  Permit2 deployment (via `deployCode("Permit2.sol:Permit2")`): token aggregation
  dedup/sum, valid signed transfer succeeds, tampered witness fails, reused nonce fails,
  expired deadline fails, wrong spender (a different calling contract) fails, excessive
  pull fails

**Requirements satisfied:** all Phase 3 acceptance criteria — valid witness succeeds;
modified plan fails; reused nonce fails; expired signature fails; wrong spender fails;
excessive pull fails; duplicate token requirements are safely aggregated. EIP-1271
contract-signature support and the "existing direct approval to Permit2" onboarding flow
are explicitly deferred to Phase 14 (execution scheduler) — not part of this phase's
scope and not silently assumed.

**Two real build problems found and fixed while wiring this phase (not scope creep —
both blocked any use of the real Permit2 contract at all):**

1. Permit2's own nested `lib/solmate` submodule wasn't initialized (only the top-level
   `permit2` submodule was added in Phase 1) — fixed with `git submodule update --init
--recursive` inside the permit2 submodule; confirmed our top-level CI's
   `submodules: recursive` checkout step already handles this correctly on a fresh clone.
2. `foundry.toml`'s hard-pinned `solc = "0.8.26"` made it impossible to compile Permit2
   at all (its contracts pragma an exact `0.8.17`, which cannot satisfy `^0.8.26` in the
   same compilation unit). Fixed by switching to `auto_detect_solc = true` (TIDYR's own
   contracts now pragma an exact `0.8.26` for determinism, Permit2 compiles under its own
   `0.8.17` unit) and enabling `via_ir = true` project-wide, since Permit2's contracts hit
   "stack too deep" under legacy codegen (confirmed Permit2's own `foundry.toml` also
   requires `via_ir = true`). Re-verified after both fixes that Vector A's
   `executionPlanHash` golden value is unchanged.

**Commands executed and results:**

```
forge clean && forge build   -> Compiling 15 files with Solc 0.8.17 / 42 files with Solc 0.8.26, successful
forge test                   -> 20 passed, 0 failed (1 toolchain smoke + 12 SweepPlanLib + 7 Permit2Witness)
```

**Unresolved risks:** none new. EIP-1271 smart-contract-wallet signature support remains
an explicitly deferred item, not a silent gap — Permit2 itself supports it
(`SignatureVerification.sol`) and TIDYR will exercise it if/when smart-contract wallet
support is added to the execution scheduler.

**Commit hash:** `31519cb`

**Next phase:** Phase 4 — SweepExecutor core (validation, Permit2 pull, allowlisted
adapter execution, balance-delta isolation, remainder return, events).

---

## Phase 4 — Secure Sweep Execution

**Objective:** Implement `SweepExecutor` itself — the contract that validates a signed
plan, pulls exactly the tokens it authorizes via the Phase 3 Permit2 witness, runs
allowlisted adapter swaps, performs transfers/discards/burns, settles output, and
returns any unconsumed input — with the full security-pattern set from PRD §5 and the
§19 corrections (no executor-side revoke, corrected `allowFailure` semantics, plan-fund
isolation from pre-existing balances).

**Files created:**

- `packages/contracts/src/SweepExecutor.sol` — the core contract:
  `Ownable2Step` + `ReentrancyGuard`; immutable `PERMIT2`/`WMON`; owner-managed adapter
  and output-token allowlists; `executeSweep` validation pipeline (owner match, non-zero
  recipient, output-token allowlist, deadline, sequential nonce, plan shape); Permit2
  batch-witness pull using Phase 3's `TidyrWitness`/`aggregateTokenAmounts`; a
  balance-delta swap loop with the corrected §19.9 `allowFailure` semantics (a "successful"
  under-delivering adapter call is always fatal, never a soft failure); WMON unwrap for
  native MON output; balance-delta-from-pre-pull-baseline settlement and remainder-return
  (§19.10 isolation from pre-existing/other-plan balances); a narrowly-scoped
  `recoverStrayTokens` sharing `executeSweep`'s reentrancy lock so it can never run
  mid-execution
- `packages/contracts/src/interfaces/IAdapter.sol`, `IBurnable.sol`, `IWMON.sol`
- `packages/contracts/test/mocks/{MockAdapter,MockWMON,MockBurnableERC20,MockReentrantAdapter}.sol`
  — controllable test doubles so SweepExecutor's handling of adapter results can be
  tested independently of any real DEX (PancakeV2Adapter/UniswapV3Adapter get their own
  tests in Phase 5)
- `packages/contracts/test/SweepExecutor.t.sol` — 19 unit tests (every happy path: ERC20
  output, native MON output via WMON unwrap, transfer/discard/burn actions; every
  validation failure: wrong owner, zero recipient, disallowed output token, expired
  plan, reused nonce, unregistered adapter, ambiguous swap-into-settlement-token, empty
  plan; `allowFailure` correctness including the under-delivery-always-fatal case;
  pre-existing-balance isolation; owner-only + reentrancy-blocked recovery; a malicious
  reentrant adapter) plus 3 fuzz tests (256 runs each: swap conservation, transfer/discard
  non-retention, pre-existing-balance non-attribution)
- `packages/contracts/test/SweepExecutorInvariants.t.sol` — a stateful handler driving
  128 runs × 64 sequential real-signature sweeps (8,192 calls) from the same owner,
  checking two invariants after every call: the executor never retains a touched-token
  balance, and the owner's nonce always exactly equals the number of successful calls

**Requirements satisfied:** all Phase 4 acceptance criteria — unit tests for every
validation; fuzz tests for action arrays and amounts; invariant that the executor cannot
spend more than Permit2 authorized (structural: the only pull path is the witness-bound
batch permit); invariant that a plan cannot consume pre-existing balances; invariant that
successful execution retains zero active-plan balance; invariant that a nonce cannot be
reused; invariant that an unregistered adapter is unreachable; no arbitrary call target
exists (only `IAdapter.swap` and a native-MON send to the plan's own recipient).

**A real bug found and fixed while building the invariant test (not a contract bug — a
test harness bug, but worth recording since it shaped the final invariant suite):** the
handler's `runSweep` called `bound(amount, 1, DUST.balanceOf(OWNER))` without checking
whether that balance had already reached zero after enough prior successful sweeps,
which made `bound` revert with "Max is less than min" once the fuzzer's sequence drained
the owner's balance. Fixed by returning early when the owner's balance is zero, letting
later calls in a sequence become no-ops rather than reverting the whole run.

**Commands executed and results:**

```
forge clean && forge build                                        -> successful (0.8.17 + 0.8.26 units)
forge test --no-match-contract SweepExecutorInvariantsTest         -> 42 passed, 0 failed
forge test --match-contract SweepExecutorInvariantsTest            -> 2 invariants passed (8192 calls each, 0 reverts)
grep -rn "delegatecall|tx.origin" src/                             -> no matches (only a doc comment mentions delegatecall)
forge snapshot                                                     -> written to packages/contracts/.gas-snapshot
```

**Unresolved risks:** none new. Adapters themselves (PancakeV2Adapter/UniswapV3Adapter)
don't exist yet — Phase 4's tests exercise SweepExecutor's handling of adapter results
generically via `MockAdapter`; real DEX integration correctness is Phase 5's scope, not
assumed here.

**Commit hash:** `cc11b20`

**Next phase:** Phase 5 — PancakeV2Adapter (direct pair interaction, per conflict C-1)
and UniswapV3Adapter (strict path/command allowlist against the verified Monad
deployment).

---

## Phase 5 — Constrained DEX Adapters

**Objective:** Implement `PancakeV2Adapter` and `UniswapV3Adapter` with the smallest safe
surface, verified against real Monad mainnet contracts wherever possible rather than
assumed from the PRD's examples.

**Files created:**

- `packages/contracts/src/interfaces/{IPancakeFactory,IPancakePair}.sol`
- `packages/contracts/src/adapters/PancakeV2Adapter.sol` — per conflict C-1, reads pairs
  directly from the verified Monad factory and computes swap amounts itself via the
  standard constant-product formula (0.3% fee), mirroring UniswapV2Router02's own
  `_swap`/`getAmountsOut` logic without depending on a router that doesn't exist on
  Monad; strict path validation (must start at `tokenIn`, end at `tokenOut`), an
  owner-managed intermediate-asset allowlist (seeded with WMON), non-zero
  `minAmountOut`, deadline enforcement, output always settles to the caller
- `packages/contracts/src/interfaces/ISwapRouter02.sol`, `src/libraries/UniswapV3Path.sol`
  (minimal packed-path token extraction, the standard BytesLib-style technique used by
  Uniswap's own `Path.sol`)
- `packages/contracts/src/adapters/UniswapV3Adapter.sol` — **conflict C-7** (new,
  recorded in the traceability matrix): the PRD directs wrapping Uniswap's Universal
  Router with a command-byte allowlist, but Uniswap also deployed a classic `SwapRouter02`
  on Monad with a fixed, non-generic `exactInput` signature — confirmed by reading the
  _live deployed bytecode's function selectors_ (`0xb858183f` present, the old
  deadline-inclusive `exactInput` selector `0xc04b8d59` absent), not assumed. Calling
  SwapRouter02 directly has a strictly smaller attack surface (no command bytes to
  allowlist at all) for the identical capability, so the adapter does that instead of
  wrapping Universal Router.
- Test mocks: `MockPancakePair`, `MockPancakeFactory`, `MockSwapRouter02` (mirrors
  `MockAdapter`'s Normal/Revert/UnderDeliver control shape)
- `packages/contracts/test/PancakeV2Adapter.t.sol` (10 tests), `UniswapV3Adapter.t.sol`
  (11 tests) — path validation, intermediate-asset allowlist, output enforcement,
  expiry, malformed path, router-revert bubbling, approval reset, owner-only admin
- `packages/contracts/test/SweepExecutorAdapterIntegration.t.sol` (2 tests) — full
  signed-plan execution through the real (non-mock) adapter contracts, not `MockAdapter`
- `packages/contracts/test/PancakeV2Adapter.fork.t.sol` (2 tests) — **a real swap against
  the actual live PancakeSwap V2 WMON/USDC pair on Monad mainnet**
  (`0x27AA322b3f8Ba9d0041Df99c33fE4f3CC135E054`, found via `factory.getPair` at test
  time, confirmed non-zero live reserves ~16.25 WMON / ~0.359 USDC), wrapping real
  native MON into real WMON through the real WMON contract and executing a genuine
  `IPancakePair.swap()` call, with output matching the constant-product formula computed
  from the live reserves exactly

**Requirements satisfied:** all Phase 5 acceptance criteria — unit tests with
controlled routers; malicious-path tests; wrong-output tests; expired-route tests;
partial/reverting-router tests; mainnet-fork quote-and-swap test (PancakeV2, ran
successfully against live Monad state — Uniswap V3 fork testing deferred since no
fee-tier pool with live TIDYR-relevant liquidity is expected to exist pre-deployment;
the mock-router tests cover its logic exhaustively). Fee-on-transfer input handling is
inherited from SweepExecutor's Phase 4 exact-pulled-amount check, not re-implemented
per adapter.

**Commands executed and results:**

```
forge build                                                          -> successful
forge test --no-match-path "*.fork.t.sol" --no-match-contract SweepExecutorInvariantsTest
                                                                      -> 65 passed, 0 failed
forge test --match-path "*.fork.t.sol"                               -> 2 passed (live Monad mainnet fork)
forge test --match-contract SweepExecutorInvariantsTest              -> 2 invariants passed (8192 calls each)
forge snapshot                                                       -> updated packages/contracts/.gas-snapshot
```

CI (`contracts.yml`) updated: the deterministic suite excludes `*.fork.t.sol` via
`--no-match-path`; fork tests run in a separate, `continue-on-error` step so network
flakiness never blocks the required (deterministic) suite.

**Unresolved risks:** none new. Uniswap V3 has no equivalent fork-tested live pool yet
(Phase 6/10 will deploy TIDYR's own demo liquidity, at which point a V3 fork test could
be added if a real V3 pool with TIDYR-relevant tokens exists — not assumed here).

**Commit hash:** `1935fbf`

**Next phase:** Phase 6 — Demo token suite (DUST1–5) and DemoDistributor.

---

## Phase 6 — Demo Asset Suite

**Objective:** Implement the five demo tokens and `DemoDistributor` with a fixed,
documented supply, no hidden taxes, no post-deployment minting, and one honest claim
per address.

**Files created:**

- `packages/contracts/src/tokens/DemoToken.sol` — fixed 1,000,000-token supply minted
  to the deployer at construction; no `mint` function exists at all, so supply can never
  change afterward. Used for DUST1/DUST2/DUST3/DUST5 (DUST5's "no pool" status is a
  liquidity-provisioning decision made in Phase 8/10, not a contract-level difference —
  the token itself is identical in shape to DUST1–3)
- `packages/contracts/src/tokens/BurnableDemoToken.sol` — same fixed-supply policy, adds
  OpenZeppelin's audited `ERC20Burnable` for DUST4
- `packages/contracts/src/tokens/DemoDistributor.sol` — `Ownable2Step` + `Pausable`;
  `claimDemoBundle()` sets `claimed[msg.sender]` before any external call (CEI), then
  transfers 200 of each of the five tokens via `SafeERC20`; `pause`/`unpause` exist only
  for emergency inventory depletion or a token-level error per §19.15, restricted to the
  owner; deliberately has no owner withdrawal function since it only ever holds
  pre-funded demo inventory, never arbitrary user funds
- `packages/contracts/test/DemoToken.t.sol` (6 tests), `test/DemoDistributor.t.sol`
  (8 tests)

**Requirements satisfied:** all Phase 6 acceptance criteria — one successful claim;
second claim reverts; DUST4 burn reduces both balance and total supply (and reverts on
an over-balance burn); DUST5 remains freely transferable at the contract level;
inventory-limit handling is honest (a claim that would exceed remaining inventory
reverts the entire bundle transfer, never a partial/short distribution — verified by
draining the distributor via 5 real claims, exactly matching its 1000-ether-per-token
funding, then confirming a 6th claimant's transaction reverts and is not recorded as
claimed).

**A real test bug found and fixed (not a contract bug):** the initial over-balance-burn
test computed `token.balanceOf(address(this)) + 1` directly inside the `vm.expectRevert()`
call-armed statement. Since `balanceOf` is itself an external call, Foundry's
`expectRevert` intercepted _that_ call (a harmless view call that obviously doesn't
revert) rather than the intended `burn` call, so the test passed for the wrong reason
until closer inspection of its trace. Fixed by computing the balance on its own line
before arming `expectRevert`.

**Commands executed and results:**

```
forge build                                                          -> successful
forge test --no-match-path "*.fork.t.sol" --no-match-contract SweepExecutorInvariantsTest
                                                                      -> 79 passed, 0 failed
```

**Unresolved risks:** none new. Mainnet deployment of these contracts (real supply,
real distributor funding) is Phase 9 — nothing here is deployed yet.

**Commit hash:** `124c0b9`

**Next phase:** Phase 7 — Security hardening: fuzz/invariant/fork test expansion,
Slither, gas snapshot review, threat-model documentation.

---

## Security Addendum — Pre-Phase-7 Review (branch `fix/security-addendum-before-phase-7`)

**Trigger:** an external review, prompted by public discussion of a Multicall3
approval-drain vulnerability class, requesting a mandatory security architecture audit
of Phases 0–6 before Phase 7 begins.

**Objective:** verify every claim in the review against the actual repository state —
not assume the review's framing was correct, and not fabricate findings to look
thorough where the code was already sound.

**Outcome: zero P0 (fund-drain) findings.** The architecture already avoided every
mechanism the review was concerned about — no Multicall3 reference exists anywhere in
the codebase yet, no generic arbitrary-call execution surface exists in `SweepExecutor`,
Permit2 integration already uses `SignatureTransfer` exclusively with exact amounts,
`msg.sender == plan.owner` was already enforced, and balance-delta plan isolation was
already the most heavily tested part of the codebase (Phase 4's 8,192-call invariant
suite). Full citation-backed comparison in `docs/security-addendum-review.md`.

**Two real hardening items identified and fixed** (not exploits — reasonable
defense-in-depth the review asked for):

1. **`executionPlanHash` now binds `chainId` and the executor's own address explicitly.**
   `SweepPlanLib.hashPlan` gained two new leading parameters. This was not fixing an
   exploitable gap — Permit2's own EIP-712 domain separator already includes chainId and
   its own address, and Permit2 already binds the spender to `msg.sender` at signing
   time (proven by the existing `test_wrongSpender_fails`) — but making it explicit in
   TIDYR's own plan hash removes the reliance on an implicit upstream property. Golden
   vector A's hash changed as a direct, expected, and re-verified consequence:
   `0xdf7a8dd0108003ffa8b036d6471d7a6479a56d02b6b7737737c398e3515100d1`, cross-checked
   byte-identical in both Solidity and TypeScript.
2. **`freezeConfiguration()` added to `SweepExecutor`, `PancakeV2Adapter`, and
   `UniswapV3Adapter`.** Once called (owner-only, irreversible), the adapter and
   output-token registries can never change again — mitigating a compromised/coerced
   owner registering a malicious adapter after users have started trusting a live
   deployment. `recoverStrayTokens` deliberately remains available afterward since it's
   unrelated to the execution security boundary.

**One audit-clarity addition:** `test_multicall3_rejectedAsUnregisteredAdapter` proves
the real, verified Multicall3 address is rejected the same way any other unregistered
address would be — not because it was previously reachable (it wasn't), but because a
named test is better evidence than "it's just not in the allowlist."

**Explicitly deferred, not faked:** dynamic token discovery, the pricing/oracle
service, and the three-layer transaction-review signing gate all belong to Phase 11/12,
which haven't been reached yet. Rather than build disconnected stub code against
infrastructure that doesn't exist, these are documented as binding design intent in
`docs/token-support-model.md` and `docs/pricing-and-oracle-model.md`, with the one
TS-level test the review specifically asked for
(`approvalBuilder_rejectsMulticall3AsSpender`) explicitly tracked as a Phase 11
requirement in `docs/implementation-plan.md` rather than written against code that
doesn't exist.

**Files created:**

- `docs/security-addendum-review.md`, `docs/approval-architecture.md`,
  `docs/permit2-witness-model.md`, `docs/token-support-model.md`,
  `docs/pricing-and-oracle-model.md`
- `artifacts/security-addendum/findings.md` (17-item P0–P3 table),
  `artifacts/security-addendum/test-results.md`

**Files changed:**

- `packages/contracts/src/libraries/SweepPlanLib.sol` (`hashPlan` signature),
  `packages/transaction-review/src/executionPlanHash.ts` (mirrored)
- `packages/contracts/src/SweepExecutor.sol`,
  `src/adapters/{PancakeV2Adapter,UniswapV3Adapter}.sol` (freeze mechanism +
  `hashPlan` call-site update)
- All test files that sign a plan (`SweepPlanLib.t.sol`, `Permit2Witness.t.sol`,
  `SweepExecutor.t.sol`, `SweepExecutorAdapterIntegration.t.sol`,
  `SweepExecutorInvariants.t.sol`) updated for the new `hashPlan` signature
- `test-vectors/golden-vectors.md` (new hash + revision history entry)
- `docs/implementation-plan.md` (Phase 11 row: tracked Multicall3-rejection
  approval-builder test requirement)

**Commands executed and results:**

```
forge build                                                             -> successful
forge test --no-match-path "*.fork.t.sol" --no-match-contract SweepExecutorInvariantsTest
                                                                         -> 87 passed, 0 failed
forge test --match-path "*.fork.t.sol"                                  -> 2 passed (live Monad mainnet)
forge test --match-contract SweepExecutorInvariantsTest                 -> 2 invariants passed (8192 calls)
pnpm typecheck / build / test / lint / format                           -> all clean; transaction-review: 16 tests
bash scripts/scan-secrets.sh                                            -> no secret patterns found
forge snapshot                                                          -> packages/contracts/.gas-snapshot updated
```

**Unresolved risks:** none new. See `artifacts/security-addendum/findings.md` for the
full disposition (P2/P3 items are tracked design-intent for Phase 11/12, not silent gaps).

**Next:** Phase 7 as originally planned — Slither, expanded fuzz/invariant/fork
coverage, gas review, threat-model documentation.

---

## Independent Codex Audit and Remediation (branch `fix/security-addendum-before-phase-7`)

**Trigger:** an independent audit of the security-addendum review above (files dropped
into `audit/` — `codex-addendum-audit.md`, `codex-addendum-findings.json`,
`codex-addendum-requirements.md`, `codex-addendum-command-log.md`), verdict **FAIL**:
P0 0 · **P1 1** · P2 7 · P3 2. Per the operating rules, Phase 7 did not begin until the
P1 was resolved.

**The P1 (CA-01) was real, not a false alarm — verified directly before fixing:**
`registerAdapter` accepted any nonzero address (including Multicall3's real address),
and `freezeConfiguration` never checked whether a registered adapter's own
configuration was itself frozen. The previously-added `test_multicall3_rejectedAsUnregisteredAdapter`
proved only the _default_ (never-registered) state — not that registration itself was
blocked, nor that a registered-but-still-mutable adapter would be caught before the
executor's freeze permanently "blessed" it.

**Fix:**

1. `registerAdapter` now explicitly reverts (`AdapterIsMulticall3`) for Multicall3's
   real, verified address, regardless of owner action.
2. `freezeConfiguration` now requires every currently-registered (and still-allowed)
   adapter to itself report `configurationFrozen() == true` (via a new
   `IFreezableAdapter` interface), reverting `RegisteredAdapterNotFrozen(adapter)`
   otherwise. A "frozen" `SweepExecutor` is now only achievable once every adapter it
   can still reach is itself frozen — closing the actual gap CA-01 identified.
3. Adapters removed via `removeAdapter` before freezing are correctly exempt (no longer
   reachable, so their own mutability is no longer relevant).

**Regression tests added:** `test_registerAdapter_rejectsMulticall3Explicitly`,
`test_freezeConfiguration_revertsIfRegisteredAdapterNotFrozen`,
`test_freezeConfiguration_succeedsWhenAllRegisteredAdaptersFrozen`,
`test_freezeConfiguration_ignoresRemovedAdapters` — each directly reproduces the
audit's stated reproduction steps and proves they now fail/succeed as required.

**The nine P2/P3 findings were also all resolved, not just the P1** (CA-02 through
CA-10, excluding CA-01; an earlier version of this line and `findings.md`'s own summary
miscounted this as eight — RA-04 correction, see below):

- **CA-02** (freeze readiness) — same fix as CA-01.
- **CA-03** (Multicall3-as-recipient overclaim) — corrected the documentation rather
  than adding code: `plan.recipient` is the user's own chosen destination for their own
  funds and carries no pull authority, unlike spender/adapter/router roles. Restricting
  it would have been security theater with no corresponding threat. See traceability
  conflict C-8.
- **CA-04** (incomplete hash-mutation regression coverage) — added 6 new Solidity tests
  (`owner`/`adapter`/`routeData`/`minAmountOut`/`chainId`/`executor`) and 4 new
  TypeScript tests (`owner`/`adapter`/`routeData`/`minAmountOut`; `chainId`/`executor`
  already existed) closing a real gap: this sensitivity had been verified once by an
  ephemeral, non-retained mutation script, not committed as regression coverage.
- **CA-05/CA-06** (untracked Phase 11/12 pricing/generic-token deferrals) — added
  explicit, named acceptance-test requirements to `docs/implementation-plan.md` and
  `docs/requirements-traceability.md` so a later phase can't satisfy a vague gate
  without actually implementing the promised boundary.
- **CA-07** (false "no Multicall3 matches" grep claim) — corrected in
  `docs/security-addendum-review.md`, `artifacts/security-addendum/test-results.md`,
  and `findings.md`. The real, reproducible result: vendored dependencies
  (`packages/contracts/lib/`) contain many unrelated Multicall matches (OpenZeppelin's
  own call-batching utility, forge-std's own Multicall3 helper); TIDYR's own production
  source had zero matches before this remediation and 3 legitimate, intentional matches
  after (the fix itself).
- **CA-08** (claimed-passing `forge fmt --check` actually failed) — ran `forge fmt`,
  verified `forge fmt --check` now passes cleanly from `packages/contracts`.
- **CA-09** (stale hash/count references in traceability) — updated to the current
  golden vector and test counts; confirmed no other current-state document still cites
  the pre-addendum hash (the one remaining reference, in this file's own Phase 2
  history section above, is correctly historical — it documents what was true then).
- **CA-10** (findings.md's own severity-count table didn't match its summary) —
  corrected.

**Commands executed and results:**

```
forge build                                                          -> successful
forge fmt --check (from packages/contracts)                          -> clean (was failing, CA-08 fixed)
forge test --no-match-path "*.fork.t.sol" --no-match-contract SweepExecutorInvariantsTest
                                                                      -> 97 passed, 0 failed (was 87 - +10 new tests)
forge test --match-path "*.fork.t.sol"                               -> 2 passed (live Monad mainnet)
forge test --match-contract SweepExecutorInvariantsTest              -> 2 invariants passed (8192 calls each)
pnpm typecheck / build / test / lint / format                        -> all clean; transaction-review: 20 tests (was 16 - +4 new)
bash scripts/scan-secrets.sh                                         -> no secret patterns found
rg -n -i multicall packages/contracts/src ...                        -> 3 matches, all the intentional CA-01 fix
forge snapshot                                                       -> packages/contracts/.gas-snapshot updated
```

**Unresolved risks:** none new. P2 items CA-05/CA-06 (pricing/generic-token deferrals)
now have explicit tracked acceptance tests for Phase 11/12 rather than being resolved
immediately — appropriately, since implementing them now would mean building
disconnected code against routing infrastructure that doesn't exist yet.

**Phase 8 may not begin** (per the operating instructions — Phase 8 is mainnet
deployment tooling, several phases past where this repository currently stands; Phase 7
itself has also not yet begun). This remediation pass is ready for independent
re-audit. Once confirmed, Phase 7 (contract security verification) proceeds as
originally planned on a dedicated branch.

---

## Independent Codex Re-audit and RA-01 Remediation (architecture change)

**Trigger:** an independent re-audit of the remediation pass above (files dropped into
`audit/` — `codex-addendum-reaudit.md`, `codex-addendum-reaudit-findings.json`,
`codex-addendum-reaudit-matrix.md`, `codex-addendum-reaudit-command-log.md`), verdict
**FAIL**: P0 0 · **P1 1** · P2 2 · P3 2. Phase 7 did not begin until the P1 was
resolved.

**The P1 (RA-01) was real, not a false alarm:** `SweepExecutor.registerAdapter` still
accepted any contract and `freezeConfiguration` still trusted that contract's own
self-reported `configurationFrozen()` value. `MockAdapter` was direct evidence the
predicate was forgeable — its `configurationFrozen` defaulted to `true` while its
mode/ratio/reported-frozen-flag all remained mutable after "freezing." A malicious or
upgradeable adapter could return `true`, be permanently blessed, and change behavior
afterward.

**Fix — the adapter registry was removed entirely, not patched further:**

1. `SwapAction.adapter` (an arbitrary `address`) replaced with `SwapAction.adapterKind`,
   a closed `SweepPlanLib.AdapterKind` enum (`PANCAKE_V2 = 0`, `UNISWAP_V3 = 1`).
2. `SweepExecutor` now takes `pancakeV2Adapter_` and `uniswapV3Adapter_` as immutable
   constructor arguments (`PANCAKE_V2_ADAPTER`, `UNISWAP_V3_ADAPTER`) — fixed for the
   contract's lifetime, resolved per-swap via `_adapterFor`.
3. `registerAdapter`, `removeAdapter`, `allowedAdapters`, `_registeredAdapterList`,
   `MULTICALL3_ADDRESS`, `AdapterIsMulticall3`, `AdapterNotAllowed`,
   `RegisteredAdapterNotFrozen`, and `IFreezableAdapter.sol` are all deleted — not
   deprecated, not hidden behind a flag.
4. `freezeConfiguration()` initially dropped all adapter-related checks (later
   revisited — see "Follow-up hardening" below).
5. Any out-of-range `AdapterKind` ordinal is rejected by Solidity's own ABI decoder
   before `executeSweep`'s body runs — a language-level guarantee, not a runtime check.

This also resolves **RA-03** (P2, unbounded adapter-history gas growth in
`freezeConfiguration`) as a side effect: there is no adapter history to iterate anymore.

**Regression tests:** the four CA-01-era adapter-lifecycle tests
(`test_unregisteredAdapter_reverts`, `test_multicall3_rejectedAsUnregisteredAdapter`,
`test_registerAdapter_rejectsMulticall3Explicitly`,
`test_freezeConfiguration_revertsIfRegisteredAdapterNotFrozen`,
`test_freezeConfiguration_succeedsWhenAllRegisteredAdaptersFrozen`,
`test_freezeConfiguration_ignoresRemovedAdapters`) were removed because the mechanism
they tested no longer exists, and replaced with tests proving the new architecture
directly: `test_invalidAdapterKindOrdinal_revertsAtAbiDecode` (proves the ABI-decode
guarantee the whole design relies on) and `test_registerAdapterSelector_noLongerExists` /
`test_removeAdapterSelector_noLongerExists` (prove the functions are gone from the
ABI, not merely input-validated). `test_maliciousReentrantAdapter_reverts` was
rewritten to deploy its own `SweepExecutor` instance with the reentrant mock wired at
construction (adapters can no longer be registered post-deployment).

### Follow-up hardening: constructor validation and freeze coupling

A narrow follow-up review of the RA-01 remediation found two remaining gaps, both
fixed in the same pass:

1. **Constructor validated only nonzero-ness.** An EOA, a duplicate adapter pair, or
   Multicall3's own real address could be wired into either fixed slot. **Fixed:** the
   constructor now reverts on no-code addresses (`AdapterHasNoCode`), a duplicate pair
   (`DuplicateAdapterAddress`), or Multicall3's verified real address in either slot
   (`AdapterIsMulticall3` — reintroduced, but as a constructor-time check against an
   immutable slot, not a runtime registry check).
2. **Freeze said nothing about adapter-level mutable config.** Each fixed adapter's
   own intermediate-asset allowlist remained separately owner-mutable indefinitely
   after "freezing" the executor. **Fixed:** `freezeConfiguration()` now reverts
   (`AdapterNotYetFrozen`) unless both `PANCAKE_V2_ADAPTER` and `UNISWAP_V3_ADAPTER`
   have already frozen themselves — reading `configurationFrozen()` from exactly the
   two specific, immutable-address contracts fixed at construction, not an arbitrary
   registry, so this does not reintroduce RA-01's forgeable-trust pattern.

New tests: `test_constructor_rejectsAdapterWithNoCode`,
`test_constructor_rejectsDuplicateAdapterPair`,
`test_constructor_rejectsMulticall3InEitherSlot`,
`test_freezeConfiguration_revertsUnlessBothAdaptersFrozen`, and
`test_swapsUnaffectedByFreezeState` (proves swaps are unaffected by freeze state
either way, since only output-token mutation functions are freeze-gated).
`MockAdapter` regained a minimal `configurationFrozen`/`freezeConfiguration()` pair so
tests can control it directly. `forge test` now passes **103/103** (was 99).
Also fixed the stale CA-07 evidence this follow-up surfaced in
`artifacts/security-addendum/test-results.md` (a grep-match count and an
`action.adapter` reference both predating this session's renames).

**RA-02** (P2, freeze-readiness gaps/weak mock-only coverage) is moot — the freeze
mechanism it concerned no longer exists.

**RA-04** (P3, "eight" vs. nine P2/P3 findings) and **RA-05** (P3, stale absolute
no-Multicall3-references claims left uncorrected in some places) are fixed in this
pass — see the corrections in `artifacts/security-addendum/findings.md`,
`docs/security-addendum-review.md`'s new addendum section, and
`docs/approval-architecture.md`.

**Commands executed and results:**

```
forge build                                                          -> successful (src/ and full)
forge fmt --check (from packages/contracts)                          -> clean
forge test                                                           -> 103 passed, 0 failed (was 97 pre-RA-01; +6 net across both hardening passes)
pnpm typecheck / build / lint / format                               -> all clean
pnpm test                                                            -> transaction-review: 20 tests, all passing incl. new golden vector
```

**Golden vector A's `executionPlanHash` changed** as a direct, expected consequence of
`adapter` (address) → `adapterKind` (uint8 enum) — see `test-vectors/golden-vectors.md`
for the new value and revision history entry.

**Remaining P2 (tracked, not a Phase-7 blocker):** a follow-up independent review's
verdict was **CONDITIONAL PASS** (P0 0 · P1 0 · P2 1 · P3 0) — the two P1s above are
resolved, but only under an explicit deployment-time trust boundary: the constructor
checks (no-code/duplicate/Multicall3 rejection) narrow _which_ addresses can be wired
into the two immutable adapter slots, but cannot themselves prove the deployed
bytecode there is genuinely the audited `PancakeV2Adapter`/`UniswapV3Adapter` source.
Fixed by adding an explicit Phase 9 gate rather than leaving this an implicit
assumption: `docs/requirements-traceability.md`'s Section 2 now has a row requiring
the deploy script to read back `SweepExecutor.PANCAKE_V2_ADAPTER()`/
`UNISWAP_V3_ADAPTER()` post-deployment and assert each matches the independently
deployed, source-verified adapter address from the same run, recorded in
`deployments/mainnet.json`.

**Phase 8 may not begin. Phase 7 has still not begun.** This remediation pass is ready
for independent re-audit. Once confirmed, Phase 7 (contract security verification)
proceeds as originally planned on a dedicated branch.
