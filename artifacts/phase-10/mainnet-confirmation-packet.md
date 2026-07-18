# Phase 10 — Monad Mainnet Confirmation Packet

**Status: PREPARED FOR REVIEW ONLY. No transaction described here has been
broadcast. Nothing in this document authorizes a broadcast — that requires
a separate, explicit approval per transaction, per the standing
confirmation-checkpoint pattern used throughout this project.**

Branch: `security/phase-7-verification` @ `5c05cbe` (protocol branch; the
frontend branch `frontend/production-lifecycle` was not merged into this
branch and is untouched by this work).

Chain: Monad mainnet, chain ID 143. All live reads below were taken at block
88584368–88590779 (2026-07-18) via `https://rpc.monad.xyz`.

---

## 1. Re-verified live state (this session, not relying on prior reports)

| Item                                                                              | Value                                                                                                                         |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Deployer address                                                                  | `0xbde0076F05B5eA898F9ca51f1b595D84598DE586`                                                                                  |
| Deployer MON balance                                                              | 43.018882540000000000 MON                                                                                                     |
| Deployer DUST3 balance                                                            | 600,000 DUST3                                                                                                                 |
| Deployer WMON balance                                                             | 0                                                                                                                             |
| Deployer USDC balance                                                             | 0                                                                                                                             |
| SweepExecutor owner                                                               | `0xbde0076F05B5eA898F9ca51f1b595D84598DE586` (matches deployer)                                                               |
| SweepExecutor `configurationFrozen()`                                             | `false`                                                                                                                       |
| MON_SENTINEL (`0xEeee...EEeE`) output-token status                                | `true` (allowed)                                                                                                              |
| Canonical USDC (`0x754704Bc059F8C67012fEd69BC8A327a5aafb603`) output-token status | `true` (allowed)                                                                                                              |
| DUST1/DUST2/DUST3/DUST4/DUST5/WMON registered as output tokens?                   | `false` for all six — confirms exactly the intended two-token output set, nothing extra                                       |
| PancakeV2Adapter address / codesize                                               | `0xBB86D6ef057F03Ca0bcaB9f87B61894977B0dBcb` / 3,393 bytes (has code)                                                         |
| UniswapV3Adapter address / codesize                                               | `0xE80d042fBDC03Da8262ED0669c75a394d2437D27` / 2,810 bytes (has code)                                                         |
| PancakeV2Adapter `configurationFrozen()`                                          | `false`                                                                                                                       |
| UniswapV3Adapter `configurationFrozen()`                                          | `false`                                                                                                                       |
| DUST3/WMON pool at fee 100/500/3000/10000                                         | **none exist** — `getPool` returns the zero address at all four tiers                                                         |
| WMON/USDC pool (fee 3000)                                                         | `0x659bD0BC4167BA25c62E05656F78043E7eD4a9da` — exists, `liquidity()` = 25,245,712,781,908,811,921 (raw), current tick -314724 |
| WMON/USDC current price                                                           | ≈0.0215 USDC per WMON (derived from live `slot0`)                                                                             |
| DemoDistributor `CLAIM_AMOUNT`                                                    | 200 ether (200 DUST3, and 200 of each of the other 4 demo tokens, per claim)                                                  |
| DemoDistributor `claimed(deployer)`                                               | `false`                                                                                                                       |
| DemoDistributor remaining DUST3 inventory                                         | 400,000 DUST3 (2,000 claims worth)                                                                                            |

**Re-confirmed against live state (already covered by
`SweepExecutor.t.sol::test_freezeConfiguration_revertsUnlessBothAdaptersFrozen`,
but not previously re-verified live in this Phase 10 packet):**
`SweepExecutor.freezeConfiguration()` currently reverts with
`AdapterNotYetFrozen(0xBB86D6ef057F03Ca0bcaB9f87B61894977B0dBcb)` on real
mainnet right now — the executor-level freeze requires **both adapters' own
`freezeConfiguration()`** to have been called first (the RA-01 freeze-coupling
design). This means the freeze sequence is three transactions, not one,
which the earlier session-level summaries hadn't spelled out concretely.
Confirmed the adapter-level freeze only guards
`allowIntermediateAsset`/`disallowIntermediateAsset` (owner-only admin
functions) — it does **not** affect `swap()`, so freezing the adapters has no
effect on the smoke sweep's ability to execute. Also confirmed WMON is
already an allowed intermediate asset on `UniswapV3Adapter`
(`allowedIntermediateAssets(WMON) == true`), so no additional admin call is
needed for the multihop route to validate.

