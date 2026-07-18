# TIDYR Frontend — Asset Requests (Phase F3)

Everything below is served today by a code-generated placeholder
(`next/og` `ImageResponse` routes or inline SVG/CSS) so the frontend never
blocks on final art. Each placeholder can be replaced with the real file at
the same route/path with no layout change. Nothing here blocks any other
phase.

## 1. `icon.svg` / protocol mark

- **Current placeholder:** `apps/web/src/app/icon.tsx` — a 32×32 solid violet
  (`#5e4cff`) rounded square, generated at request time via `next/og`.
- **Dimensions:** 32×32 (favicon), scalable SVG preferred so it also covers
  larger sizes (180×180 apple-touch-icon, 512×512 PWA icon) from one source.
- **Aspect ratio:** 1:1.
- **Background:** transparent (the current placeholder uses solid white —
  the real mark should work on both light and dark browser chrome).
- **Colors:** `#5e4cff` primary; `#c8ccf3` / `#dfdbff` as optional secondary
  tones if the mark has more than one shape.
- **Placement:** browser tab, PWA home-screen icon, `apps/web/src/app/icon.tsx`
  replacement (or a static `icon.svg` dropped into `apps/web/src/app/`, which
  Next.js picks up automatically by file-convention).
- **Safe area:** keep the mark inside the inner 80% of the canvas — some
  platforms crop icon corners into a circle.
- **Image-generation prompt (if using an AI image tool):** "A minimal
  geometric app icon mark for a crypto wallet-cleanup tool called TIDYR, one
  solid saturated violet (#5e4cff) shape suggesting tidiness or a cleaned
  grid, on a transparent background, flat, no gradient, no text, no
  photorealism, works at 32px."
- **SVG suitability:** yes, strongly preferred (crisp at all sizes, small
  file size).
- **Max file size:** 15 KB (SVG) / 40 KB (PNG fallback).
- **Fallback behavior:** current `icon.tsx` code-generated square remains in
  place until replaced.

## 2. `opengraph-image.png` (Open Graph / link-preview card)

- **Current placeholder:** `apps/web/src/app/opengraph-image.tsx` —
  code-generated via `next/og`, matches the exact composition below.
- **Dimensions:** 1200×630.
- **Aspect ratio:** 1.91:1.
- **Background:** solid white or cloud-mist (`#f6f8fa`).
- **Colors:** `#36394a` heading text, `#666d80` body, `#5e4cff` / `#c8ccf3`
  pixel accents, `#5e4cff` status dot.
- **Composition (already implemented in code):** TIDYR wordmark top-left;
  headline "Clean every Monad wallet without blindly signing." large,
  left-aligned; a row of small violet pixel tiles beneath the headline;
  "Live on Monad mainnet" status line bottom-left with a violet dot.
- **Placement:** link previews (Twitter/X, Slack, Discord, iMessage).
- **Safe area:** keep all text within a 1100×530 centered box — some
  platforms crop edges.
- **Image-generation prompt:** "A clean OG social card, 1200x630, white
  background, small violet square logomark top-left, large dark slate
  headline text 'Clean every Monad wallet without blindly signing.', a short
  row of small violet pixel squares below the headline, a small violet dot
  and 'Live on Monad mainnet' caption bottom-left, no illustration, no
  gradient, no stock photography, flat and technical."
- **SVG suitability:** no (Open Graph requires a raster image; PNG/JPEG only).
- **Max file size:** 300 KB (most platforms reject OG images above ~5 MB, but
  smaller loads faster in link unfurls).
- **Fallback behavior:** the code-generated route always renders — a final
  static PNG can simply replace the route's export, or be dropped in as
  `opengraph-image.png` (Next.js file convention) to skip the dynamic route
  entirely.

## 3. `twitter-image.png`

- **Current placeholder:** re-exports `opengraph-image.tsx` directly
  (`apps/web/src/app/twitter-image.tsx`).
- Same spec as §2. A distinct Twitter-specific crop is optional, not required.

## 4. Social header (1500×500)

- **Current placeholder:** none rendered anywhere yet — no UI surface in this
  build uses a profile-style social header. Documented here only because the
  brief requests a specification for it.
- **Dimensions:** 1500×500.
- **Aspect ratio:** 3:1.
- **Background:** solid white or `#f6f8fa`.
- **Colors:** same palette as the OG image.
- **Composition suggestion:** wordmark + a wider strip of the pixel-fragment
  motif, no headline text (social headers are usually cropped differently per
  platform, so avoid load-bearing copy).
- **Placement:** X/Twitter or GitHub organization profile header, if TIDYR
  creates one.
- **Safe area:** keep all content within the centered 1200×470 region.
- **SVG suitability:** no (profile headers are raster on every platform that
  uses this dimension).
- **Max file size:** 2 MB (most platforms' upload cap for profile headers).
- **Fallback behavior:** none needed — no route currently depends on this
  asset.

## 5. Profile icon (400×400)

- **Current placeholder:** none — same reasoning as §4; only the browser
  favicon (§1) is actually consumed by this build.
- **Dimensions:** 400×400.
- **Aspect ratio:** 1:1.
- **Background:** transparent or white.
- **Colors:** same as §1.
- **Composition:** the protocol mark alone, larger and centered, no wordmark
  text (avatar-sized crops rarely fit text legibly).
- **Placement:** GitHub org avatar, X/Twitter profile photo, if created.
- **Safe area:** inner 85% circle (most platforms crop avatars to a circle).
- **SVG suitability:** source in SVG, export a PNG for upload (most avatar
  upload flows don't accept SVG).
- **Max file size:** 1 MB.
- **Fallback behavior:** none needed — not referenced by any route.

## What is NOT requested

No hero product screenshot, no illustration, no photography, no partner/
customer logos, no 3D renders — per `design.md`'s "Don't" list and the
brief's explicit prohibition on generic Web3 imagery. The landing page's
product-preview section is built from real UI components, not an image, and
needs no asset from this list.
