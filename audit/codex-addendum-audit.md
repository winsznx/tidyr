# Independent Security Addendum Audit

## Verdict

**FAIL — Phase 7 may not begin.**

The reported statement “0 P0 and 0 exploitable P1 findings” is not supported. No P0 was found, but CA-01 is a P1 unsafe-adapter/configuration-boundary issue: the owner can register Multicall3 or any arbitrary adapter before freezing, and freezing permanently preserves that reachability. The named test proves only that an address which was never registered is rejected.

Counts: **P0 0 · P1 1 · P2 7 · P3 2**.

## Scope and Git result

This review covered Phases 0–6, the approval/Permit2/generic-token addendum, commits `ab3d458`, `9de4c84`, and `0276555`, the addendum report, and its evidence. Phase 7–16 implementation was not demanded early.

The branch is a linear three-commit descendant of `build/pre-frontend-production` (`124c0b9`) and its diff is limited to hash binding, freeze/test changes, a gas snapshot, and documentation/evidence. No unrelated application feature, tracked secret, disabled test, blanket suppression, or future-phase implementation was hidden in the range. Whether older history was rewritten cannot be proven from local refs alone because no trusted remote history was supplied.

## Security conclusions

### Execution plan hash

The implementation correctly uses `block.chainid` and the actual `address(this)`. Solidity and TypeScript use the same `abi.encode` model. Each dynamic action is element-hashed, `routeData` is hashed to `bytes32`, and arrays of fixed-size hashes are ABI-encoded, avoiding packed dynamic-data ambiguity. The cross-language golden vector passes.

An independent ephemeral mutation run proved that chain ID, executor, owner, recipient, output token, input amount, adapter, route bytes, minimum output, deadline, nonce, and action order each change the TypeScript hash. The Solidity source binds the same fields. The committed regression suites nevertheless omit four required field mutations on both sides (CA-04).

`displayManifestHash` and `executionPlanHash` remain intentionally distinct.

### Permit2

The executor imports the canonical vendored `ISignatureTransfer`, calls `permitWitnessTransferFrom`, sends pulls only to itself, requests exact aggregated token amounts, uses the plan deadline/nonce, binds the witness to the execution hash, and requires `msg.sender == plan.owner`. AllowanceTransfer is not the production authorization path. Valid, modified-witness, replay, expiry, wrong-spender, excessive-pull, and duplicate aggregation tests pass against the real vendored Permit2 contract.

No current production approval builder exists, so initial user-to-Permit2 approval construction is correctly a later-phase concern; current shared types do not force unlimited approval.

### Multicall3, arbitrary execution, and freeze

There is no generic `{target, callData}`, delegatecall, or generic-selector executor interface. This is strong primary protection.

However, `registerAdapter` accepts any nonzero address, including the verified Multicall3 address. `freezeConfiguration` then freezes that unchecked set. The Multicall3 test does not call `registerAdapter`; it proves only the default false mapping entry. The executor also does not require registered adapters to have frozen their own configuration. These facts invalidate the claimed frozen security boundary (CA-01/CA-02).

The plan recipient accepts Multicall3 despite documentation marking “never recipient” complete (CA-03). The repository-wide no-match evidence is also false because the test itself contains the references (CA-07).

### Balance and action safety

Input baselines are recorded before Permit2 pulls, settlement/native baselines are separate, only positive deltas are paid or returned, duplicate inputs are aggregated, settlement-token swap input is rejected, and required/optional swap behavior is atomic. Pre-existing input/output/native balances were not found to leak. Unit, fuzz, and invariant execution supports this conclusion.

Burn and discard operate on plan-pulled executor balances; discard uses the fixed dead address. No executor-side user allowance revocation exists. Successful under-delivery always reverts, while an allowed reverted subcall returns input through the remainder path.

### Demo tokens and pricing deferrals

No contract or shared action schema hardcodes the five demo tokens as permitted production inputs. Adapters accept arbitrary ERC-20 endpoints subject to path and route behavior. No production fake USD oracle or fixed MON/USD value was found; `minAmountOut` remains the on-chain safety control.

The architecture does not prevent later discovery or PriceService work, but formal future-phase tracking is incomplete: manual arbitrary-token entry/no-demo-allowlist acceptance and PriceService/oracle acceptance requirements are missing from the implementation plan/traceability gates (CA-05/CA-06). This fails the user's conditions for accepting those items as deferred.

## Verification results

- TypeScript: **26 passed, 0 failed, 0 skipped**.
- Deterministic Solidity: **87 passed, 0 failed, 0 skipped**.
- Monad fork: **2 passed, 0 failed, 0 skipped**.
- Invariants: **2 passed**, each with **8,192 calls**, zero reverts.
- Fuzz: **3 properties passed at 2,048 runs each** under the CI profile.
- Root format/lint/typecheck/test/build/secret scan: passed.
- `forge build`: passed after clean.
- `forge fmt --check`: failed from the correct contracts directory.
- Slither: exited 255 with 37 reports; expected/noise reports were manually triaged, but the command is not green.

## Top findings

1. **CA-01 (P1):** freeze can bless Multicall3 or any arbitrary adapter.
2. **CA-02 (P2):** freeze lacks readiness and cross-adapter frozen-state validation.
3. **CA-03 (P2):** Multicall3 recipient prohibition is not enforced despite being marked complete.
4. **CA-05/CA-06 (P2):** deferred pricing and generic-token requirements lack formal acceptance tracking.
5. **CA-07/CA-08 (P2):** grep and Solidity-format evidence do not reproduce.

Full structured findings are in `audit/codex-addendum-findings.json`; the requirements matrix and command log are adjacent to this report.

