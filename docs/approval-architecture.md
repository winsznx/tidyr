# TIDYR Approval Architecture

Status: Phase 2–4 (contracts) implemented and verified; Phase 11/12 (TS-side discovery
and approval-transaction builders) not yet built — see `docs/implementation-plan.md`
Phase 11 for the tracked requirement this doc implies for that phase.

## Multicall3 is read-only infrastructure, never a spender

Multicall3 (`0xcA11bde05977b3631167028862bE2a173976CA11`, verified on Monad mainnet —
see `docs/research/external-addresses.md`) accepts an arbitrary `target` and arbitrary
`callData` in `aggregate3`. If a user ever approved Multicall3 as an ERC-20 spender,
anyone could instruct Multicall3 to call
`token.transferFrom(victim, attacker, allowance)` — the token sees
`msg.sender == Multicall3` and permits the transfer. This is a real, general class of
vulnerability; it does not mean Multicall3 itself is compromised.

TIDYR's rules, current and binding for all future phases:

1. Multicall3 may only ever be called through read-only `eth_call` (`balanceOf`,
   `allowance`, `decimals`, `symbol`, `name`) — planned for Phase 12's asset-discovery
   pipeline. Nothing in the current codebase calls it at all yet.
2. TIDYR must never generate `token.approve(MULTICALL3_ADDRESS, amount)`.
3. Multicall3 must never be registered as an adapter, router, or spender — every one of
   these roles grants _pull_ authority over funds it doesn't own. `plan.recipient` is
   deliberately **not** restricted from being Multicall3: it is the user's own chosen
   destination for their own swept output, the same as any other address they could pick,
   and carries no pull authority. Restricting it would be security theater with no
   corresponding threat (Codex addendum audit finding CA-03 — an earlier draft of this
   document incorrectly included "recipient" in this list; corrected here, see
   `docs/requirements-traceability.md` conflict C-8).
4. Contract-level proof: **superseded by the RA-01 remediation.** `SweepExecutor` no
   longer has a `registerAdapter` function or any adapter registry at all —
   `SwapAction.adapterKind` is a closed `AdapterKind` enum (`PANCAKE_V2`/`UNISWAP_V3`)
   resolving to one of exactly two immutable addresses fixed at construction, so there
   is no address field, registration call, or allowlist for Multicall3 (or anything
   else) to reach in the first place. An earlier remediation pass added an explicit
   `AdapterIsMulticall3` rejection in `registerAdapter`, proved by
   `test_multicall3_rejectedAsUnregisteredAdapter` and
   `test_registerAdapter_rejectsMulticall3Explicitly` — an independent re-audit found
   this insufficient (finding RA-01: registration still trusted arbitrary contracts'
   self-reported freeze state) and it was replaced by the closed-adapter-kind
   architecture instead of being patched further. See `SweepExecutor.sol`'s
   contract-level doc comment and `test_registerAdapterSelector_noLongerExists` /
   `test_removeAdapterSelector_noLongerExists` (proving the functions no longer exist
   at all) and `test_invalidAdapterKindOrdinal_revertsAtAbiDecode` (proving Solidity's
   ABI decoder itself rejects any adapter identifier outside the closed set).
5. TypeScript-level proof (not yet possible): once Phase 11/12 builds an approval or
   transaction-calldata builder, it must include a test (`approvalBuilder_rejectsMulticall3AsSpender`
   or equivalent) proving the builder refuses to construct an approval or write call
   targeting Multicall3. This is tracked explicitly in `docs/implementation-plan.md`'s
   Phase 11 row rather than silently assumed.

## No arbitrary execution targets in SweepExecutor

`SweepExecutor` never accepts a generic `struct Call { address target; bytes callData; }`
— confirmed absent by `grep -rn "struct Call\b" packages/contracts/src` (no matches).
Every action is one of the four typed structs in `SweepPlanLib.sol`
(`SwapAction`/`TransferAction`/`DiscardAction`/`BurnAction`). Every swap's
`adapterKind` is a closed `AdapterKind` enum (`PANCAKE_V2`/`UNISWAP_V3`), resolved via
`SweepExecutor._adapterFor` to one of exactly two immutable addresses fixed at
construction — there is no runtime allowlist check because there is no address field
in a plan to check in the first place (Codex addendum re-audit finding RA-01,
superseding the earlier `allowedAdapters` registry design).

Each adapter independently validates its own route before ever reaching a DEX call:

- **`PancakeV2Adapter`**: path must start at the swap's `tokenIn` and end at the
  settlement token; every intermediate hop token must be in `allowedIntermediateAssets`;
  `minAmountOut` must be non-zero; the route's own deadline is enforced.
- **`UniswapV3Adapter`**: identical path/intermediate/deadline/minAmountOut rules,
  applied to the packed V3 path format via `UniswapV3Path.sol`.

Neither adapter accepts a caller-supplied router or arbitrary command bytes — see
`docs/requirements-traceability.md` conflict **C-7** for why `UniswapV3Adapter` calls
SwapRouter02's fixed `exactInput` signature directly rather than wrapping Universal
Router's generic command stream in the first place.

