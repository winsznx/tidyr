# TIDYR — 2-Minute Demo Video Script

Target runtime: **2:00, hard cap.** Judges watch dozens of these — the first
10 seconds decide whether they lean in or start skimming. Every second after
that should be proof, not narration.

## Before you hit record

- [ ] Two funded real wallets ready (you already have
      `0x9fe816A8bD6933464c177ba94890aEDE5CD5aA5A` and
      `0xE684c8F0626235AEC8355bEF7197092726E1b69d`, each holding MON + DUST1-5).
      Use these, or your own — either way, **use real mainnet wallets with
      real balances**, never a reset/seeded demo account. That's the single
      biggest "is this real" signal a judge checks for.
- [ ] Staging URL open and warm in a tab already:
      `https://tidyr-web-staging-staging.up.railway.app` (loading it live
      on camera burns 5-10 seconds you don't have).
- [ ] Wallet extension unlocked and connected before recording starts.
- [ ] MonadScan tab pre-opened in the background, ready to alt-tab into for
      the transaction proof at the end.
- [ ] Screen resolution: capture at 1080p minimum, browser window filling
      the frame — no other tabs/bookmarks bar visible, no personal info
      leaking in a wallet extension's account list.
- [ ] Do one full silent dry run first. If any step takes longer than
      expected (RPC latency, wallet popup lag), you need to know before
      you're on the clock.
- [ ] Script below is timed generously loose — practice it once, then trim
      your own dead air, don't just read it cold on the first take.

## Recording tools

Any screen recorder that captures a browser tab in 1080p+ works — QuickTime
(macOS, free, `Cmd+Shift+5`), OBS, or Loom. Record audio directly (a
voiceover recorded separately and dubbed over rarely syncs well for a fast
2-minute cut). Do the narration live while you click.

---

## Shot list

### 0:00–0:12 — The problem (talk to camera or voiceover over a blank tab)

> "I run multiple wallets testing chains and farming airdrops. Every one of
> them ends up littered with dust — tiny leftover tokens not worth the gas
> to deal with individually. Cleaning that up manually, wallet by wallet, is
> exactly the kind of tedious task that shouldn't need a human. This is
> TIDYR — one place to scan every wallet, decide what to do with what's in
> it, and sweep it all in one signed batch."

Keep this tight — one breath, no re-takes needed if you know it cold. This
is the only part of the video that's talking rather than showing; everything
after this is the app doing real things.

### 0:12–0:28 — Wallets page: real balances, multiple wallets

- Cut to `/app/wallets`.
- Show both wallets already added, with **real live balances** rendering
  (MON + DUST1-5). Let it sit on screen long enough to read, don't rush
  past it — this is the "yes, this is really reading the chain" beat.
- Optionally: point out one wallet is watch-only (if you have one added) to
  show it works without full wallet access too.

### 0:28–0:55 — Planning: pick real actions

- On one wallet's token list, assign a few different actions across
  different tokens: **sell** DUST3 (the one token with a real liquidity
  pool — say this out loud, it's honest and it's interesting: *"only DUST3
  actually has a market, so that's the one that gets a real sell route —
  the rest correctly show no route available"*), **consolidate** another
  token to your primary wallet, **discard** or **burn** DUST4 (the one
  demo token with a real `burn()`).
- Narrate while clicking, don't silently click for 20 seconds.

### 0:55–1:20 — Review: the real plan, hashes, and a live check

- Cut to `/app/review`.
- Show the built plan: real token amounts, the route used, the minimum
  output from a live quote, and the two hashes (`displayManifestHash`,
  `executionPlanHash`).
- Point at the round-trip/precondition badges: *"this re-checks the plan
  against the live chain — fresh nonce, valid deadline — right before I'm
  ever asked to sign anything."*
- This is the "no blind signing" beat — say that phrase or something close
  to it out loud.

### 1:20–1:40 — Sign: a real wallet signature

- Cut to `/app/execute`.
- Click "Request signature," let the real wallet extension popup appear
  on screen, approve it.
- Say: *"this is a real Permit2 signature — it authorizes exactly this
  plan, nothing else. Nothing broadcasts yet."*

### 1:40–1:55 — Execute: simulate, broadcast, confirm

- Show the auto-run simulation result (green/success badge).
- Click "Broadcast." Let the pending state show briefly.
- Cut to the confirmed state with the real transaction hash, then alt-tab
  (or cut) to the pre-opened MonadScan tab showing that exact transaction,
  live, on Monad mainnet.
- This single cut — app claims success, MonadScan independently confirms
  it — is the most convincing 3 seconds in the whole video. Don't skip it
  to save time; cut something earlier instead if you're over budget.

### 1:55–2:00 — Close

- Quick cut to `/app/report/[thatManifestHash]` showing the reconstructed
  report (real `SweepCompleted`/`Transfer` data), or just a closing line:

> "Everything you just saw is chain-only — no backend, no fake state. Real
> contracts, frozen on Monad mainnet, so what you reviewed is what actually
> ran."

Hard stop at 2:00.

---

## What NOT to do (these are exactly what the judging agent is trained to catch)

- **Don't** show a state you reset/seeded moments before recording and
  pretend it's your everyday wallet. If asked, be honest that these are
  test wallets funded for the demo — the balances and the transaction are
  still 100% real, that's what matters.
- **Don't** cut around a loading spinner by hiding it — a couple seconds of
  a real RPC read completing is *proof*, not dead air to edit out.
- **Don't** narrate what the code does ("this uses Permit2 EIP-712 typed
  data...") instead of what it means for the user ("this signs one message
  that authorizes exactly this batch"). Judges are grading practical impact,
  not architecture literacy.
- **Don't** end on a UI screenshot. End on the MonadScan confirmation or the
  report page — the artifact that exists independently of your own app.
- **Don't** pad to fill 2 minutes. A tight 1:40 with no dead air beats a
  padded 2:00 every time.

## Optional B-roll if you have time to spare after the core cut

- A 2-second shot of `SECURITY.md` or the audit verdict
  (`audit/phase-7-adversarial-audit.md`'s "CONDITIONAL PASS") scrolling by —
  useful only as a flash-cut, not something to read on screen; the video is
  about the product working, not the paperwork behind it.
