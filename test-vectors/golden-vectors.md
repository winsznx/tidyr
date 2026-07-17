# Golden Cross-Language Hash Vectors

Phase 2 requires that `packages/contracts/src/libraries/SweepPlanLib.sol` (Solidity) and
`packages/transaction-review/src/executionPlanHash.ts` (TypeScript) produce byte-identical
`executionPlanHash` values for the same logical plan. This document records the vector,
where it is reproduced on each side, and the exact value both sides must assert against.

Neither side treats this file as the source of truth at runtime — it is a human-readable
record of what was cross-verified and when. The actual assertions live in:

- `packages/contracts/test/SweepPlanLib.t.sol` (`VECTOR_A_EXPECTED_HASH`)
- `packages/transaction-review/src/executionPlanHash.test.ts` (`VECTOR_A_EXPECTED_HASH`)

## Vector A

One swap action, one transfer action, no discards, no burns.

| Field                   | Value                                                     |
| ----------------------- | --------------------------------------------------------- |
| `owner`                 | `0x1111111111111111111111111111111111111111`              |
| `recipient`             | `0x2222222222222222222222222222222222222222`              |
| `outputToken`           | `0x754704Bc059F8C67012fEd69BC8A327a5aafb603` (Monad USDC) |
| `deadline`              | `1800000000`                                              |
| `nonce`                 | `0`                                                       |
| `displayManifestHash`   | `keccak256("display-manifest-vector-a")`                  |
| `swaps[0].tokenIn`      | `0x3333333333333333333333333333333333333333`              |
| `swaps[0].amountIn`     | `200000000000000000000` (200e18)                          |
| `swaps[0].adapter`      | `0x4444444444444444444444444444444444444444`              |
| `swaps[0].minAmountOut` | `100`                                                     |
| `swaps[0].routeData`    | `0x1234`                                                  |
| `swaps[0].allowFailure` | `false`                                                   |
| `transfers[0].token`    | `0x3333333333333333333333333333333333333333`              |
| `transfers[0].amount`   | `50000000000000000000` (50e18)                            |
| `transfers[0].to`       | `0x2222222222222222222222222222222222222222`              |

**Expected `executionPlanHash`:**
`0x184bb27ccf4286fdd2f69be2433e59715e5ce345badd2ba2f5688bd2368f1de5`

Derivation: computed by running `forge test -vvv` against
`SweepPlanLibTest::test_vectorA_printHash` (the Solidity implementation), then
independently reproduced by running the TypeScript implementation
(`executionPlanHash.test.ts`) against a hand-built plan with identical field values.
Both sides produced the same value before this document was written — this is not an
assumed/fabricated constant.

## Sensitivity properties verified (both languages, same vector)

| Change                                                                  | Hash changes?    |
| ----------------------------------------------------------------------- | ---------------- |
| `swaps[0].amountIn` +1e18                                               | yes              |
| `recipient` changed                                                     | yes              |
| `outputToken` changed (USDC → WMON)                                     | yes              |
| `deadline` +1                                                           | yes              |
| `nonce` +1                                                              | yes              |
| Swap action order reversed (2-swap variant)                             | yes              |
| Compare `executionPlanHash` vs. `displayManifestHash` for the same plan | always different |

## Why two independent hashes (PRD §19.3)

`displayManifestHash` is `keccak256` of an RFC 8785 (JCS) canonical JSON string — a
human-readable manifest with no ABI-level detail. `executionPlanHash` is `keccak256` of
ABI-encoded struct fields, including per-action-array sub-hashes. These are different
byte representations of related but distinct data (the display manifest omits
`adapter`/`routeData`/`minAmountOut` details the contract needs); they must never be
expected to collide, and the test suite explicitly asserts they don't for the same
logical plan.

## Reproducing this vector

```bash
# Solidity side
cd packages/contracts && forge test --match-test test_vectorA_printHash -vvv

# TypeScript side
cd packages/transaction-review && node --test --experimental-strip-types src/executionPlanHash.test.ts
```
