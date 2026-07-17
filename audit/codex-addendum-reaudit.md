# Independent TIDYR Security Addendum Remediation Re-audit

## Verdict

**FAIL — Phase 7 may not begin.**

Counts: **P0 0 · P1 1 · P2 2 · P3 2**.

CA-01 is only partially remediated and remains **unresolved as P1**. The canonical Multicall3 address is now correctly rejected during registration, with exact address comparison that cannot be bypassed by checksum casing because Solidity addresses are 160-bit values. Zero remains rejected and valid non-Multicall addresses remain registerable.

The second half of CA-01 is not securely fixed. Registration still accepts any other contract, and freeze trusts that arbitrary contract's `configurationFrozen()` return value. There is no identity, code-hash, factory, proxy, or immutable-implementation validation. A malicious/mutable adapter can return `true`, be permanently blessed, and change behavior after executor freeze. The existing MockAdapter is direct evidence that the predicate is insufficient: it defaults to `configurationFrozen == true`, yet its mode, ratio, and reported frozen flag remain mutable.

This is the practical forged-readiness bypass the re-audit rules require classification as P1.

## Repository and commits

The branch is correct and locally linear. `c828243` records the original audit; four later commits perform code/test, hash-test, formatting, and documentation remediation. No Phase 7 implementation, unrelated feature, disabled/weakened test, tracked secret, private key, or blanket suppression was found.

Without a trusted remote/ref history, rewritten history cannot be disproven beyond local ancestry: `c828243` is the merge base and HEAD is four linear commits ahead.

## Prior finding disposition

- **CA-01:** unresolved — specific Multicall3 guard fixed, forged freeze readiness remains P1.
- **CA-02:** partially resolved — enumeration/removal behavior added, but empty/invalid configuration and real-adapter readiness coverage remain.
- **CA-03:** resolved — recipient correctly distinguished from pull-authority roles.
- **CA-04:** resolved — all ten claimed new mutation tests exist and pass.
- **CA-05:** resolved — explicit pricing/oracle acceptance gates tracked.
- **CA-06:** resolved — manual generic-token/no-demo-allowlist gates tracked.
- **CA-07:** partially resolved — scoped grep evidence corrected, but stale absolute claims remain in historical status/table text.
- **CA-08:** resolved — contract-root `forge fmt --check` passes.
- **CA-09:** resolved — current vector/count references updated; old vector is clearly Phase 2 history.
- **CA-10:** partially resolved — original totals fixed, but remediation summaries now say eight instead of nine lower-severity findings.

## Four claimed CA-01 tests

The four tests exist at `packages/contracts/test/SweepExecutor.t.sol:496-542`.

Only two expose the old vulnerability directly: explicit owner registration of Multicall3 now reverts, and an adapter reporting false now blocks freeze. The all-frozen-success and removed-adapter-success cases also succeeded under the old unconditional freeze, so they are compatibility/enumeration tests rather than pre-fix vulnerability detectors. All four pass currently, but none challenges a malicious adapter returning a forged true value, and none uses the real Pancake and Uniswap adapters in the executor-freeze lifecycle.

## Execution hash

The Solidity and TypeScript golden-vector tests pass with identical value `0xdf7a8dd0108003ffa8b036d6471d7a6479a56d02b6b7737737c398e3515100d1`.

The implementation binds chain ID, actual executor, owner, recipient, output token, deadline, nonce, ordered action arrays, token, exact amount, adapter, route hash, minimum output, and action semantics. Dynamic bytes are hashed before fixed-width ABI encoding, and arrays are encoded as `bytes32[]`, not ambiguous packed dynamic values. `displayManifestHash` remains distinct.

Six new Solidity and four new TypeScript mutation tests exist and pass. Independent extra mutations confirmed input token, `allowFailure`, and action type also change the hash.

## Validation

- Deterministic Solidity: **97 passed, 0 failed, 0 skipped**.
- Monad fork: **2 passed, 0 failed, 0 skipped**, using live Monad factory/pair state.
- Invariants: **2 passed**, **8,192 calls each**, zero handler reverts.
- Fuzz: **3 properties × 2,048 CI-profile runs**, all passed.
- TypeScript: **30 passed, 0 failed, 0 skipped**.
- Install, root format, lint, typecheck, build, test, secret scan: passed.
- `forge fmt --check`, clean build: passed.
- Slither: **failed with exit 255**, 38 reports across 48 analyzed contracts. Phase 7 remains the planned Slither-hardening phase, so this is recorded as a non-green configured command rather than treated as a missing future deliverable.

## Remaining findings

1. **RA-01 / P1:** arbitrary adapters can forge `configurationFrozen() == true` and remain mutable after executor freeze.
2. **RA-02 / P2:** freeze permits undefined empty/invalid configuration and lacks real Pancake/Uniswap readiness lifecycle tests.
3. **RA-03 / P2:** unbounded every-ever adapter history can make freeze exceed practical gas limits.
4. **RA-04 / P3:** remediation documents miscount nine prior P2/P3 findings as eight.
5. **RA-05 / P3:** stale false no-Multicall absolutes remain alongside later corrections.

Structured evidence is in `audit/codex-addendum-reaudit-findings.json`, with the prior-finding matrix and command log in adjacent files.

**Phase 7 may not begin.**

