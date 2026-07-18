# Phase 10 — Freeze Packet (Prepared for Review Only, NOT Broadcast)

**Status: PREPARED FOR HUMAN APPROVAL ONLY. No freeze transaction has been
sent. `configurationFrozen()` is confirmed `false` on the executor and both
adapters as of this packet.**

Prepared immediately after the successful, independently-verified Phase 10
engineering smoke test (`deployments/mainnet.json` → `phase10.smokeSweep`,
tx `0xc2396b545c1b7fa9a068c42fbcebfaaf0f87203365cc4e87a6ca21301fbd4363`,
status success, executor/adapter balances confirmed zero, nonce consumed
exactly once).

## Freeze readiness checklist (re-verified live, this session)

| Requirement                                                              | Result                                                                                                                                                                        |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| MON_SENTINEL (`0xEeee...EEeE`) is allowed                                | ✅ `true`                                                                                                                                                                     |
| Canonical USDC (`0x754704Bc059F8C67012fEd69BC8A327a5aafb603`) is allowed | ✅ `true`                                                                                                                                                                     |
| No unintended output token allowed                                       | ✅ WMON and all 5 DUST tokens confirmed `false`                                                                                                                               |
| Deployed adapter immutables remain correct                               | ✅ `UniswapV3Adapter.ROUTER() == 0xfE31F71C1b106EAc32F1A19239c9a9A72ddfb900`, `.WMON() == 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A` — both match the Phase 9 record exactly |
| Adapter bytecode matches recorded deployments                            | ✅ Per Phase 9's `identityGate.check3_maskedRuntimeBytecodeComparison` (masked-immutable runtime bytecode match); no redeploy has occurred since                              |
| `configurationFrozen()` currently false                                  | ✅ Confirmed `false` on `SweepExecutor`, `PancakeV2Adapter`, and `UniswapV3Adapter`                                                                                           |
| Freeze is irreversible                                                   | ✅ No `unfreeze` function exists in any of the three contracts                                                                                                                |
| No future product requirement needs another executor output token        | ✅ PRD scope only ever names MON and USDC as sweep outputs                                                                                                                    |

## The three freeze transactions (sequence, not yet sent)

Both adapters must be frozen before the executor's freeze will succeed — the
executor's `freezeConfiguration()` reverts with `AdapterNotYetFrozen` until
both adapters report `configurationFrozen() == true` (confirmed live during
the original confirmation packet and unchanged since).

### F1. PancakeV2Adapter.freezeConfiguration()

| Field                                   | Value                                                                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sender                                  | `0xbde0076F05B5eA898F9ca51f1b595D84598DE586`                                                                                                                   |
| Target                                  | `0xBB86D6ef057F03Ca0bcaB9f87B61894977B0dBcb`                                                                                                                   |
| Function                                | `freezeConfiguration()`                                                                                                                                        |
| Selector                                | `0x8d9bad95`                                                                                                                                                   |
| Calldata                                | `0x8d9bad95`                                                                                                                                                   |
| Native value                            | 0                                                                                                                                                              |
| Current account nonce                   | 23                                                                                                                                                             |
| Fresh gas estimate (live, this session) | 59,142                                                                                                                                                         |
| Proposed gas limit                      | 75,000                                                                                                                                                         |
| Estimated MON cost                      | ≈0.00603–0.00765 MON                                                                                                                                           |
| Expected state change                   | `PancakeV2Adapter.configurationFrozen` false → true; blocks only `allowIntermediateAsset`/`disallowIntermediateAsset` going forward — does not affect `swap()` |

### F2. UniswapV3Adapter.freezeConfiguration()

| Field                                   | Value                                                                 |
| --------------------------------------- | --------------------------------------------------------------------- |
| Sender                                  | deployer                                                              |
| Target                                  | `0xE80d042fBDC03Da8262ED0669c75a394d2437D27`                          |
| Function                                | `freezeConfiguration()`                                               |
| Selector                                | `0x8d9bad95`                                                          |
| Calldata                                | `0x8d9bad95`                                                          |
| Native value                            | 0                                                                     |
| Current account nonce                   | 24 (after F1)                                                         |
| Fresh gas estimate (live, this session) | 59,154                                                                |
| Proposed gas limit                      | 75,000                                                                |
| Estimated MON cost                      | ≈0.00603–0.00765 MON                                                  |
| Expected state change                   | `UniswapV3Adapter.configurationFrozen` false → true; same scope as F1 |

### F3. SweepExecutor.freezeConfiguration()

| Field                 | Value                                                                                                                                                                                          |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sender                | deployer                                                                                                                                                                                       |
| Target                | `0x7a844005998e896967A8b2BdA13c7826F387E9c3`                                                                                                                                                   |
| Function              | `freezeConfiguration()`                                                                                                                                                                        |
| Selector              | `0x8d9bad95`                                                                                                                                                                                   |
| Calldata              | `0x8d9bad95`                                                                                                                                                                                   |
| Native value          | 0                                                                                                                                                                                              |
| Current account nonce | 25 (after F1, F2)                                                                                                                                                                              |
| Gas estimate          | 57,333 (fork-measured after freezing both adapters there — cannot be live-estimated on real mainnet until F1/F2 are actually sent, since it currently reverts with `AdapterNotYetFrozen`)      |
| Proposed gas limit    | 75,000                                                                                                                                                                                         |
| Estimated MON cost    | ≈0.00585–0.00765 MON                                                                                                                                                                           |
| Expected post-state   | `SweepExecutor.configurationFrozen() == true`; `allowedOutputTokens` permanently fixed to exactly MON_SENTINEL and USDC; `registerOutputToken`/`removeOutputToken` revert for all future calls |

**Total freeze sequence: ≈175,629 gas, ≈0.0179–0.0230 MON.**

## Stop — awaiting human approval

This packet is prepared but not authorized to broadcast. Sending F1/F2/F3
requires the same per-transaction review-and-approve pattern used for the
Phase 10 smoke sequence, in a separate step.