---

## 2. Liquidity sizing

Full candidate modeling (2/3/5/8/10 MON, with per-candidate DUST3 amount,
tick range, utilization, expected output, price impact, sustainable demo
swaps, and reserve) is in **`artifacts/phase-10/liquidity-sizing.md`**.

**Recommendation: 5 MON deposit, ~50,000 DUST3 desired (~49,262 DUST3
actually consumed by the mint).** This is not a default — it's chosen because
it sustains ~24 sequential full-claim (200 DUST3) demo sweeps before 5%
cumulative price drift, at negligible (0.208%) single-swap impact, while
retaining ≈87% of the deployer's MON balance after all Phase 10 gas.

---

## 3. Pool parameters

| Field                                      | Value                                                                             |
| ------------------------------------------ | --------------------------------------------------------------------------------- |
| token0                                     | DUST3 (`0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3`) — numerically less than WMON |
| token1                                     | WMON (`0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A`)                               |
| Fee tier                                   | 3000 (0.30%)                                                                      |
| Tick spacing                               | 60                                                                                |
| Initial price                              | 1 DUST3 = 0.0001 WMON (equivalently, **1 WMON = 10,000 DUST3**)                   |
| sqrtPriceX96                               | 792281625142643392428113920                                                       |
| Lower tick                                 | -98160 (= -1636 × 60, a valid multiple)                                           |
| Upper tick                                 | -86160 (= -1436 × 60, a valid multiple)                                           |
| DUST3 desired / WMON desired               | 50,000 ether / 5 ether                                                            |
| Actual mint consumption (measured on fork) | 49,262.435587280338882168 DUST3 / 5.0 WMON exactly                                |
| Resulting position liquidity               | 1,915.02 (human units); raw `1915019841751920881690`                              |
| Expected NFT position                      | New `INonfungiblePositionManager` token ID, recipient = deployer                  |

**Consumer-readable price explanation:** the pool is seeded so that **1 MON
buys 10,000 DUST3** (equivalently, 1 DUST3 is worth 0.0001 MON) — reflecting
that DUST3 is an intentionally near-worthless demo "dust" token. Through the
second leg (the real, existing WMON/USDC pool at ≈0.0215 USDC/WMON), one full
200-DUST3 demo claim is worth **≈$0.000427** — a genuinely tiny amount, which
is the correct, honest outcome for a token whose entire purpose is to
represent worthless wallet dust. This is not a market-making pool; it exists
solely to prove the sweep mechanism works end-to-end on real infrastructure.

---

## 4. Transaction packet

All calldata below was generated with `cast calldata` against the exact
proposed values, and independently reproduced by a real (local-fork-only)
execution of `packages/contracts/script/Phase10RouteSimulation.s.sol`
against `anvil --fork-url https://rpc.monad.xyz` — see
`artifacts/phase-10/smoke-plan.json` for the full rehearsal result. No step
below has been sent to real mainnet.

### A. Wrap MON → WMON

| Field                       | Value                                                                       |
| --------------------------- | --------------------------------------------------------------------------- |
| Sequence                    | 1                                                                           |
| Purpose                     | Obtain WMON for the new pool's liquidity                                    |
| Sender                      | `0xbde0076F05B5eA898F9ca51f1b595D84598DE586`                                |
| Target                      | `0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A` (WMON)                         |
| Function                    | `deposit()`                                                                 |
| Selector                    | `0xd0e30db0`                                                                |
| Calldata                    | `0xd0e30db0`                                                                |
| Native value                | 5000000000000000000 wei (5 MON)                                             |
| Approvals                   | none                                                                        |
| Expected/proposed gas limit | 44,942 measured / 60,000 proposed limit                                     |
| Estimated gas cost          | 44,942 × 102 gwei ≈ 0.00458 MON                                             |
| Expected state change       | Deployer WMON balance 0 → 5; deployer MON balance -5 (minus gas)            |
| Balances before/after       | WMON: 0 → 5.0; MON: 43.018882540 → ~38.014 (after value + gas)              |
| Rollback/failure behavior   | Reverts only if insufficient MON sent (not possible here); no partial state |
| Explorer URL template       | `https://monadscan.com/tx/{hash}`                                           |

