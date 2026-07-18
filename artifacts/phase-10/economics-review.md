# Phase 10.1 — Economics Review (No Broadcast)

Re-reads Monad mainnet chain ID 143 fresh this session (block 88592731,
2026-07-18), independent of the earlier confirmation packet's reads. No
transaction was broadcast in producing this review.

## 1. Verified numbers

| Item                    | Value                                                                                     | Source                                               |
| ----------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Current WMON/USDC price | 0.021454739 USDC per WMON (was 0.021499 at the last packet — real, small market movement) | fresh `slot0()` read                                 |
| Gas price               | 102 gwei (unchanged)                                                                      | fresh `cast gas-price`                               |
| Deployer MON balance    | 43.018882540 MON (unchanged)                                                              | fresh `cast balance`                                 |
| Deployer USDC balance   | **0**                                                                                     | fresh `cast call balanceOf` — confirmed, not assumed |

### Output for 200, 500, 1,000, 2,000, 5,000, 10,000 DUST3

First leg (DUST3→WMON) is **modeled** against the proposed 5 MON / 50,000
DUST3 pool (it doesn't exist on mainnet yet) using the exact Uniswap V3
in-range constant-sum formula. Second leg (WMON→USDC) is a **fresh live
`QuoterV2.quoteExactInputSingle` staticcall** against the real, existing
pool — not modeled.

| DUST3 in | Modeled WMON out (first leg) | First-leg impact | Live-quoted USDC out (second leg) | USDC out (human) | Complete-route degradation vs. zero-impact theoretical |
| -------- | ---------------------------- | ---------------- | --------------------------------- | ---------------- | ------------------------------------------------------ |
| 200      | 0.01991926                   | 0.208%           | **426** raw                       | **$0.000426**    | 0.721%                                                 |
| 500      | 0.04972057                   | 0.519%           | **1,063** raw                     | $0.001063        | 0.908%                                                 |
| 1,000    | 0.09918363                   | 1.036%           | **2,121** raw                     | $0.002121        | 1.141%                                                 |
| 2,000    | 0.19734516                   | 2.061%           | **4,220** raw                     | $0.004220        | 1.653%                                                 |
| 5,000    | 0.48585274                   | 5.074%           | **10,391** raw                    | $0.010391        | 3.136%                                                 |
| 10,000   | 0.94766267                   | 9.897%           | **20,268** raw                    | $0.020268        | 5.531%                                                 |

"Complete-route degradation" = the gap between the live-quoted output and the
zero-impact/zero-fee theoretical output (spot price × amount) — it combines
both pools' 0.3% LP fees (0.6% combined) with actual AMM-curve slippage, so
it is larger than the first-leg slippage figure alone even at small sizes.

### Integer rounding (USDC's 6 decimals)

At 200 DUST3, the output is 426–427 raw units depending on the exact
WMON/USDC spot price at read time — a swing of 1 raw unit is a ~0.23%
_relative_ difference at this size, even though it's a $0.000001 _absolute_
difference. Rounding/precision noise is proportionally much larger at
dust-level amounts than at 10,000 DUST3 (where 1 raw unit is ~0.005%
relative). This is a real consequence of USDC's 6-decimal granularity
colliding with genuinely tiny values — not a bug, but a reason dust-scale
demo amounts are inherently noisy in percentage terms even though the
absolute values are exact.

### Would the current frontend show $0.00?

**No frontend USD/price formatter exists in `apps/web` yet** — grepped for
one; F10 (pricing/quotes UI) was never reached before F11–F14 was paused.
This question is therefore hypothetical today, not a reproducible bug in
committed code. But the underlying concern is valid and quantifiable: **any
standard 2-decimal-place USD formatter (`Intl.NumberFormat('en-US', {style:
'currency', currency: 'USD'})` or equivalent) would round every value in the
200–2,000 DUST3 range to $0.00**, and even 5,000 DUST3 (25× a real demo
claim) rounds to only $0.01. This must be treated as a real constraint on
whatever pricing UI F10 eventually builds, regardless of which pool
architecture is chosen.

## 2. Slippage tightening

`minAmountOut` at each tolerance, for the 200-DUST3 case (expected 426 raw
units):

| Tolerance              | minAmountOut | Notes                                                                                                                                                                  |
| ---------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0.5%                   | 423          | Tighter than the measured 0.721% total degradation — **would revert against the exact modeled/quoted expectation**, unsafe as a hard floor                             |
| 1%                     | 421          | Still tighter than the 0.721% measured degradation baseline; leaves ~0.28% headroom for further WMON/USDC drift — marginal                                             |
| **2% (recommended)**   | **417**      | Comfortably above the 0.721% baseline degradation, leaving ~1.3% headroom for real WMON/USDC market movement between quote and broadcast                               |
| 3%                     | 413          | More headroom than needed given the measured 0.721% baseline and the short deadline window                                                                             |
| 5%                     | 404          | Excess headroom for a trade this size                                                                                                                                  |
| 10% (previous default) | 383          | The packet's original value — **41 raw units (10%) of slack against a 426-unit expected output is not justified by a measured 0.208–0.721% impact/degradation figure** |

**Recommendation: 2%.** The first leg's slippage is close to fully
deterministic (we mint the pool ourselves, in the same review cycle, so
there is no adversarial front-running window on a pool nobody else knows
exists yet) — the real uncertainty is confined to the second leg's real,
actively-traded WMON/USDC pool between quote-time and broadcast-time. Two
live reads taken ~85 minutes apart this session showed the WMON/USDC price
move by ≈0.2% (0.021499 → 0.021454739) — 2% tolerance covers roughly 10× that
observed real-world drift plus the combined 0.6% LP fee and first-leg
slippage, without leaving so much slack (10%) that a materially worse fill
would silently succeed. **A fresh quote and simulation must still be
generated immediately before signing** — this recommendation does not
substitute for that.

## 3. The two demos, and why pool size alone cannot fix the dollar-display problem

**A. Engineering smoke test** — proves Permit2, `exactInput` multihop, the
deployed adapters, the DUST3→WMON→USDC route, nonce consumption, and zero
retained executor balances. A tiny, even sub-cent, output is **acceptable
and expected** for this purpose — it is explicitly labeled as an engineering
proof, not a product experience.

**B. Consumer-facing demo** — needs an output a person looking at the TIDYR
interface would read as "something happened," not $0.00.

**Critical finding: pool depth (more MON) does not change the output of a
200-DUST3 claim — only the initial price ratio does.** A larger DUST3/WMON
pool at the _same_ 0.0001 WMON/DUST3 ratio reduces _price impact for larger
trades_; it does not increase how much a single 200-DUST3 claim is
fundamentally worth. This means "Option C" (a bigger DUST3/WMON pool) **does
not, by itself, solve the consumer-demo dollar-display problem** — it only
helps if paired with a different price ratio, which is a separate decision
(see `demo-options.md`).

## 4. Demo architecture comparison

Full detail with all four (five, including the frontend-only fix) options
modeled is in **`artifacts/phase-10/demo-options.md`**.

## 5. DemoDistributor inspection

| Question                                                                        | Answer                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Is `CLAIM_AMOUNT` immutable?                                                    | **Yes** — declared `uint256 public constant CLAIM_AMOUNT = 200 ether;` in `DemoDistributor.sol:18`. A Solidity `constant` is baked into bytecode; there is no setter.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Can the claim amount be changed?                                                | **No**, not on the currently deployed instance. Changing it requires deploying a **new** `DemoDistributor` contract (new address, new constructor).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Can inventory be replenished?                                                   | **Yes**, without redeployment — the contract has no internal ledger beyond the `claimed` mapping; anyone can `transfer` more of any of the 5 tokens directly to the existing distributor address, and `claimDemoBundle()` will draw from whatever balance it holds.                                                                                                                                                                                                                                                                                                                                                                                                            |
| Would changing the claim amount require a new deployment?                       | **Yes** — see above.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Would a new distributor invalidate existing documentation/frontend assumptions? | **Yes, materially**: `deployments/mainnet.json`, `docs/frontend-integration-matrix.md`, `PROJECT_STATUS.md`, and any frontend code (`apps/web/src/lib/deployment.ts` → `DEMO_TOKENS`, the `/demo` page) reference the current `DemoDistributor` address (`0x49552A355cCB700E8Ab18e392F1B05F0005C2d9E`) and its 200-per-token claim economics. A new distributor would need every one of those updated, and — because `claimed` state does not carry over — anyone who already claimed from the old contract could claim again from the new one, which may or may not be an intended behavior change. **No modification or redeployment was performed as part of this review.** |

## 6. Pool initialization decision

The proposed DUST3/WMON pool's initial `sqrtPriceX96` becomes the pool's
starting price permanently once `initialize()` is called — Uniswap V3 pools
have no "reset price" function; changing the effective exchange rate after
initialization would require either trading it there through arbitrage-sized
swaps (impractical and would waste the seeded liquidity) or abandoning the
pool and creating a new one at a different fee tier (fee tiers 100/500/10000
are all still free — confirmed no pool exists at any of the four tiers).

**Recommendation: Option 3** — proceed with the current DUST3/WMON pool
**only as the engineering smoke route** (Option 1 is folded into this, since
they are the same pool and the same economics), and treat the "consumer
needs to see a real number" requirement as a **separate, not-yet-decided**
question — most honestly resolved on the **frontend presentation side**
(show more precision, or a "<$0.01" affordance, for genuinely tiny dust
values) rather than by inflating DUST3's exchange rate purely to make a
number look bigger. Rationale:

- **Demo clarity**: the engineering pool's tiny output is not a bug to hide —
  it is the truthful result of sweeping a token whose entire premise is
  near-worthlessness. A "$0.10 per claim" number achieved only by picking an
  arbitrary 235× richer exchange rate would misrepresent what DUST3 is.
- **Capital efficiency**: Option B (a direct DUST3/USDC pool) turns out to be
  **not capital-feasible today** without external USDC funding — see
  `demo-options.md`; at the current live WMON/USDC price, acquiring even 1
  USDC via an on-chain swap costs **≈46.6 MON**, more than the deployer's
  entire remaining balance.
- **Safety**: initializing the engineering pool at its already-proven price
  and treating it as engineering-only removes any pressure to pick a
  consumer-facing price under time pressure before real capital is
  committed.
- **Route credibility**: preserves the already-proven, already-tested
  DUST3→WMON→USDC multihop exactly as validated; no new route needs
  re-verification.
- **Frontend presentation**: this is a code problem (number formatting), not
  a liquidity problem, and belongs in F10 (never yet built) rather than in
  a Phase 10 capital decision.

**If a visibly-larger consumer number is still wanted**, the two genuinely
capital-relevant paths are (a) fund a direct DUST3/USDC pool with externally
sourced USDC (not swapped from MON at today's price) at a deliberately
chosen, clearly-documented "demo exchange rate," or (b) accept a materially
richer DUST3/WMON ratio with the same honest caveat. Both require a
separate, explicit decision — not made in this review.
