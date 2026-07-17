# Security Addendum — Test Results

Exact commands and results for every claim in `findings.md`. Run on
`fix/security-addendum-before-phase-7`, after the chainId/executor binding and
freeze-mechanism changes.

## Solidity — deterministic suite (excludes fork and invariant tests)

```
cd packages/contracts
forge build
forge test --no-match-path "*.fork.t.sol" --no-match-contract SweepExecutorInvariantsTest
```

Result: **87 passed, 0 failed, 0 skipped**, across 9 test suites:

| Suite                                   | Tests | New in this review                                       |
| --------------------------------------- | ----- | -------------------------------------------------------- |
| `ToolchainSmoke.t.sol`                  | 1     | —                                                        |
| `SweepPlanLib.t.sol`                    | 12    | chainId/executor now parameters of every `hashPlan` call |
| `Permit2Witness.t.sol`                  | 7     | signing helper updated for the new `hashPlan` signature  |
| `SweepExecutor.t.sol`                   | 26    | +3 freeze tests, +1 explicit Multicall3-rejection test   |
| `PancakeV2Adapter.t.sol`                | 12    | +2 freeze tests                                          |
| `UniswapV3Adapter.t.sol`                | 13    | +2 freeze tests                                          |
| `SweepExecutorAdapterIntegration.t.sol` | 2     | signing helper updated                                   |
| `DemoToken.t.sol`                       | 6     | —                                                        |
| `DemoDistributor.t.sol`                 | 8     | —                                                        |

## Solidity — mainnet fork tests

```
forge test --match-path "*.fork.t.sol"
```

Result: **2 passed, 0 failed** — real swap against the live PancakeSwap V2 WMON/USDC
pair on Monad mainnet, unaffected by this review's changes (doesn't touch `hashPlan`).

## Solidity — invariant suite

```
forge test --match-contract SweepExecutorInvariantsTest -vv
```

Result: **2 passed, 0 failed** —
`invariant_executorRetainsNoTouchedTokenBalance` and `invariant_nonceMatchesCallCount`,
both still holding across 128 runs x 64 calls (8,192 total) with the new
`hashPlan(plan, block.chainid, address(EXECUTOR))` signing path wired into the handler.

## TypeScript — full workspace

```
pnpm typecheck   -> 6/6 packages pass
pnpm build       -> 6/6 packages pass
pnpm test        -> all packages pass; packages/transaction-review: 16 tests
                    (was 14 - +2 for chainId/executor sensitivity)
pnpm lint        -> clean
pnpm format      -> clean
```

`packages/transaction-review/src/executionPlanHash.test.ts`'s
"vector A executionPlanHash matches the Solidity golden value" test is the
cross-language proof that both sides still agree byte-for-byte after the chainId/executor
change: `0xdf7a8dd0108003ffa8b036d6471d7a6479a56d02b6b7737737c398e3515100d1`.

## Secret scan

```
bash scripts/scan-secrets.sh
```

Result: `No secret patterns found in tracked files.`

## Manual grep verification (findings F-1 through F-4, F-8)

```
rg -n -i multicall packages apps
  -> many matches once vendored dependencies are included: OpenZeppelin's own unrelated
     call-batching Multicall.sol utility and forge-std's own IMulticall3/
     MULTICALL3_ADDRESS helper, both under packages/contracts/lib/ — neither related to
     TIDYR's adapter/spender risk (Codex addendum audit finding CA-07; an earlier
     version of this artifact incorrectly reported "no matches" for the unscoped
     command)

rg -n -i multicall packages/contracts/src packages/shared packages/routing packages/transaction-review packages/execution apps
  -> STALE as of the RA-01 remediation (see below) — this line originally recorded 3
     matches for the CA-01-era registry fix (MULTICALL3_ADDRESS constant,
     AdapterIsMulticall3 error, explicit-rejection check in registerAdapter). That
     entire mechanism was deleted when the adapter registry was removed. A follow-up
     hardening pass then reintroduced MULTICALL3_ADDRESS/AdapterIsMulticall3 in a
     different form — an explicit constructor-time check rejecting Multicall3's real
     address in either fixed adapter slot — so the current scoped grep again finds
     matches confined to packages/contracts/src/SweepExecutor.sol, all intentional.
     Re-run this command against current `src/` before treating any specific count as
     authoritative; treat this note, not the historical number, as current.

grep -rn "struct Call\b" --include="*.sol" packages/contracts/src packages/contracts/test
  -> no matches

grep -rn "\.call(\|\.call{value" --include="*.sol" packages/contracts/src
  -> only SweepExecutor.sol's native-MON send to plan.recipient

grep -rn "\.approve(\|forceApprove(" --include="*.sol" packages/contracts/src
  -> STALE reference to `action.adapter` — that field was renamed to `action.adapterKind`
     by the RA-01 remediation (an enum identifier, not an address, so it is never an
     approval target). The approve/forceApprove targets are now: the fixed adapter
     resolved via `SweepExecutor._adapterFor(action.adapterKind)`, or an adapter's own
     immutable `ROUTER`/pair address — never a plan-supplied address either way.
```

## Gas snapshot

```
forge snapshot --no-match-path "*.fork.t.sol" --no-match-contract SweepExecutorInvariantsTest
```

Updated `packages/contracts/.gas-snapshot` to reflect the new tests and the small gas
delta from `chainId`/`executor` now being ABI-encoded into every `hashPlan` call.
