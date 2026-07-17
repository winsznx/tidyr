# Security Addendum Remediation Re-audit Matrix

| Prior ID | Claimed remediation commit | Independent status | Evidence |
| --- | --- | --- | --- |
| CA-01 | `4980f95` | **Unresolved** | Canonical Multicall3 registration now reverts, but arbitrary adapters can forge `configurationFrozen() == true`; RA-01 |
| CA-02 | `4980f95` | **Partially resolved** | Active entries are enumerated and removed entries skipped; empty/invalid readiness and real-adapter lifecycle coverage remain; RA-02 |
| CA-03 | `3833920` | Resolved | Recipient correctly documented as a transfer destination without pull authority; conflict C-8 records rationale |
| CA-04 | `9876087` | Resolved | Six Solidity and four TypeScript mutation tests added; all pass |
| CA-05 | `3833920` | Resolved | Explicit Phase 11 PriceService/oracle tests tracked in implementation plan and traceability |
| CA-06 | `3833920` | Resolved | Manual arbitrary-token/no-demo-allowlist acceptance tests tracked for Phase 11/12 |
| CA-07 | `3833920` | **Partially resolved** | Scoped grep evidence is corrected, but stale false absolutes remain in historical status/table text; RA-05 |
| CA-08 | `374d3cb` | Resolved | `forge fmt --check` passes from `packages/contracts` |
| CA-09 | `3833920` | Resolved | Current traceability/vector uses `0xdf7a...5100d1`; old hash remains only in Phase 2 history |
| CA-10 | `3833920` | **Partially resolved** | Original severity table count corrected, but remediation text now miscounts nine findings as eight; RA-04 |

## Four claimed CA-01 regression tests

| Test | Vulnerability/property | Pre-fix behavior | Current behavior | Strength |
| --- | --- | --- | --- | --- |
| `test_registerAdapter_rejectsMulticall3Explicitly` (`SweepExecutor.t.sol:496`) | Owner directly registers canonical Multicall3 | Would not revert; exposes old bug | Reverts `AdapterIsMulticall3` | Strong, exact reproduction |
| `test_freezeConfiguration_revertsIfRegisteredAdapterNotFrozen` (`:511`) | Active adapter reports unfrozen | Old freeze succeeds, so assertion fails | Reverts `RegisteredAdapterNotFrozen` | Proves boolean check only; not identity or real freeze semantics |
| `test_freezeConfiguration_succeedsWhenAllRegisteredAdaptersFrozen` (`:521`) | Adapter reports true | Old unconditional freeze also succeeds | Succeeds | Compatibility test, not a pre-fix vulnerability detector; mock remains mutable |
| `test_freezeConfiguration_ignoresRemovedAdapters` (`:533`) | Removed adapter is skipped | Old unconditional freeze also succeeds | Succeeds | Enumeration-policy test, not a pre-fix vulnerability detector |

No executor-level tests use an unfrozen real PancakeV2Adapter or UniswapV3Adapter.

## Execution hash

- Current Solidity/TypeScript vector: `0xdf7a8dd0108003ffa8b036d6471d7a6479a56d02b6b7737737c398e3515100d1`.
- Bound in both implementations: chain, executor, owner, recipient, output token, deadline, nonce, display manifest, ordered action arrays, input token, amount, adapter, route hash, minimum output, and `allowFailure`.
- Six new Solidity mutations: owner, adapter, route, minimum output, chain, executor.
- Four new TypeScript mutations: owner, adapter, route, minimum output.
- All ten pass. Existing tests cover amount, recipient, output, deadline, nonce, order, and hash distinctness.
- Independent ephemeral mutations additionally confirmed input token, `allowFailure`, and action type change the TypeScript hash.
- Element hashing and `abi.encode(bytes32[])` avoid packed dynamic-array/bytes ambiguity.

## Documentation/deferred capabilities

- Dynamic discovery and PriceService/oracle integration remain explicitly not started.
- Phase 11/12 acceptance gates now cover manual token entry, demo-allowlist prohibition, executable/reference values, stale/low-confidence data, and `minAmountOut` independence.
- No Phase 7 completion claim was found; project status says Phase 7 has not begun.

