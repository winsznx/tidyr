# TIDYR Staging Deployment Report

**Status: Staging preview deployed.** This is not "TIDYR production complete" —
F11–F20 remain paused, no backend services exist, and the frontend is an
honest, intentionally-limited preview (see §13).

## 1. Protocol freeze transactions

| Step                                         | Tx hash                                                              | Block    | Gas used |
| -------------------------------------------- | -------------------------------------------------------------------- | -------- | -------- |
| F1: `PancakeV2Adapter.freezeConfiguration()` | `0xa812372ff9cb9220fa3f4c9876b16c7c441370772aaab51f6a527c58f2281d27` | 88614826 | 75,000   |
| F2: `UniswapV3Adapter.freezeConfiguration()` | `0x3dd1e8aa9b12510aa6b1a82b6aa74099524d52db952fed99710c16868fe5efdc` | 88618447 | 75,000   |
| F3: `SweepExecutor.freezeConfiguration()`    | `0x68317c9292361bf8fbfc9441b9284f4e801e42447b4685e058924f34f0b6b6b6` | 88618636 | 125,000  |

Full Phase 10 lineage (route proof → confirmation packet → economics review →
real smoke test → freeze) is in `PHASE_10_COMPLETION_REPORT.md`.

## 2. Final frozen-state reads (independently verified after each tx)

- `SweepExecutor.configurationFrozen() == true`
- `PancakeV2Adapter.configurationFrozen() == true`
- `UniswapV3Adapter.configurationFrozen() == true`
- `allowedOutputTokens`: MON_SENTINEL = `true`, USDC = `true`; WMON and all 5
  DUST tokens = `false` — permanently locked, confirmed live
- Post-freeze mutation attempts (`registerOutputToken`,
  `allowIntermediateAsset`) confirmed reverting with `ConfigurationIsFrozen()`

## 3. Release branch

`release/web-staging`, created from `frontend/production-lifecycle` and
merged with `protocol/phase-10-mainnet-smoke` (`--no-ff`, no conflicts, no
history rewritten, no branch discarded).

## 4. Final commit

`530dff2` — `fix: upgrade next to patch a critical security advisory`

Commits on this branch (newest first): `530dff2`, `1cb7cc0`, `9f1c361`,
`8945714`, `a389ce4`, `6b39172`, `96ee951` (merge), plus everything inherited
from `frontend/production-lifecycle` and `protocol/phase-10-mainnet-smoke`.

## 5. Local validation commands

```bash
pnpm install --frozen-lockfile
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm build
node apps/web/scripts/generate-deployment-config.mjs
```

All passed. Full detail, including the one real unit-test suite added to
unblock `pnpm test` (apps/web previously had zero test files), in
`artifacts/frontend/local-smoke-test.md`.

## 6. Tested routes

`/`, `/app`, `/app/wallets`, `/app/review`, `/app/execute`, `/demo`,
`/security`, `/contracts`, `/opengraph-image`, `/icon.svg`,
`/manifest.webmanifest`, `/robots.txt`, `/sitemap.xml`, `/api/health` — all
200 on both the local dev/production server and the live Railway staging
domain.

## 7. Responsive viewports

**Not verified with a real browser** — no headless browser (Playwright/
Puppeteer) was available in this environment. CSS uses relative units and
the existing `Container`/Tailwind responsive classes throughout by
construction, but 375×812 / 768×1024 / 1440×900 layout, horizontal-overflow,
and hydration-console-error checks were not visually confirmed. Flagged as a
required follow-up before wide sharing (see §15).

## 8. Railway project / environment / service

| Field       | Value                                                        |
| ----------- | ------------------------------------------------------------ |
| Project     | `tidyr-web-staging` (`49b04512-d393-416b-b431-ddd78b01ec29`) |
| Environment | `staging`                                                    |
| Service     | `tidyr-web-staging` (`99b55d16-f360-40b8-b626-61157c74b901`) |

## 9. Railway staging URL

**https://tidyr-web-staging-staging.up.railway.app**

## 10. Build and start commands

