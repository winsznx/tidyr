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
3. Multicall3 must never be registered as an adapter, router, spender, or transfer
   recipient.
4. Contract-level proof: `packages/contracts/test/SweepExecutor.t.sol::test_multicall3_rejectedAsUnregisteredAdapter`
   constructs a plan with Multicall3's real verified address as the swap adapter and
   confirms it reverts with `AdapterNotAllowed` — the same rejection any other
   unregistered address gets, with nothing special carved out.
5. TypeScript-level proof (not yet possible): once Phase 11/12 builds an approval or
   transaction-calldata builder, it must include a test (`approvalBuilder_rejectsMulticall3AsSpender`
   or equivalent) proving the builder refuses to construct an approval or write call
   targeting Multicall3. This is tracked explicitly in `docs/implementation-plan.md`'s
   Phase 11 row rather than silently assumed.

## No arbitrary execution targets in SweepExecutor

`SweepExecutor` never accepts a generic `struct Call { address target; bytes callData; }`
— confirmed absent by `grep -rn "struct Call\b" packages/contracts/src` (no matches).
Every action is one of the four typed structs in `SweepPlanLib.sol`
(`SwapAction`/`TransferAction`/`DiscardAction`/`BurnAction`), and every swap's `adapter`
field is checked against `allowedAdapters` before any external call
(`SweepExecutor.sol`, `executeSweep`'s swap-validation loop).

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

## Frozen configuration (added by this review)

`SweepExecutor`, `PancakeV2Adapter`, and `UniswapV3Adapter` each expose
`freezeConfiguration()` (owner-only, irreversible). Once frozen:

- `SweepExecutor.registerAdapter` / `removeAdapter` / `registerOutputToken` /
  `removeOutputToken` all revert with `ConfigurationIsFrozen`.
- Each adapter's `allowIntermediateAsset` / `disallowIntermediateAsset` revert the same way.
- `SweepExecutor.recoverStrayTokens` remains available — it is unrelated to the
  execution security boundary the freeze protects.

A new DEX integration or output asset after freezing requires deploying a new
`SweepExecutor`/adapter version, not a change to a deployment users already trust.
Verified by `test_freezeConfiguration_blocksFurtherAdapterAndOutputTokenChanges`,
`test_freezeConfiguration_blocksIntermediateAssetChanges` (both adapters),
`test_freezeConfiguration_onlyOwner` (all three contracts), and
`test_freezeConfiguration_doesNotBlockRecovery`.

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
