# TIDYR Threat Model — Phase 7 Task 7.1

Scope: `SweepExecutor`, `PancakeV2Adapter`, `UniswapV3Adapter`, `SweepPlanLib`,
`TidyrWitness`, Permit2 integration, `DemoDistributor`. Each threat below records the
asset at risk, entry point, exploit prerequisites, the actual defense, the test that
proves the defense, and residual risk honestly stated (not "none" where that isn't
true).

## 1. Malicious caller (arbitrary EOA/contract calling `executeSweep` directly)

- **Asset:** any funds a caller could attempt to move on someone else's behalf.
- **Entry point:** `executeSweep(plan, signature)` — callable by anyone.
- **Prerequisites:** none — this is the default-open entry point.
- **Defense:** `plan.owner != msg.sender` reverts `NotPlanOwner`; the Permit2
  signature must independently verify against `plan.owner`'s key regardless of who
  calls. A caller cannot execute someone else's plan even if they somehow obtained
  the signed calldata, since `msg.sender` must equal `plan.owner`.
- **Test evidence:** `test_notPlanOwner_reverts`.
- **Residual risk:** none identified.

## 2. Captured Permit2 signature (signature intercepted/leaked before use)

- **Asset:** the exact tokens/amounts the captured signature authorizes.
- **Entry point:** anyone who obtains a valid `(plan, signature)` pair.
- **Prerequisites:** the plan owner's signature must leak (e.g. a compromised
  frontend, a malicious RPC proxy, a leaked mempool-adjacent relay).
