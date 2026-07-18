# TIDYR Frontend Architecture (Phase F0)

Companion to [`frontend-integration-matrix.md`](./frontend-integration-matrix.md)
and [`frontend-state-machine.md`](./frontend-state-machine.md). Read
`frontend-integration-matrix.md` first — it establishes that this is a
chain-only build (no backend exists yet).

## Stack

| Concern | Choice | Why |
|---|---|---|
| Framework | Next.js 15, App Router | PRD §13 specifies Next.js; App Router is current stable |
| UI runtime | React 19 | Next 15 default |
| Styling | Tailwind CSS v4 (`@theme`) | `design.md` ships Tailwind v4 tokens directly |
| Wallet | wagmi v2 + viem | PRD §13 specifies wagmi + viem |
| Server/chain state | TanStack Query | wagmi's own dependency; reused directly, no second cache |
| Local workflow state | Zustand | PRD §13 specifies Zustand |
| Validation | Zod (via `@tidyr/shared`) | reuse existing schemas, no duplication |
| Fonts | `next/font/google` (Space Grotesk, Inter, IBM Plex Mono) | no private Britti Sans binaries; see design-interpretation notes below |

## Package layout

```
apps/web/
├── src/
│   ├── app/                       ← Next.js App Router routes
│   │   ├── layout.tsx
│   │   ├── page.tsx                (landing)
│   │   ├── opengraph-image.tsx     (next/og)
│   │   ├── twitter-image.tsx
│   │   ├── robots.ts
│   │   ├── sitemap.ts
│   │   ├── manifest.ts
│   │   ├── app/                    (the workspace, routed at /app)
│   │   │   ├── layout.tsx
│   │   │   ├── page.tsx
│   │   │   ├── wallets/page.tsx
│   │   │   ├── review/page.tsx
│   │   │   ├── execute/page.tsx
│   │   │   └── report/[manifestHash]/page.tsx
│   │   ├── demo/page.tsx
│   │   ├── security/page.tsx
│   │   └── contracts/page.tsx
│   ├── components/
│   │   ├── ui/            (button, card, input, badge, tabs, dialog, sheet,
│   │   │                    tooltip, skeleton, progress, empty-state,
│   │   │                    error-state, address, toast)
│   │   ├── brand/          (wordmark, pixel-field, protocol-mark-slot)
│   │   ├── layout/          (container, section, app-shell)
│   │   ├── landing/         (hero, product-preview, problem, workflow,
│   │   │                     monad-section, security-section, contracts-table,
│   │   │                     demo-cta, footer)
│   │   └── workspace/       (wallet-card, token-row, action-planner,
│   │                         review-card, signature-queue, execution-monitor,
│   │                         report)
│   ├── lib/
│   │   ├── deployment.ts           ← generated from deployments/mainnet.json
│   │   ├── abi/                    ← re-exported ABI fragments from
│   │   │                              packages/contracts/out
│   │   ├── chain.ts                ← viem public client, Monad chain def
│   │   ├── wagmi.ts                ← wagmi config (connectors, chain)
│   │   ├── routing/                ← chain-only route discovery (factory +
│   │   │                              quoter reads) — NOT packages/routing
│   │   ├── review/                 ← calldata decode-and-compare, simulation
│   │   │                              (eth_call staticcall), diff builder
│   │   ├── execution/              ← chain-only execution monitor (receipt
│   │   │                              polling) — NOT packages/execution
│   │   └── format.ts                ← address/amount/hash formatting
│   ├── store/                       ← Zustand stores (wallets, plan, execution)
│   └── styles/globals.css
├── scripts/generate-deployment-config.mjs
├── next.config.ts
├── tailwind is config-free (v4 CSS-first `@theme`)
├── package.json
└── tsconfig.json
```

## Design interpretation (binding rules, not suggestions)

- `design.md` is a Lightdash style reference. Its literal copy, "Lightdash"
  identity, and Britti Sans binary are **not** reused. Its tokens, spacing,
  radii and restraint principles **are**.
- Font substitution (already flagged as acceptable in `design.md` itself):
  Space Grotesk 600/500 replaces Britti Sans Semibold/Medium at display and
  section-heading tiers; Inter stays for body/UI; IBM Plex Mono is added for
  hashes/addresses/calldata (not present in the Lightdash reference, required
  by the PRD's transaction-review surface).
- Radius contradiction in `design.md` (§"Tokens — Colors" agent-prompt example
  shows a pill-radius primary button, but the structural token table specifies
  `--radius-buttons: 8px`) is resolved in favor of the structural rule: **8px
  for buttons/inputs/nav, pill (999px) reserved for badges/tabs/status only.**
- One saturated violet CTA per viewport (`#5e4cff`) is enforced as a review
  checklist item during F2/F17, not just a guideline.
- The pixel-grid/mosaic motif is reinterpreted as a "cleanup fragments
  resolving into an ordered grid" — thematically tied to TIDYR's actual
  product (messy wallets → tidy plan), not copied wholesale from the Lightdash
  hero.

## State separation (Phase F6 detail)

1. **Server/chain state (TanStack Query)** — anything read from an RPC: wallet
   balances, `allowedOutputTokens`, pool addresses, quotes, simulation
   staticcalls, receipt polling, `SweepCompleted` log queries. Keyed by
   `[chainId, address, blockTag]`-shaped query keys so refresh/invalidation is
   explicit and stale data never silently persists across a chain-state change.
2. **Local plan state (Zustand)** — selected wallets, per-token action
   assignment, output-token choice, recipients, UI preferences (expanded rows,
   filters). Persisted to `localStorage` under the storage policy in
   `frontend-integration-matrix.md` §5 (address/label/watch-only/primary-wallet
   only — never signatures or calldata beyond the active resumable manifest ID
   and locally-submitted tx hashes).
3. **Execution state (Zustand + TanStack Query hybrid)** — per-wallet signature
   graph status, submitted hashes (persisted), polled receipt/commitment
   status (not persisted, re-derived on load from the persisted hashes).

See `frontend-state-machine.md` for the full state diagrams.

## What ships now vs. what is explicitly deferred

This document, `frontend-integration-matrix.md`, and
`FRONTEND_COMPLETION_REPORT.md` are the three places that track real vs.
deferred scope. The completion report is authoritative on exact phase status
at any point in time — this file describes the target architecture regardless
of how much of it is built yet.
