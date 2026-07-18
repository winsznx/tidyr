# Deployment Preflight — Phase 8

Phase 8 is **"Mainnet deployment tooling + preflight (no broadcast)"**
(`docs/implementation-plan.md`) — a **stop gate** requiring explicit user approval
before Phase 9 (the actual mainnet broadcast). This document describes what Phase 8
built and how to run it in its intended, non-broadcasting mode.

## What exists

- `packages/contracts/script/Deploy.s.sol` — deploys `PancakeV2Adapter`,
  `UniswapV3Adapter`, `SweepExecutor`, five demo tokens, and `DemoDistributor`;
  transfers ownership toward `PROTOCOL_OWNER_ADDRESS`; runs the adapter-identity
  verification gate (checks 1/2/4/5/6 of 8); writes `deployments/mainnet.json`.
- `scripts/verify-deployment-bytecode.mjs` — the companion check (check 3 of 8):
  compares each deployed adapter's live runtime bytecode against the compiled
  artifact, masking the byte ranges Solidity's immutables occupy (read from the
  artifact's own `deployedBytecode.immutableReferences` metadata), so legitimate
  per-deployment constructor arguments never cause a false mismatch. Validated
  against a local Anvil deployment during Phase 8 (a genuine match passes; a
  mismatched contract at the same address fails with the exact byte-length reason) -
  not asserted without that evidence.

Together these implement all eight checks
`docs/requirements-traceability.md` Section 2 mandates.

## Required environment variables

All of these must be set (see `.env.example`) before running either script:

| Variable                   | Purpose                                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `MONAD_RPC_URL`            | RPC endpoint (defaults to `https://rpc.monad.xyz` if unset)                                                         |
| `PERMIT2_ADDRESS`          | canonical Permit2                                                                                                   |
| `WMON_ADDRESS`             | canonical WMON                                                                                                      |
| `PANCAKE_V2_FACTORY`       | canonical PancakeSwap V2 factory                                                                                    |
| `UNISWAP_V3_SWAP_ROUTER02` | canonical Uniswap SwapRouter02                                                                                      |
| `PROTOCOL_OWNER_ADDRESS`   | the address ownership will be transferred toward (public address only)                                              |
| `DEPLOYER_PRIVATE_KEY`     | **never** set this in a chat message or a runtime service — place it in a local, gitignored `.env.deploy` file only |

## Phase 8 mode: preflight/dry-run (no broadcast)

```bash
cd packages/contracts
source ../../.env.deploy   # loads DEPLOYER_PRIVATE_KEY and the rest locally, never committed
forge script script/Deploy.s.sol --rpc-url "$MONAD_RPC_URL"
```

**No `--broadcast` flag.** `forge script` without `--broadcast` simulates every step
(including the `vm.startBroadcast`/`vm.stopBroadcast` block) against a local EVM
forked from live Monad mainnet state, and reports whether every step — preflight
checks, all six deployments, ownership transfer calls, the identity-verification
gate, and the `deployments/mainnet.json` write — would succeed, without sending a
single real transaction. This is the only mode this session ran.

Then, independently, check the masked bytecode comparison (also read-only):

```bash
node scripts/verify-deployment-bytecode.mjs
```

## Phase 9 mode: actual broadcast (explicitly out of scope for this session)

```bash
forge script script/Deploy.s.sol --rpc-url "$MONAD_RPC_URL" --broadcast --verify
```

This sends real transactions, spends real MON, and deploys contracts that cannot be
undeployed. **This requires:**

1. Explicit user approval, given after reviewing the Phase 8 dry-run's output.
2. `DEPLOYER_PRIVATE_KEY` funded with enough native MON to cover deployment gas.
3. `ETHERSCAN_API_KEY` set (for `--verify`'s source verification).

This document does not itself authorize that step — it only describes how to run it
once authorized. No Phase 8 work in this repository invokes `--broadcast`.

## After Phase 9 (not yet reached)

- `PROTOCOL_OWNER_ADDRESS` must independently call `acceptOwnership()` on
  `PancakeV2Adapter`, `UniswapV3Adapter`, `SweepExecutor`, and `DemoDistributor` from
  its own key — `Deploy.s.sol` only calls `transferOwnership`, the first half of
  `Ownable2Step`'s two-step handoff; it cannot and does not complete the second half
  on the new owner's behalf.
- `DEPLOYER_PRIVATE_KEY` must be removed from any Railway runtime service (PRD
  §19.19 step 30) — it should never have been placed in one to begin with per
  `.env.example`'s own comment.
- Demo liquidity provisioning, buy/sell smoke tests, and `claimDemoBundle()` testing
  from fresh EOAs are Phase 10, not Phase 8/9.