- **Defense:** the signature only authorizes _exactly_ the plan it was signed over -
  binding is total (owner, recipient, outputToken, deadline, nonce, every
  action field including `adapterKind`/`routeData`/`minAmountOut`, chainId, executor
  address). A leaked signature cannot be replayed for a different plan, a different
  chain, a different executor deployment, or after its nonce is consumed. It _can_
  still be submitted by anyone before the legitimate owner submits it themselves
  (nothing requires `msg.sender` beyond `plan.owner` - but recall `plan.owner ==
msg.sender` is required, so only the owner's own address can be `msg.sender`; an
  attacker holding a leaked signature still cannot submit it as themselves, only as
  the victim, which produces the same intended-by-signer outcome, not an attacker
  benefit). The one genuine residual case: within the signed deadline, the
  transaction can be front-run/resubmitted by anyone acting _as a relayer_ on the
  owner's behalf via the owner's own transaction (this is not an attack - it just
  means whoever submits it first "wins" the gas race, but the outcome is identical
  either way since the plan's terms are fixed).
- **Test evidence:** `test_modifiedPlan_fails`, `test_signature_
doesNotSurviveChainIdChange`, `test_signature_doesNotSurviveCrossExecutorReplay`,
  `test_planASignature_cannotAuthorizePlanB_differentRecipient`, `test_
planASignature_cannotAuthorizePlanB_differentMinAmountOut`, `test_
signedAdapterKind_cannotBeSubstitutedAtExecution`, `test_reusedNonce_reverts`
  (Permit2Witness.t.sol and SweepExecutorCompleteness.t.sol/SweepExecutorAdversarial.t.sol).
- **Residual risk:** a leaked signature can still be _submitted_ by any relayer
  before the deadline expires - this is inherent to any signature-based
  meta-transaction scheme and not specific to TIDYR; the outcome is unchanged
  regardless of who submits it.

## 3. Malicious frontend (compromised or fake TIDYR UI)

- **Asset:** whatever the user is tricked into signing.
- **Entry point:** the signing prompt itself (outside this repository's contract
  scope, but the contract-side mitigation matters).
- **Prerequisites:** user must sign a plan/message they didn't intend.
- **Defense:** `executionPlanHash` (what gets signed via the Permit2 witness) is
  distinct from `displayManifestHash` (PRD §19.3) specifically so a wallet's
  signing UI can, in a future phase, decode and display the actual on-chain effect
  independent of what a compromised frontend claims it is - this is exactly why two
  hashes exist rather than one. The three-layer transaction-review security boundary
  (manifest / calldata decode-and-compare / simulation) that would fully close this
  gap is explicitly Phase 11 work, not yet built (`docs/security-addendum-review.md`).
- **Test evidence:** `test_executionHashDiffersFromDisplayManifestHash` proves the
  two hashes are structurally independent, which is the precondition for that future
  defense to work at all.
- **Residual risk, honestly stated:** **a malicious frontend today could still show a
  user one manifest while having them sign a plan with different terms**, since the
  wallet-level calldata-decode-and-compare UI doesn't exist yet. This is the single
  most significant residual risk in the current system and is explicitly out of
  scope for V1/Phase 7 (contract-side verification) — tracked as mandatory Phase 11
  work, not silently accepted.

## 4. Malicious token (as swap input, transfer token, or output token)

- **Asset:** the executor's own accounting integrity.
- **Entry point:** any ERC-20 address a plan names.
- **Prerequisites:** the plan owner or an integrator must choose to interact with a
  malicious/non-standard token (TIDYR itself doesn't allowlist arbitrary input
  tokens - only `outputToken` is allowlisted via `allowedOutputTokens`).
- **Defense:** balance-delta accounting throughout (never trusting a token's return
  value or a swap's reported output), `SafeERC20` for false-return/no-return
  tolerance, exact-amount `UnexpectedPulledAmount` checks that reject fee-on-transfer
  tokens rather than silently under-crediting, `nonReentrant` blocking reentrant
  token hooks.
- **Test evidence:** `test_falseReturnToken_asOutputToken_reverts`, `test_
noReturnToken_asOutputToken_succeeds`, `test_feeOnTransferToken_asSwapInput_
reverts`, `test_reentrantToken_transferHook_blockedByReentrancyGuard` (all in
  `SweepExecutorAdversarial.t.sol`).
- **Residual risk:** a rebasing token (balance changes without a transfer) used as
  swap _input_ could, in principle, cause `UnexpectedPulledAmount` to fire
  spuriously (safely rejecting the plan, not losing funds) if its balance rebases
  between the baseline snapshot and the pull within the same transaction - this is
  vanishingly unlikely (rebases are typically time-based, not per-transaction) and,
  even if triggered, fails safe (reverts, doesn't lose funds). Classified: safely
  rejected in the worst case, not silently broken.

## 5. Malicious adapter implementation

- **Asset:** funds mid-swap (the input token already pulled and approved to the
  adapter).
- **Entry point:** would require a malicious contract to occupy one of the two fixed
  `PANCAKE_V2_ADAPTER`/`UNISWAP_V3_ADAPTER` immutable slots - which per RA-01's
  remediation is only possible at `SweepExecutor` construction, never afterward.
- **Prerequisites:** a compromised or negligent deployment process wiring a
  malicious contract into one of these two slots (see threat 6 below - this is a
  deployment-integrity threat, not a runtime one).
- **Defense:** balance-delta accounting (the executor never trusts the adapter's
  return value), `forceApprove` grants only the exact `amountIn` (not unlimited), so
  even a fully malicious adapter cannot pull more than the single swap's own
  authorized amount, and cannot cause the executor to credit an output that didn't
  actually arrive.
- **Test evidence:** the three `MockMaliciousAdapter` tests (excess pull,
  send-elsewhere, revert-after-partial-mutation) in `SweepExecutorAdversarial.t.sol`.
- **Residual risk:** a malicious adapter can always cause its _own_ swap action to
  fail or under-deliver (fully contained to that one action, tolerated via
  `allowFailure` or fatal to the whole plan if required) - it cannot affect any
  _other_ token's baseline/remainder accounting, since those are computed
  independently per-token before any adapter call runs.

## 6. Compromised deployer before deployment completion

- **Asset:** the entire system's adapter-immutability guarantee.
- **Entry point:** the Phase 9 deployment script/process.
- **Prerequisites:** the deployer's key or deployment pipeline is compromised
  _during_ deployment (before `SweepExecutor`'s constructor call, or between
  deploying the adapters and deploying the executor).
- **Defense:** this is the one threat class no Solidity-level constructor check can
  fully close (see `SweepExecutor.sol`'s own contract-level doc comment and
  `docs/security-addendum-review.md`'s "Follow-up hardening" section). Constructor
  validation (`AdapterHasNoCode`, `DuplicateAdapterAddress`, `AdapterIsMulticall3`)
  narrows _which_ addresses can be wired in, but cannot prove the bytecode at those
  addresses is genuinely the audited source.
- **Test evidence:** N/A at the contract level; this is why
  `docs/requirements-traceability.md`'s Phase 9 gate row (strengthened this session,
  Task 7.14) mandates independent bytecode/constructor-argument/dependency
  verification as an explicit, non-optional deployment-script gate.
- **Residual risk, honestly stated:** **this cannot be fully closed by contract code
  alone.** It is mitigated by process (the strengthened Phase 9 gate, requiring
  independent verification and abort-on-mismatch) but ultimately depends on
  deployment-process integrity, the same trust boundary every immutable-constructor
  system has.

## 7. Incorrect (not malicious, just wrong) adapter wired into executor constructor

- **Asset:** correctness of routing (not fund safety, if the wrong-but-legitimate
  adapter is still a real, well-behaved `IAdapter` implementation).
- **Entry point:** deploy-script error (e.g. swapping the two adapter addresses, or
  deploying with a stale/wrong-network adapter address).
- **Defense:** `AdapterHasNoCode`/`DuplicateAdapterAddress`/`AdapterIsMulticall3`
  constructor checks catch the cheap, mechanical mistakes (typo'd zero address,
  duplicate, well-known-bad address). The strengthened Phase 9 gate (Task 7.14) is
  what catches "right shape, wrong network/version" mistakes via bytecode/dependency
  comparison.
- **Test evidence:** `test_constructor_rejectsAdapterWithNoCode`, `test_constructor_
rejectsDuplicateAdapterPair`, `test_constructor_rejectsMulticall3InEitherSlot`.
- **Residual risk:** an adapter that is a legitimate, well-behaved `IAdapter`
  implementation but simply the _wrong_ one (e.g. pointed at a different, unintended
  factory) would not be caught by any contract-level check - only by the Phase 9
  gate's dependency-address verification.

## 8. Malicious quote or route provider

- **Asset:** swap output value (not fund custody).
- **Entry point:** `SwapAction.routeData` — supplied by whatever off-chain
  quote/routing service produces the plan (not yet built; `packages/routing` is a
  future phase).
- **Prerequisites:** a compromised or malicious routing service returns a
  bad/manipulated route.
- **Defense:** `minAmountOut` is part of the signed plan (the user/their wallet is
  the one committing to this value, not the routing service unilaterally), and
  balance-delta accounting means the executor never trusts anything the route
  claims - either the swap delivers at least `minAmountOut` (measured, not
  reported) or it reverts.
- **Test evidence:** `test_adapterUnderDelivers_revertsInvariantViolation_
regardlessOfAllowFailure`.
- **Residual risk:** a malicious routing service could still construct a
  _technically-valid-but-bad-value_ route (e.g. an unnecessarily lossy path through
  legitimate, allowed intermediate assets) that a naive user signs without noticing -
  this is a UX/review-layer concern (Phase 11's transaction-review boundary), not a
  contract-level fund-safety issue, since `minAmountOut` still bounds the floor.

## 9. Forced token or MON balance (unsolicited transfer to the executor)

- **Asset:** the plan's own fund-isolation guarantee.
- **Entry point:** anyone can `token.transfer(executorAddress, amount)` or
  self-destruct-send native MON to the executor at any time, unsolicited.
- **Defense:** baseline-before/delta-after accounting for every token and for native
  MON means a forced balance is simply never attributed to any plan - it sits in the
  contract, recoverable only by the owner via `recoverStrayTokens`.
- **Test evidence:** `test_preExistingExecutorBalance_isNotSweptIntoPlan`, `test_
preExistingOutputTokenBalance_isNotSweptIntoPlan`, `testFuzz_
preExistingBalance_neverAttributedToPlan` (256/10,000 runs).
- **Residual risk:** none identified for accounting correctness; the forced balance
  itself is real and sits in the contract until the owner recovers it - not a loss,
  just dormant until `recoverStrayTokens` is called.

## 10. Reentrancy

- **Asset:** any state consistency `nonReentrant` protects.
- **Entry point:** a malicious adapter or token attempting to re-enter
  `executeSweep`/`recoverStrayTokens` mid-execution.
- **Defense:** `ReentrancyGuard`, shared across both functions.
- **Test evidence:** `test_maliciousReentrantAdapter_reverts`, `test_
reentrantToken_transferHook_blockedByReentrancyGuard`.
- **Residual risk:** none identified.

## 11. MEV and stale quotes

- **Asset:** swap output value.
- **Entry point:** the public mempool, between signing and inclusion.
- **Defense:** `minAmountOut` (user-committed floor, enforced via balance delta) and
  `deadline` (both plan-level and per-swap) bound the exposure window and the
  acceptable-outcome floor. This is the same mitigation every AMM router uses; TIDYR
  does not (and V1 is not scoped to) provide MEV-protection beyond this baseline
  (no private mempool integration, no commit-reveal).
- **Test evidence:** `test_expiredPlan_reverts`,
  `test_adapterUnderDelivers_revertsInvariantViolation_regardlessOfAllowFailure`.
- **Residual risk, honestly stated:** sandwich attacks against a public-mempool swap
  are possible up to the `minAmountOut` floor the user themselves set - this is
  standard AMM-swap MEV exposure, not a TIDYR-specific defect, and not something V1
  claims to solve.

## 12. Recipient rejecting MON

- **Asset:** the swept output itself.
- **Entry point:** `plan.recipient` being a contract with no `receive`/payable
  fallback.
- **Defense:** the entire `executeSweep` transaction reverts atomically
  (`NativeTransferFailed`) - no partial execution, no stranded funds mid-transaction.
- **Test evidence:** `test_moneyRejectingRecipient_revertsWholePlan`.
- **Residual risk:** none for fund safety (atomic revert); the plan simply cannot
  complete for that recipient until they choose a MON-accepting address or an ERC20
  output instead - a UX limitation, not a security one.

## 13. Malformed ERC-20 (false-return, no-return)

Covered under threat 4 above (`test_falseReturnToken_asOutputToken_reverts`,
`test_noReturnToken_asOutputToken_succeeds`).

## 14. Fee-on-transfer token

Covered under threat 4 above (`test_feeOnTransferToken_asSwapInput_reverts`).

## 15. Rebasing token

Covered under threat 4 above (residual risk noted there).

## 16. Denial-of-service via oversized actions or route data

- **Asset:** transaction includability / gas cost.
- **Entry point:** a plan with the maximum number of actions and/or maximally
  distinct tokens; `routeData` length.
- **Defense:** `MAX_ACTIONS = 50` bounds every loop; the worst-case measured cost
  (3.6M gas for 50 distinct-token transfers) is well within normal single-transaction
  gas limits. `routeData` cannot expand into unbounded work (bounded packed/array
  encoding, not executable data).
- **Test evidence:** `gas-report.md` (Task 7.11) — `test_gas_
maxActionsPlan_50DistinctTokenTransfers`, `test_gas_maxActionsPlan_50Transfers`,
  `test_gas_mixedActionPlan_10OfEachType`.
- **Residual risk:** a plan is signed by its own owner, who pays for their own gas -
  there is no attacker who benefits from constructing a maximally expensive plan
  against a victim, since the victim would have to sign it themselves. Not a
  cross-user DoS vector.

## Summary of residual risks not eliminated (honestly carried forward)

1. **No wallet-level transaction-review boundary yet** (threat 3) - the single
   largest residual gap, explicitly Phase 11 work.
2. **Deployment-integrity trust boundary** (threat 6) - mitigated by the
   strengthened Phase 9 gate, not eliminable by contract code alone.
3. **Standard AMM MEV exposure up to `minAmountOut`** (threat 11) - inherent to
   public-mempool swaps generally, not a TIDYR-specific defect.
4. **Leaked-signature relay-ordering** (threat 2) - inherent to signature-based
   meta-transactions generally; outcome is unchanged regardless of who submits it.

None of these four are P0/P1-severity contract bugs - they are either explicitly
deferred, process-level, or inherent to the class of system being built, and are
recorded here rather than silently assumed away.
