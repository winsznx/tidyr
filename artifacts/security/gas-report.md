# Gas and DoS Report — Phase 7 Task 7.11

All figures below are `forge snapshot`/isolated `gasleft()`-delta measurements against
the deterministic (non-fork) local test suite, on the same `foundry.toml` optimizer
settings (`optimizer_runs = 200`, `via_ir = true`) used throughout this repository.

## Per-operation baseline (from `.gas-snapshot`, full test-call gas including harness setup)

| Operation                                                                                    | Gas     |
| -------------------------------------------------------------------------------------------- | ------- |
| Base sweep — single ERC20-output swap (`test_swapToERC20Output_succeeds`)                    | 262,999 |
| Transfer action (`test_transferAction_consolidates`)                                         | 182,467 |
| Discard action (`test_discardAction_sendsToDeadAddress`)                                     | 181,736 |
| Burn action (`test_burnAction_reducesSupply`)                                                | 164,596 |
| DemoDistributor claim, all 5 tokens (`test_claimDemoBundle_transfersAllFiveTokens`)          | 226,262 |
| `SweepPlanLib.validatePlanShape` at exactly `MAX_ACTIONS` (`test_exactlyMaxActionsAccepted`) | 65,624  |

These four action types cost roughly the same order of magnitude (160k-260k),
dominated by the Permit2 batch pull and the single ERC20 transfer/burn call each
performs — expected, since none of them do meaningfully more work than one external
token movement plus event emission.

## Plan-shape extremes (new this session, `test/SweepExecutorGas.t.sol`)

Isolated `executeSweep`-only gas (measured via a `gasleft()` delta around just the
call, excluding test-harness setup like token deployment/minting/approval, which is
not part of the contract's own cost):

| Plan shape                                                                                                                | Isolated `executeSweep` gas |
| ------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| 50 transfer actions, same token, same recipient (cheapest way to hit `MAX_ACTIONS`)                                       | 703,462                     |
| 50 transfer actions, 50 distinct tokens, same recipient (worst realistic case for `aggregateTokenAmounts`'s O(n²) dedupe) | 3,605,566                   |
| Mixed: 10 swaps + 10 transfers + 10 discards (typical large real-world sweep)                                             | 970,382                     |

**Command:**

```bash
cd packages/contracts
forge test --match-contract SweepExecutorGasTest -vv
```

## DoS analysis

1. **`aggregateTokenAmounts` is O(n²) in the number of unique tokens.** This is
   documented at the point of definition
   (`SweepPlanLib.sol::aggregateTokenAmounts`'s own doc comment: "O(n^2) in total
   action count, bounded by MAX_ACTIONS (50), so worst case is a fixed, small, audited
   cost - not user-influenced beyond that bound"). The 50-distinct-token measurement
   above (3.6M gas) is the actual worst case this quadratic behavior can ever reach,
   since `MAX_ACTIONS = 50` is enforced by `validatePlanShape` before any of these
   loops run, and it is not extendable by an attacker — a plan is authored and signed
   by its own owner, who pays the gas for their own plan and has no incentive to
   construct a maximally expensive one against themselves.
2. **3.6M gas for the worst case is well within normal single-transaction bounds** on
   any EVM-compatible chain with a block gas limit in the tens of millions (Ethereum
   mainnet's is ~30M as of this writing; Monad's own limit was not independently
   re-verified as part of this report and should be confirmed against
   `docs/research/monad-source-map.md`/live network data before Phase 9 deployment,
   but 3.6M is comfortably below any EVM chain's practical minimum block gas limit in
   production use today).
3. **`routeData` cannot become an unbounded DoS vector.** Each adapter decodes
   `routeData` as a bounded structure (`PancakeV2Adapter`: `abi.decode(routeData,
(address[]))`, a plain path array; `UniswapV3Adapter`: a packed V3 path via
   `UniswapV3Path.sol`, whose `tokenAt`/hop-count logic operates on the path's own
   fixed byte-stride encoding). Neither interprets `routeData` as executable bytecode,
   call data for an arbitrary target, or anything that could recursively expand gas
   cost beyond the path's own hop count - and hop count is implicitly bounded by the
   same `MAX_ACTIONS`-bounded plan and by gas itself (a path long enough to be a DoS
   concern would simply run out of gas within the single swap action, reverting that
   action - fatal only if `allowFailure` is false, exactly like any other
   insufficiently-funded action).
4. **Event volume is reasonable.** Every action emits exactly one `ActionExecuted` or
   `ActionFailed` event; at `MAX_ACTIONS = 50` that's at most 50 action-level events
   plus one `SweepCompleted` per plan - not a meaningfully larger log volume than the
   50 token-movement calls already imply.
5. **Loops are bounded.** Every loop in `SweepExecutor.sol` iterates over either
   `plan.swaps`/`transfers`/`discards`/`burns` (each individually bounded by the
   overall `MAX_ACTIONS` total) or `tokens[]` (the deduplicated aggregate, itself
   bounded by the same total). None iterates over unbounded external state.

## Gas recommendation for Monad (narrow buffers)

Per the operating instructions' note that "Monad charges against submitted gas
limit": callers/wallets estimating gas for `executeSweep` should use a narrow buffer
over `eth_estimateGas`'s result (e.g. 10-15%, not a blanket 2x or fixed large
constant), since overestimating gas limit on Monad has a direct cost unlike chains
that only charge for gas actually consumed regardless of the submitted limit. This is
a wallet/execution-layer (`packages/execution`, Phase 14) concern, not a contract-level
one - recorded here as the gas-report's cross-reference to that future work, per Task
7.11's explicit request, not implemented in this contracts-only phase.

## Reproducing this report

```bash
cd packages/contracts
forge snapshot                                            # full .gas-snapshot regeneration
forge test --match-contract SweepExecutorGasTest -vv       # isolated executeSweep-only figures above
```
