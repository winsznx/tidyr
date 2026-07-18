# Manual Line-by-Line Review — Phase 7 Task 7.13

Scope: `packages/contracts/src/SweepExecutor.sol`, `src/adapters/PancakeV2Adapter.sol`,
`src/adapters/UniswapV3Adapter.sol`, `src/libraries/SweepPlanLib.sol`,
`src/libraries/TidyrWitness.sol`, `src/libraries/UniswapV3Path.sol`,
`src/tokens/DemoDistributor.sol`. Reviewed against the checklist in Task 7.13.

## Checks-Effects-Interactions (CEI) and reentrancy

- **`SweepExecutor.executeSweep`:** validates → hashes → snapshots baselines → pulls
  funds (external call to Permit2) → executes actions (external calls to adapters/
  tokens) → settles output (external call) → returns remainders (external calls) →
  emits event. This is not textbook CEI (state writes like `nonces[plan.owner] =
plan.nonce + 1` happen before the pull, which is correct - nonce must be consumed
  before any external call, not after, to prevent reentrant nonce reuse) but the
  function is `nonReentrant`, which is the actual, stronger guarantee CEI is normally
  used to approximate. Verified directly: `test_maliciousReentrantAdapter_reverts`,
  `test_reentrantToken_transferHook_blockedByReentrancyGuard`, and all three
  `MockMaliciousAdapter` tests exercise reentrancy attempts against this exact
  function and its callees.
- **`DemoDistributor.claimDemoBundle`:** genuinely textbook CEI —
  `claimed[msg.sender] = true` is set before the loop of external `safeTransfer`
  calls. Correct as written; no reentrancy path exists even without a
  `ReentrancyGuard`, since the state that gates re-entry (`claimed`) is already
  written before any external call.
- **`recoverStrayTokens`:** shares `executeSweep`'s `nonReentrant` lock, so it cannot
  run mid-sweep (PRD §19.10) - verified structurally and by the reentrant-adapter
  tests, which attempt exactly this call from inside a swap.

## State reads after external calls

- **`_executeSwap`:** reads `IERC20(settlementToken).balanceOf(address(this))` both
  before and after `adapter.swap(...)`. This is the intended pattern (balance-delta
  accounting, not a bug) - Slither's `reentrancy-balance` finding on this exact
  pattern is triaged in `slither-triage.md` finding 2. The post-call read is safe
  specifically because `executeSweep` (the only path that reaches this function) is
  `nonReentrant`.
- **`_settleOutput`:** reads balances before and after `WMON.withdraw`/the native
  transfer; same reasoning applies, and `nonReentrant` covers this call site too
  since it's within the same `executeSweep` invocation.

## Nonce timing

`nonces[plan.owner] = plan.nonce + 1` executes immediately after the nonce-match
check, before `validatePlanShape`, before hashing, before the Permit2 pull, and
before any action executes. This means a plan that fails _after_ this point (e.g.
`UnexpectedPulledAmount`, a required swap reverting) still reverts the _entire_
transaction (Solidity's atomic revert semantics undo the nonce write too) - so the
nonce is never actually "consumed" unless the whole sweep succeeds. Verified by
`test_skipAheadNonce_reverts` (this session) and the pre-existing
`test_reusedNonce_reverts`.

## Permit2 array alignment

`_pullViaPermit2` builds `permitted[]` and `details[]` in the same loop, indexed
identically from `tokens[]`/`amounts[]` (both produced by the single call to
`SweepPlanLib.aggregateTokenAmounts`), so there is no way for the two arrays to
desynchronize - they are constructed from the same source arrays in the same loop
iteration, not independently. Verified by `test_aggregateTokenAmounts_dedupesAndSums`
and the full Permit2 integration suite.

## Hash ambiguity

`SweepPlanLib.hashPlan` hashes each action array element-wise (hash each action, then
hash the array of hashes) specifically to avoid the ABI-encoding ambiguity that a
single `abi.encode(plan)` call could introduce when nested dynamic `bytes` fields
(`SwapAction.routeData`) are present - documented at the point of definition and
proven by the full golden-vector + mutation-test suite in `SweepPlanLib.t.sol` (18
tests) and `executionPlanHash.test.ts` (20 tests), all still passing after this
session's Slither-triage renames (`SweepPlanLib.hashPlan` itself was untouched this
session; only two identifier renames in `SweepExecutor.sol` occurred, both proven by
`forge test` to be behavior-preserving).

## Balance-delta correctness, duplicate-token handling, output/input overlap

- `test_outputTokenAlsoUsedAsTransferInput_noDoubleCount` (this session) proves
  `_settleOutput`-before-`_returnRemainders` ordering correctly avoids double-counting
  when the settlement token coincides with a token also used in a transfer/discard/
  burn action (swap-input overlap is separately, structurally disallowed via
  `AmbiguousSwapToken`).
- `test_preExistingOutputTokenBalance_isNotSweptIntoPlan` (this session) proves a
  pre-existing stray balance of the _settlement_ token specifically (not just an
  unrelated token) is correctly excluded from what gets sent to the recipient.
- `aggregateTokenAmounts`'s O(n²) dedupe is documented and bounded by `MAX_ACTIONS`;
  its worst-case gas cost is measured directly in `gas-report.md`.

## Route validation / adapter caller restriction

- Both adapters validate their own `routeData`-derived path against
  `allowedIntermediateAssets` before ever reaching a DEX call - path tokens cannot
  redirect the swap to an unreviewed venue, since the adapter's own `FACTORY`/`ROUTER`
  immutable is the only DEX-facing target, never derived from `routeData`.
