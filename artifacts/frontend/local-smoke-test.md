# Frontend Local Smoke Test

Branch: `release/web-staging`
Package: `@tidyr/web` (`apps/web`)

## Commands run (from repository root unless noted)

```bash
pnpm install --frozen-lockfile
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm build
node apps/web/scripts/generate-deployment-config.mjs   # from apps/web
```

All passed. `pnpm test` required adding one real unit test suite
(`apps/web/src/lib/format.test.ts`, 3 assertions covering `truncateAddress`/
`truncateHash`) — `apps/web` previously had zero test files, which made
`vitest run` exit 1 with "No test files found." This is not a claim that
F18 (the full test suite) is complete; it is the minimum needed for the
local-validation gate to pass honestly rather than being skipped.

## Dev server

```bash
pnpm --filter @tidyr/web dev
```

Bound to `http://localhost:3000` (printed by Next.js). No console errors or
warnings in the dev server log beyond two pre-existing, benign Next.js
notices (`Next.js plugin was not detected in your ESLint configuration`;
`metadataBase property in metadata export is not set` — both cosmetic, not
functional issues).

### Routes tested (HTTP, dev server)

| Route                                                    | Status                                            |
| -------------------------------------------------------- | ------------------------------------------------- |
| `/`                                                      | 200                                               |
| `/app`                                                   | 200                                               |
| `/app/wallets`                                           | 200                                               |
| `/app/review`                                            | 200                                               |
| `/app/execute`                                           | 200                                               |
| `/demo`                                                  | 200                                               |
| `/security`                                              | 200                                               |
| `/contracts`                                             | 200                                               |
| `/opengraph-image`                                       | 200                                               |
| `/icon.svg`                                              | 200                                               |
| `/manifest.webmanifest`                                  | 200                                               |
| `/robots.txt`                                            | 200                                               |
| `/sitemap.xml`                                           | 200                                               |
| `/api/health`                                            | 200, body `{"status":"ok","service":"tidyr-web"}` |
| `/tidyr-logo-transparent.svg`, `.png`, `tidyr-favicon-*` | 200 (real brand assets load)                      |

### Content checks

- Landing page HTML contains the real `tidyr-logo-transparent.svg` reference
  (wordmark wired in, not the code-generated placeholder).
- `/app` HTML contains the string "Preview environment" (staging notice
  renders inside the workspace shell, not on the landing page).
- The only external `target="_blank"` link in the codebase
  (`components/ui/address.tsx`'s explorer link) already carries
  `rel="noreferrer noopener"`.

## Production-mode local test

```bash
pnpm --filter @tidyr/web build
PORT=3000 pnpm --filter @tidyr/web start
curl http://localhost:3000/api/health   # {"status":"ok","service":"tidyr-web"}
curl -o /dev/null -w '%{http_code}' http://localhost:3000/                       # 200
curl -o /dev/null -w '%{http_code}' http://localhost:3000/tidyr-logo-transparent.svg  # 200
curl -o /dev/null -w '%{http_code}' http://localhost:3000/icon.svg                    # 200
```

All passed.

## Limitations — not tested in this pass

- **No real browser/viewport testing.** This environment has no headless
  browser (Playwright/Puppeteer) available. Only HTTP-level (curl) and
  server-log-level verification was performed at 375×812 / 768×1024 /
  1440×900 was **not** visually confirmed — CSS uses relative units and
  `Container`/responsive Tailwind classes throughout by construction, but
  actual rendered layout, horizontal-overflow, and React hydration-mismatch
  console errors were not observed in a real browser.
- **No wallet extension available.** Wallet connect, watch-only add,
  duplicate-wallet detection, and wrong-chain UI were verified by prior code
  review and the F5 implementation's own logic, not by driving an actual
  injected wallet provider in this pass.
- Screenshots were not produced (no browser tooling in this environment).

These limitations should be closed with a real browser-based QA pass before
treating the staging deployment as broadly shareable.