- Build: `pnpm install --frozen-lockfile && node apps/web/scripts/generate-deployment-config.mjs && pnpm --filter @tidyr/web build`
- Start: `pnpm --filter @tidyr/web start` (binds to Railway's `$PORT` — confirmed in runtime logs as port 8080, never hardcoded to 3000)

## 11. Healthcheck result

`GET /api/health` → `200 {"status":"ok","service":"tidyr-web"}`, verified on
the live staging domain. No RPC or database call in the handler.

## 12. Environment variable names (no secret values)

- `NEXT_PUBLIC_SITE_ORIGIN` = `https://tidyr-web-staging-staging.up.railway.app`
- `NEXT_PUBLIC_MONAD_RPC_URL` = `https://rpc.monad.xyz`

`NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` was **not** set — no real project ID
is available; the code already degrades gracefully (injected-only wallet
connection, WalletConnect connector simply omitted) rather than shipping
half-configured. No private key, admin credential, or explorer API secret
exists in this service's configuration.

## 13. Confirmed disabled functionality

Verified by direct code search and live HTTP checks against the deployed
staging domain:

- No Permit2 signing call exists anywhere in `apps/web`
- No `executeSweep` call exists anywhere in `apps/web`
- No admin/deployer action (`freezeConfiguration`, `registerOutputToken`,
  etc.) exists in the frontend
- No `DEPLOYER_PRIVATE_KEY` or any private-key environment variable exists
  in the frontend/runtime configuration
- `/app/review`, `/app/execute`, `/app/report/[hash]` render static
  `EmptyState` placeholders naming their pending build pass — no wiring to
  calldata decoding, simulation, or event reads
- Revoke, Top-up, and Multi-send are absent from the action planner (not
  stubbed, not faked)
- Sell is gated on "route candidate" language only — no code path claims
  `canSell = true`
- The workspace shell shows "Preview environment — transaction preparation
  and execution services are not yet enabled" on every `/app/*` route
- No fixture data exists inside the real application workspace (the
  landing page's illustrative product preview is explicitly labeled and
  uses only real deployed token addresses, not fabricated ones)

## 14. Console / runtime errors

- Build logs: clean after the Next.js security-patch upgrade (see below).
  One blocked build attempt is recorded and resolved, not hidden — see §16.
- Runtime logs (`railway logs`): clean startup, `Ready in 286ms`, no errors.
- Rendered HTML and all downloaded JS chunks on the live staging domain:
  searched for private-key/API-key patterns — no matches.

## 15. Remaining backend and frontend blockers

- **Backend**: no API, indexer, routing/pricing, or execution-monitoring
  service exists. F11–F14 remain paused pending those services (per the
  standing recalibration — not touched in this pass).
- **Frontend**: F15–F20 not started (demo lifecycle beyond a static info
  page, full loading/empty/error hardening pass, accessibility pass beyond
  what's built, comprehensive test suite, further performance/security
  hardening).
- **This pass specifically**: no real browser/viewport QA, no wallet
  extension used for real connect-flow testing (see `artifacts/frontend/local-smoke-test.md` §Limitations).
- Two duplicate `ChatGPT Image...` PNGs remain untracked in
  `apps/web/public/` pending a decision on whether to keep them for a future
  profile-icon use case — not committed, per instruction to commit only the
  four approved assets.

## 16. Notable event during this deployment

Railway's build gate blocked the first deploy attempt outright with a
**CRITICAL** security advisory (CVE-2025-66478, among four affecting
`next@15.1.3`). Fixed by upgrading to `next@15.1.12` (same minor line, no
API changes) rather than bypassing the gate — re-verified clean
typecheck/test/build before redeploying. Recorded in commit `530dff2`.

## 17. Is staging safe to share publicly?

**Yes, with the caveat in §7 and §15.** No secrets are exposed, no
transaction can be signed or broadcast from the frontend, and every
incomplete surface honestly labels itself rather than faking functionality.
The unverified item is purely cosmetic/QA (real-browser responsive and
hydration testing was not performed here) — it does not create a security or
data-integrity risk, but should be closed before treating this as a
polished public artifact rather than an internal preview link.

---

**Staging preview deployed.**