- Neither adapter restricts _who_ can call `swap()` (no `onlyOwner`/allowlist on the
  function itself) - this is intentional: adapters never hold funds between calls
  (any caller can invoke `swap()`, but it can only move tokens the caller has already
  approved _to that adapter_, and settles output back to `msg.sender`, i.e. whoever
  called it). An adapter being called directly by an arbitrary EOA rather than
  `SweepExecutor` has no fund-safety implication beyond that caller's own approved
  balance - there is no privileged state an outside caller could corrupt for other
  users, since `allowedIntermediateAssets` is the only persistent adapter state and
  it's `onlyOwner`-gated separately.

## Native MON behavior

`_settleOutput`'s native-MON branch: unwraps exactly the WMON delta produced this
sweep (not any pre-existing WMON balance, since `settlementBaseline` is captured
before the pull), then sends exactly the resulting native-MON delta
(`address(this).balance - nativeBaseline`) to `plan.recipient`, reverting the entire
plan (`NativeTransferFailed`) if the recipient cannot accept it - proven atomic by
`test_moneyRejectingRecipient_revertsWholePlan` (this session) and correctly
zero-cost when no swap produced any MON by
`test_nativeMonOutput_withNoSwapProducingMon_settlesToZero` (this session, closing a
coverage gap identified in Task 7.12).

## Owner powers

- `SweepExecutor`: `registerOutputToken`/`removeOutputToken` (pre-freeze only),
  `freezeConfiguration` (irreversible, now coupled to both fixed adapters' own freeze
  state), `recoverStrayTokens` (always available, `nonReentrant`). No
  fund-redirection power exists for the owner - they cannot change `plan.recipient`,
  cannot access in-flight plan funds (shared `nonReentrant` lock), and cannot mutate
  the two fixed adapter addresses (immutable).
- Both adapters: `allowIntermediateAsset`/`disallowIntermediateAsset` (pre-freeze),
  `freezeConfiguration` (irreversible). Same absence of fund-redirection power - the
  owner controls only which intermediate hop tokens are permitted, not where output
  settles (always `msg.sender`, i.e. the calling `SweepExecutor`).
- **Verified finding (informational, not a vulnerability):** in `SweepExecutor`,
  `PancakeV2Adapter`, and `UniswapV3Adapter`, each constructor calls `Ownable
(initialOwner_)` _before_ the constructor's own body runs its `initialOwner_ ==
address(0)` check. Since OZ v5's `Ownable` constructor itself reverts
  `OwnableInvalidOwner` for a zero owner, that specific clause of each contract's own
  `ZeroAddress` check is unreachable dead code for the owner parameter specifically -
  the zero address is still correctly rejected either way, just via a different,
  already-correct error. Discovered and confirmed via
  `test_pancakeV2Adapter_constructor_rejectsZeroOwner` /
  `test_uniswapV3Adapter_constructor_rejectsZeroOwner` in `AdapterCompleteness.t.sol`
  (this session), both updated to assert the actual observed error. No fix applied -
  removing the redundant clause is optional cleanup with zero security benefit, since
  the address is rejected correctly regardless of which check fires.

## Freeze completeness

`SweepExecutor.freezeConfiguration()` now requires both `PANCAKE_V2_ADAPTER` and
`UNISWAP_V3_ADAPTER` to have already frozen themselves (this session's follow-up
hardening to the RA-01 remediation) - closing the gap where an executor-level freeze
previously said nothing about each adapter's own mutable intermediate-asset
allowlist. Proven by `test_freezeConfiguration_revertsUnlessBothAdaptersFrozen` and
`test_swapsUnaffectedByFreezeState`.

## Recovery

`recoverStrayTokens` is `onlyOwner`, shares the `nonReentrant` lock with
`executeSweep`, rejects a zero-address `to` (gap closed this session -
`test_recoverStrayTokens_rejectsZeroAddressRecipient`), and remains available after
freezing (unrelated to the execution security boundary, by design).

## Event correctness

Every state-changing function emits an event (`OutputTokenAllowed`/`Disallowed`,
`ConfigurationFrozen`, `StrayTokensRecovered`, `ActionExecuted`/`ActionFailed`,
`SweepCompleted`, and both adapters' `IntermediateAssetAllowed`/`Disallowed`/
`ConfigurationFrozen`). No event was found to fire on a no-op path or fail to fire on
a genuine state change, from direct reading of every function body in scope.

## Denial-of-service / accidental retention

Covered in depth in `gas-report.md` (Task 7.11) - all loops bounded by
`MAX_ACTIONS = 50`, worst-case measured directly (3.6M gas for 50 distinct-token
transfers), `routeData` cannot expand into unbounded work. Accidental retention:
`_returnRemainders` sweeps every token above its pre-pull baseline back to the plan
owner at the end of every successful `executeSweep` call, so unconsumed input (e.g.
from an `allowFailure`-tolerated swap failure) is never accidentally retained by the
contract - proven by the existing `test_allowFailure_adapterReverts_
planContinuesAndReturnsInput` and this session's
`test_maliciousAdapter_revertsAfterPartialMutation_leavesNoTrace`.

## Summary

No new P0 or P1 finding resulted from this manual review beyond what was already
identified and fixed via Slither triage (two zero-risk renames) and coverage-closure
(new zero-address/edge-case tests). One informational observation (unreachable
zero-owner clause in three constructors) is recorded above with no fix applied, since
fixing it has zero security benefit and the current behavior is already correct.