### B. Create DUST3/WMON 0.3% pool

| Field                       | Value                                                                                                                                                                                                        |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sequence                    | 2                                                                                                                                                                                                            |
| Purpose                     | Create the pool (does not exist at any fee tier today)                                                                                                                                                       |
| Sender                      | deployer                                                                                                                                                                                                     |
| Target                      | `0x204FAca1764B154221e35c0d20aBb3c525710498` (Uniswap V3 Factory)                                                                                                                                            |
| Contract name               | `UniswapV3Factory`                                                                                                                                                                                           |
| Function                    | `createPool(address,address,uint24)`                                                                                                                                                                         |
| Selector                    | `0xa1671295`                                                                                                                                                                                                 |
| Decoded args                | `(0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3, 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A, 3000)`                                                                                                             |
| Raw calldata                | `0xa16712950000000000000000000000001b7eb110bdc1d0b7f85046ec812be77958e8b3c30000000000000000000000003bd359c1119da7da1d913d1c4d2b7c461115433a0000000000000000000000000000000000000000000000000000000000000bb8` |
| Native value                | 0                                                                                                                                                                                                            |
| Approvals                   | none                                                                                                                                                                                                         |
| Expected/proposed gas limit | 4,558,970 measured / 5,200,000 proposed limit (14% headroom — pool deployment is the single most gas-intensive step)                                                                                         |
| Estimated gas cost          | 4,558,970 × 102 gwei ≈ 0.4650 MON                                                                                                                                                                            |
| Expected state change       | New pool contract deployed at a CREATE2 address (must be read back after real broadcast — do not assume it equals the fork rehearsal's address)                                                              |
| Rollback/failure behavior   | Reverts if the pool already exists at this tier (confirmed it does not)                                                                                                                                      |
| Explorer URL template       | `https://monadscan.com/tx/{hash}`                                                                                                                                                                            |

### C. Initialize the pool

| Field                       | Value                                                                         |
| --------------------------- | ----------------------------------------------------------------------------- |
| Sequence                    | 3                                                                             |
| Purpose                     | Set the starting price                                                        |
| Sender                      | deployer                                                                      |
| Target                      | the pool address created in step B (read back, not assumed)                   |
| Function                    | `initialize(uint160)`                                                         |
| Selector                    | `0xf637731d`                                                                  |
| Decoded args                | `sqrtPriceX96 = 792281625142643392428113920`                                  |
| Raw calldata                | `0xf637731d0000000000000000000000000000000000000000028f5c28f5c28f6000000000`  |
| Native value                | 0                                                                             |
| Expected/proposed gas limit | 70,386 measured / 100,000 proposed limit                                      |
| Estimated gas cost          | 70,386 × 102 gwei ≈ 0.00718 MON                                               |
| Expected state change       | Pool `slot0.sqrtPriceX96` set; pool otherwise has zero liquidity until step F |
| Rollback/failure behavior   | Reverts if already initialized (not possible for a pool just created)         |
| Explorer URL template       | `https://monadscan.com/tx/{hash}`                                             |

### D. Approve DUST3 to NonfungiblePositionManager

| Field                       | Value                                                                                                                                        |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Sequence                    | 4                                                                                                                                            |
| Sender                      | deployer                                                                                                                                     |
| Target                      | `0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3` (DUST3)                                                                                         |
| Function                    | `approve(address,uint256)`                                                                                                                   |
| Selector                    | `0x095ea7b3`                                                                                                                                 |
| Decoded args                | `(spender=0x7197E214c0b767cFB76Fb734ab638E2c192F4E53, amount=50000000000000000000000)` (exactly 50,000 DUST3 — not unlimited)                |
| Raw calldata                | `0x095ea7b30000000000000000000000007197e214c0b767cfb76fb734ab638e2c192f4e53000000000000000000000000000000000000000000000a968163f0a57b400000` |
| Expected/proposed gas limit | 45,981 measured / 60,000 proposed                                                                                                            |
| Estimated gas cost          | ≈0.00469 MON                                                                                                                                 |
| Expected state change       | DUST3 allowance(deployer → NFPM) 0 → 50,000                                                                                                  |

### E. Approve WMON to NonfungiblePositionManager

| Field                       | Value                                                                                                                                        |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Sequence                    | 5                                                                                                                                            |
| Sender                      | deployer                                                                                                                                     |
| Target                      | `0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A` (WMON)                                                                                          |
| Function                    | `approve(address,uint256)`                                                                                                                   |
| Selector                    | `0x095ea7b3`                                                                                                                                 |
| Decoded args                | `(spender=0x7197E214c0b767cFB76Fb734ab638E2c192F4E53, amount=5000000000000000000)` (exactly 5 WMON)                                          |
| Raw calldata                | `0x095ea7b30000000000000000000000007197e214c0b767cfb76fb734ab638e2c192f4e530000000000000000000000000000000000000000000000004563918244f40000` |
| Expected/proposed gas limit | 46,123 measured / 60,000 proposed                                                                                                            |
| Estimated gas cost          | ≈0.00470 MON                                                                                                                                 |
| Expected state change       | WMON allowance(deployer → NFPM) 0 → 5                                                                                                        |

### F. Mint the liquidity position

| Field                       | Value                                                                                                                                                                                                                                                        |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sequence                    | 6                                                                                                                                                                                                                                                            |
| Sender                      | deployer                                                                                                                                                                                                                                                     |
| Target                      | `0x7197E214c0b767cFB76Fb734ab638E2c192F4E53` (NonfungiblePositionManager)                                                                                                                                                                                    |
| Function                    | `mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))`                                                                                                                                                                 |
| Selector                    | `0x88316456`                                                                                                                                                                                                                                                 |
| Decoded args                | `token0=DUST3, token1=WMON, fee=3000, tickLower=-98160, tickUpper=-86160, amount0Desired=50000 ether, amount1Desired=5 ether, amount0Min=49500 ether (99%), amount1Min=4.95 ether (99%), recipient=deployer, deadline=<short window, set at broadcast time>` |
| Native value                | 0                                                                                                                                                                                                                                                            |
| Expected/proposed gas limit | 582,511 measured / 750,000 proposed (29% headroom)                                                                                                                                                                                                           |
| Estimated gas cost          | 582,511 × 102 gwei ≈ 0.05942 MON                                                                                                                                                                                                                             |
| Expected state change       | Mints a new position NFT; consumes ≈49,262.44 DUST3 and exactly 5 WMON (measured); pool `liquidity()` becomes 1,915.02 (human units)                                                                                                                         |
| Balances before/after       | DUST3: 600,000 → ≈550,737.56; WMON: 5 → ≈0.0 (fully consumed)                                                                                                                                                                                                |
| Rollback/failure behavior   | Reverts entirely if `amount0Min`/`amount1Min` aren't met (sandwich/slippage protection); no partial mint                                                                                                                                                     |
| Explorer URL template       | `https://monadscan.com/tx/{hash}`                                                                                                                                                                                                                            |

### G. Approve exact smoke-test DUST3 amount to Permit2

| Field                       | Value                                                                                                                                                                                                                                           |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sequence                    | 7                                                                                                                                                                                                                                               |
| Purpose                     | Standing ERC20 allowance to Permit2 (Permit2's own signed-amount model bounds the actual pull; this approval is additionally capped at the exact smoke amount, not `type(uint256).max`, per this packet's "no unlimited approvals" requirement) |
| Sender                      | deployer                                                                                                                                                                                                                                        |
| Target                      | `0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3` (DUST3)                                                                                                                                                                                            |
| Function                    | `approve(address,uint256)`                                                                                                                                                                                                                      |
| Selector                    | `0x095ea7b3`                                                                                                                                                                                                                                    |
| Decoded args                | `(spender=0x000000000022D473030F116dDEE9F6B43aC78BA3 (Permit2), amount=200000000000000000000)` (exactly 200 DUST3)                                                                                                                              |
| Raw calldata                | `0x095ea7b3000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba300000000000000000000000000000000000000000000000ad78ebc5ac6200000`                                                                                                    |
| Expected/proposed gas limit | 45,909 measured / 60,000 proposed                                                                                                                                                                                                               |
| Estimated gas cost          | ≈0.00468 MON                                                                                                                                                                                                                                    |
| Expected state change       | DUST3 allowance(deployer → Permit2) 0 → 200                                                                                                                                                                                                     |

### H. Permit2 witness signature (produced off-chain, not a transaction)

Not a broadcast transaction — signed off-chain by the deployer's wallet
immediately before step I. Structure (typehash, witness binding) proven
byte-correct by `packages/contracts/test/Phase10RouteSmoke.fork.t.sol::test_dust3ToUsdcMultihopRouteSucceeds`.
See `artifacts/phase-10/smoke-plan.json` → `permit2` for exact fields
(permitted token/amount, witness type string). **A stale signature (past
deadline, or for a different plan) is never reused** — it is generated fresh
immediately before broadcast.

### I. Execute the smoke sweep

| Field                       | Value                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sequence                    | 8                                                                                                                                                                                                                                                                                                                                                                           |
| Sender                      | deployer                                                                                                                                                                                                                                                                                                                                                                    |
| Target                      | `0x7a844005998e896967A8b2BdA13c7826F387E9c3` (SweepExecutor)                                                                                                                                                                                                                                                                                                                |
| Function                    | `executeSweep((address,address,address,uint256,uint256,bytes32,(address,uint256,uint8,uint256,bytes,bool)[],(address,uint256,address)[],(address,uint256)[],(address,uint256)[]),bytes)`                                                                                                                                                                                    |
| Selector                    | `0x6bf2fe68`                                                                                                                                                                                                                                                                                                                                                                |
| Decoded plan                | `owner=deployer, recipient=deployer, outputToken=USDC, deadline=<short window>, nonce=0, displayManifestHash=<real RFC 8785 hash, not the rehearsal placeholder>, swaps=[{tokenIn=DUST3, amountIn=200 ether, adapterKind=UNISWAP_V3(1), minAmountOut=384, routeData=<DUST3\|3000\|WMON\|3000\|USDC packed path>, allowFailure=false}], transfers=[], discards=[], burns=[]` |
| Native value                | 0                                                                                                                                                                                                                                                                                                                                                                           |
| Approvals consumed          | Permit2 pulls exactly 200 DUST3 per the witnessed signature                                                                                                                                                                                                                                                                                                                 |
| Expected/proposed gas limit | 401,532 measured / 550,000 proposed (37% headroom)                                                                                                                                                                                                                                                                                                                          |
| Estimated gas cost          | 401,532 × 102 gwei ≈ 0.04096 MON                                                                                                                                                                                                                                                                                                                                            |
| Expected state change       | Deployer DUST3 -200; deployer USDC +427 (raw units, ≈$0.000427); executor retains 0 DUST3, 0 WMON, 0 USDC after the call (measured on the fork rehearsal)                                                                                                                                                                                                                   |
| Rollback/failure behavior   | Entire plan reverts on any single action failure (`allowFailure: false`); nonce is only consumed on success                                                                                                                                                                                                                                                                 |
| Explorer URL template       | `https://monadscan.com/tx/{hash}`                                                                                                                                                                                                                                                                                                                                           |

### J. Read and verify the finalized result

Read-only, not a transaction: re-query `USDC.balanceOf(deployer)`,
`DUST3.balanceOf(executor)`, `WMON.balanceOf(executor)`,
`USDC.balanceOf(executor)`, and `SweepExecutor.nonces(deployer)` after the
real transaction confirms, and compare against the expected values above
before treating the smoke test as verified.

### K. Freeze sequence (prepared, NOT sent)

Three transactions, in order, **none sent by this packet**:

| Step | Target           | Function                | Selector                           | Measured/estimated gas                  |
| ---- | ---------------- | ----------------------- | ---------------------------------- | --------------------------------------- |
| K1   | PancakeV2Adapter | `freezeConfiguration()` | `0x8d9bad95` (owner-only, no args) | 46,336 (measured on fork)               |
| K2   | UniswapV3Adapter | `freezeConfiguration()` | `0x8d9bad95`, different target     | 46,348 (measured on fork)               |
| K3   | SweepExecutor    | `freezeConfiguration()` | `0x8d9bad95`, different target     | 57,333 (estimated after K1+K2, on fork) |

K1 and K2 **must** precede K3 — confirmed live that K3 currently reverts with
`AdapterNotYetFrozen` because neither adapter has been frozen yet. This
three-transaction freeze sequence is fully prepared and gas-measured but is
explicitly **not sent** by this packet — see §7.

---

## 5. Smoke-sweep amount selection

Full comparison of ¼ claim / ½ claim / 1 full claim / the previously-tested
10,000-DUST3 amount is in `artifacts/phase-10/smoke-plan.json`. **Selected:
200 DUST3 (one full DemoDistributor claim)** — the smallest amount that is
also fully representative of a real demo user's action, with negligible
(0.208%) price impact at the recommended pool size.

---

## 6. Failure safety (verified without broadcasting)

All items required by this packet are verified either by the two new
fork tests added for this exact route, or by the general Phase 7 suite's
structural properties (which apply to any plan/witness, not just this
route). Full detail with exact test names in
`artifacts/phase-10/smoke-plan.json` → `failureSafetyChecks`. Summary:

| Property                                                   | Verified by                                                                                                                                                                                          |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Expired deadline reverts                                   | `Phase10RouteSmoke.fork.t.sol::test_expiredDeadlineReverts` (this route, real fork)                                                                                                                  |
| Excessive `minAmountOut` reverts                           | `Phase10RouteSmoke.fork.t.sol::test_excessiveMinAmountOutReverts` (this route, real fork)                                                                                                            |
| Wrong `AdapterKind` fails                                  | `SweepExecutorAdversarial.t.sol::test_signedAdapterKind_cannotBeSubstitutedAtExecution`                                                                                                              |
| Changed recipient/amount/route/token invalidates witness   | `Permit2Witness.t.sol::test_modifiedPlan_fails`                                                                                                                                                      |
| Replayed nonce fails                                       | `Permit2Witness.t.sol::test_reusedNonce_fails`                                                                                                                                                       |
| Executor retains no plan funds on success                  | measured directly on this route's fork rehearsal (0 DUST3, 0 WMON, 0 USDC left in executor)                                                                                                          |
| Reverted execution leaves no trace / doesn't consume nonce | `SweepExecutorAdversarial.t.sol::test_maliciousAdapter_revertsAfterPartialMutation_leavesNoTrace`; also directly re-verified by both new fork tests above (nonce unchanged after each reverted case) |

---

## 7. Freeze readiness

**Freeze is NOT proposed for broadcast in this packet.** Readiness checklist:

- [x] Native MON (`MON_SENTINEL`) output token registered
- [x] Canonical USDC output token registered
- [x] No other token is registered as an output token (checked DUST1-5 and WMON — all `false`)
- [x] Adapter addresses are immutable (constructor-fixed, per RA-01 architecture — unchanged since Phase 9)
- [ ] **Adapter-level prerequisite, re-confirmed live** (already covered by `SweepExecutor.t.sol::test_freezeConfiguration_revertsUnlessBothAdaptersFrozen`): both adapters' own `freezeConfiguration()` must be called before the executor's will succeed — neither has been called on real mainnet yet
- [ ] Smoke sweep has not yet been executed on real mainnet (it is what this packet prepares, not what it completes)
- [x] Freeze is irreversible by design (no `unfreeze` function exists in `SweepExecutor.sol`, `PancakeV2Adapter.sol`, or `UniswapV3Adapter.sol`)
- [x] Output-token mutation after freeze reverts in tests (`SweepExecutor.t.sol::test_freezeConfiguration_blocksFurtherOutputTokenChanges`, Phase 7)
- [x] Phase 9 adapter identity gate remains satisfied (adapter addresses, bytecode, and constructor arguments unchanged since Phase 9 — no redeploy has occurred)

**No future demo requirement needing a third output asset has been
identified** — the product scope (PRD) only ever names MON and USDC as sweep
outputs.

**Freeze will only be proposed after the smoke sweep above is broadcast,
confirmed, and independently re-verified against this packet's expected
values.**

---

## 8. Deployment record plan

Exact fields to be appended to `deployments/mainnet.json` once real values
exist are specified in `artifacts/phase-10/proposed-deployment-diff.json`.
**`deployments/mainnet.json` itself is not modified by this packet.**

---

## Summary (see also the top-level chat response for the 12-point report)

This packet is complete and internally consistent: every quantitative claim
either comes from a live mainnet read taken this session, or from a real
(local-fork-only) execution of the exact proposed transaction sequence at
the exact proposed parameters. Nothing was broadcast to real mainnet in the
preparation of this packet.