## Frozen configuration (added by this review; adapter lifecycle removed by RA-01)

`SweepExecutor`, `PancakeV2Adapter`, and `UniswapV3Adapter` each expose
`freezeConfiguration()` (owner-only, irreversible). Once frozen:

- `SweepExecutor.registerOutputToken` / `removeOutputToken` revert with
  `ConfigurationIsFrozen`.
- Each adapter's `allowIntermediateAsset` / `disallowIntermediateAsset` revert the same way.
- `SweepExecutor.recoverStrayTokens` remains available — it is unrelated to the
  execution security boundary the freeze protects.

**Superseded by the RA-01 remediation:** `SweepExecutor` no longer has
`registerAdapter`/`removeAdapter` or an `allowedAdapters` mapping. An earlier
remediation pass (CA-01/CA-02) added an explicit `AdapterIsMulticall3` rejection to
`registerAdapter` and made `freezeConfiguration` require every registered adapter to
self-report `configurationFrozen() == true` via `IFreezableAdapter`. An independent
Codex re-audit (finding RA-01, P1) correctly identified this as insufficient:
registration still accepted any other arbitrary contract, and freeze trusted that
contract's own self-reported state — a malicious or mutable adapter could simply
return `true` while remaining free to change behavior afterward (`MockAdapter` itself
was direct evidence the predicate was forgeable). Rather than patching the predicate
further, the registry was removed: `PANCAKE_V2_ADAPTER` and `UNISWAP_V3_ADAPTER` are
now immutable constructor arguments with no post-deployment mutation path.
`IFreezableAdapter.sol` (the interface backing the old registry-trust check) has been
deleted as dead code.

**Follow-up hardening — freeze still couples to adapter-level config, but narrowly:**
a subsequent review correctly noted that immutable _addresses_ alone don't make a
"frozen" executor fully locked, since each fixed adapter's own intermediate-asset
allowlist remains separately owner-mutable. `freezeConfiguration()` now reverts
(`AdapterNotYetFrozen`) unless both `PANCAKE_V2_ADAPTER` and `UNISWAP_V3_ADAPTER`
have already frozen themselves. This is not a reintroduction of RA-01's forgeable
pattern: it reads `configurationFrozen()` from exactly the two specific,
immutable-address contracts fixed at construction, never an arbitrary or
attacker-registerable one. The constructor also now rejects an EOA (`AdapterHasNoCode`),
a duplicate adapter pair (`DuplicateAdapterAddress`), or Multicall3's real address in
either slot (`AdapterIsMulticall3`) — closing the cheap, on-chain-checkable gaps in
what the constructor previously validated (nonzero-only).

A new DEX integration or output asset requires deploying a new `SweepExecutor`/adapter
version, not a change to a deployment users already trust. Verified by
`test_freezeConfiguration_blocksFurtherOutputTokenChanges`,
`test_freezeConfiguration_blocksIntermediateAssetChanges` (both adapters),
`test_freezeConfiguration_onlyOwner` (all three contracts),
`test_freezeConfiguration_doesNotBlockRecovery`,
`test_freezeConfiguration_revertsUnlessBothAdaptersFrozen`,
`test_swapsUnaffectedByFreezeState`,
`test_constructor_rejectsAdapterWithNoCode`,
`test_constructor_rejectsDuplicateAdapterPair`,
`test_constructor_rejectsMulticall3InEitherSlot`,
`test_registerAdapterSelector_noLongerExists`, and
`test_removeAdapterSelector_noLongerExists`.

## Exact Permit2 amounts, never unlimited

`SweepPlanLib.aggregateTokenAmounts` computes the exact amount required per unique
token across every action that consumes user funds — never a duplicate entry, never
more than the plan needs. `SweepExecutor._pullViaPermit2` requests exactly those
amounts via `PermitBatchTransferFrom`. There is no code path anywhere in the contracts
that requests `type(uint256).max` from Permit2.

The _initial_ ERC-20 approval a user's wallet must grant to the canonical Permit2
contract itself (a one-time, per-token, standing `approve` — not part of TIDYR's own
signed plan) is a Phase 14 (execution scheduler) UX concern: TIDYR should request an
exact amount where practical, and if a wallet already holds a larger or unlimited
Permit2 allowance from a prior interaction, the UI should report it honestly and offer a
direct wallet-level revoke — tracked as design intent here, to be implemented when
`packages/execution` is built.

## 0x / third-party spender safety (Phase 11/12 design intent)

Not yet implemented — 0x integration doesn't exist yet. When it is built:

- Approve only the exact spender address 0x's API response designates for the specific
  flow in use (its documentation distinguishes `AllowanceHolder`, `Permit2`, and
  `Settler` execution targets — these are not interchangeable).
- Never approve 0x's general settlement/execution contract as a default.
- Validate any spender 0x returns against an allowlist derived from 0x's own official
  configuration before ever using it — treat the quote response as untrusted input.
- Never forward arbitrary 0x calldata through `SweepExecutor` directly; if 0x routes are
  ever supported, they go through a purpose-built, validating adapter with the same
  path/output/deadline constraints as `PancakeV2Adapter`/`UniswapV3Adapter` — not a
  passthrough.
