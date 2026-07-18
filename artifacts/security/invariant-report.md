# Invariant Report — Phase 7 Task 7.8

## Configuration (`foundry.toml`)

```toml
[invariant]
runs = 128
depth = 64
fail_on_revert = true

[profile.ci.invariant]
runs = 512
depth = 128
```

`fail_on_revert = true` means any unhandled handler-function revert fails the whole
campaign - the handlers below use `try/catch` deliberately where a revert is an
_expected_ outcome (e.g. an unauthorized admin call), so the campaign only fails on a
genuinely unexpected revert or a violated invariant.

## `SweepExecutorInvariantsTest` (`test/SweepExecutorInvariants.t.sol`)

| Invariant                                                                                                  | Runs | Calls | Reverts | Result |
| ---------------------------------------------------------------------------------------------------------- | ---- | ----- | ------- | ------ |
| `invariant_executorRetainsNoTouchedTokenBalance` — zero active-plan balance retained for any touched token | 128  | 8,192 | 0       | PASS   |
| `invariant_nonceMatchesCallCount` — nonce counter exactly equals successful-sweep count                    | 128  | 8,192 | 0       | PASS   |
| `invariant_ownerNeverChanges` (this session) — ownership never silently changes                            | 128  | 8,192 | 0       | PASS   |

**Handler function breakdown** (same 8,192-call campaign, both handler functions
targeted together each run):

| Handler function                                                                                                                                           | Calls | Reverts | Discards |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | ------- | -------- |
| `runSweep` (drives valid signed sweeps, pseudo-random action shape/amount)                                                                                 | 4,101 | 0       | 0        |
| `attemptUnauthorizedAdmin` (this session — drives every admin-only function from a pseudo-random non-owner address, asserting each attempt reverts inline) | 4,092 | 0       | 1        |

The single discard on `attemptUnauthorizedAdmin` is the `vm.assume(caller !=
EXECUTOR.owner())` guard rejecting the vanishingly unlikely case where the fuzzed
caller address happens to equal the owner address itself - not a defect.

**What `attemptUnauthorizedAdmin` actually proves:** it does not merely rely on the
call reverting - each of its four branches (`registerOutputToken`,
`removeOutputToken`, `freezeConfiguration`, `recoverStrayTokens`) wraps the call in
its own `try { revert("unauthorized X succeeded"); } catch {}`, so if any
unauthorized admin call ever _succeeded_, the handler itself would revert with that
message, failing the entire invariant run (since `fail_on_revert = true`). Zero such
failures occurred across 4,092 unauthorized-admin attempts.

## `DemoDistributorInvariantsTest` (`test/DemoDistributorInvariants.t.sol`, new this session)

| Invariant                                                                                                                                                                                          | Runs | Calls | Reverts | Result |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | ----- | ------- | ------ |
| `invariant_claimedAddressesHoldExactlyOneBundleWorth` — total tokens distributed always exactly equals `successfulClaims × CLAIM_AMOUNT`, never more (double-claim) or less (partial distribution) | 128  | 8,192 | 0       | PASS   |

**A genuine finding surfaced while writing this invariant, and its resolution:** the
first version of this handler allowed the fuzzed claimant address to equal
`DemoDistributor`'s own deployed address. When that specific self-referential
address was fuzzed, `msg.sender == address(DISTRIBUTOR)` inside `claimDemoBundle`
caused each token's `transfer(self, amount)` to net to a zero balance change (a
self-transfer), while `claimed[distributor] = true` was still recorded - making the
distributor "successfully claim" while distributing nothing to itself, which broke
the invariant's aggregate accounting check. This is **not a reachable production
vulnerability** - nothing can make an external call arrive with `msg.sender` equal to
an existing contract's own address without that contract's private key, which
contracts don't have; it is purely an artifact of the test harness's `vm.prank`
cheatcode allowing an otherwise-impossible caller identity. The handler was fixed to
exclude `address(DISTRIBUTOR)` from the fuzzed claimant space (`vm.assume(claimant !=
address(DISTRIBUTOR))`), documented inline at the point of the fix. Recorded here in
full rather than silently corrected, per the instruction to report real findings even
when they turn out to be test-harness artifacts rather than production bugs.

## Reproducing this report

```bash
cd packages/contracts
forge test --match-contract "SweepExecutorInvariantsTest|DemoDistributorInvariantsTest" -vv
```

For the higher `profile.ci` run counts (512 runs × 128 depth):

```bash
FOUNDRY_PROFILE=ci forge test --match-contract "SweepExecutorInvariantsTest|DemoDistributorInvariantsTest" -vv
```
