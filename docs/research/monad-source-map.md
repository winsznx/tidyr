# Monad Protocol Source Map

Primary-source findings on Monad-specific behavior that TIDYR's contracts, execution
scheduler, and UI must model correctly. Every claim below is sourced from Monad's own
documentation/blog or a directly-observed on-chain call — never from a blog aggregator or
AI-summarized secondary source without independent confirmation.

## 1. Chain identity

- Chain ID `143` (`0x8f`), native currency `MON`.
- Confirmed live via `eth_chainId` against `https://rpc.monad.xyz` → `0x8f`.
- Source: [Monad Network Information — Mainnet](https://docs.monad.xyz/developer-essentials/network-information).

## 2. Consensus / block commitment states (MonadBFT)

Monad blocks pass through four states, not the two (`pending`/`confirmed`) most EVM
tooling assumes:

1. **Proposed** — leader has proposed the block; not yet voted on. A node may
   speculatively execute it.
2. **Voted** — a Quorum Certificate (QC) exists; supermajority has voted affirmatively.
   Can be "speculatively finalized."
3. **Finalized** — a QC-squared exists (a QC over a block that itself contains a QC).
   This is the irreversible-completion state.
4. **Verified** — the finalized block's Merkle root has been independently verified.

~800ms typical finality (two consensus rounds after proposal).

**Implementation consequence (binds PRD §19.6):** TIDYR's execution monitor and status
report must only mark a wallet "complete" after the *Finalized* event/receipt, never after
first-seen/`latest`. Show only the phases the active RPC provider actually exposes; never
relabel `latest` as `finalized`.

Source: [Block States — Monad Developer Documentation](https://docs.monad.xyz/monad-arch/consensus/block-states).

## 3. Reserve-balance / gas-limit charging

Monad charges the sender based on the **submitted gas limit**, not gas used, at the time
the transaction enters consensus scheduling — this is why the PRD (§19.5) forbids
oversized multipliers like `estimate * 2`. Practical policy: `estimate + estimate/10`
(10% buffer) plus documented per-action-type sanity ceilings, recalibrated from real
deployed-contract gas measurements before production release.

## 4. EIP-7702 delegation and the 10 MON reserve

This is the most nuanced Monad-specific rule in the PRD and deserves a precise
statement, corrected from the PRD's flattened description:

- The 10 MON reserve-balance rule applies specifically to **EIP-7702-delegated EOAs**.
  A transaction that would reduce a delegated EOA's balance below 10 MON
  **unconditionally reverts**.
- **Undelegated** EOAs get an explicit carve-out: the reserve-balance algorithm allows
  the *first* transaction (per sender) within the last *k* blocks to spend the balance
  below 10 MON. This is why the PRD's own §19.8 sequencing advice (finish everything
  else, wait 3 blocks, submit the native-MON-emptying transaction last) is the safe
  general strategy for undelegated wallets — but it is not an absolute protocol
  requirement for undelegated EOAs the way it is for delegated ones.
- Monad does not require 7702 delegation for any workflow; TIDYR must never auto-delegate
  a wallet, and must detect delegation by reading the account's code (a 7702-delegated EOA
  has non-empty code at its own address per EIP-7702 semantics) before planning a native
  MON sweep.

**Implementation consequence:** `packages/execution` must branch its native-MON safe-sweep
calculation on delegation status:
- delegated → hard-block any plan that would leave balance < 10 MON; offer an explicit
  undelegation transaction first.
- undelegated → apply the reserve-plus-gas-buffer heuristic from PRD §19.8, but do not
  present it as a protocol-enforced floor the way the delegated case is.

Source: [EIP-7702 on Monad — Monad Developer Documentation](https://docs.monad.xyz/developer-essentials/eip-7702).

## 5. Parallel execution

Independent (non-conflicting) EOA transactions can be included and confirmed within the
same block/consensus round, which is the basis for TIDYR's headline "concurrent multi-wallet
broadcast" feature. This is an architectural property of Monad's parallel execution engine,
consistent with the PRD's product framing in Section 1.

Source: [How Monad Works — Monad Blog](https://blog.monad.xyz/blog/how-monad-works); [MonadBFT — Monad Developer Documentation](https://monad-docs-jlnlgs18a-monad-xyz.vercel.app/monad-arch/consensus/monad-bft).

## 6. Wallet signing model — explicit correction of an unstated PRD assumption

The PRD's transaction-batching language (Section 10, Section 12) must be read strictly
through the PRD's own §19.2 correction: ordinary browser/injected wallets sign and
broadcast a transaction together via `eth_sendTransaction` — they do not hand back a raw
signed transaction for TIDYR to hold and later broadcast. Consequences enforced in
`packages/execution`:

- EIP-712 typed-data signatures (Permit2 witness, batch permits) **can** be collected
  independently of broadcast — this is standard `eth_signTypedData_v4` behavior and is
  used for the Permit2 flow.
- Raw pre-signed transaction collection ("collect all signatures, then broadcast
  everything at once") is **only** claimed for wallets that report `atomicBatch` support
  via `wallet_getCapabilities` (EIP-5792). For all other wallets, each transaction is
  requested, signed, and broadcast by the wallet as one user-facing action, in nonce
  order, and TIDYR's "concurrent broadcast" claim applies at the level of *initiating*
  each wallet's first transaction near-simultaneously — not at the level of atomically
  co-signing every wallet's calldata ahead of time.
- TIDYR must never claim atomic batching for a wallet that has not reported the
  capability through `wallet_getCapabilities`.

This does not reduce the product's scope — the multi-wallet concurrent-broadcast feature
described in Section 1 remains fully implementable; it is implemented as
near-simultaneous initiation of each wallet's independent transaction queue, not as a
single co-signed atomic bundle across wallets (which no wallet standard supports across
distinct EOAs owned by different signers/devices).

## Sources consulted (primary only)

- [docs.monad.xyz/developer-essentials/network-information](https://docs.monad.xyz/developer-essentials/network-information)
- [docs.monad.xyz/developer-essentials/eip-7702](https://docs.monad.xyz/developer-essentials/eip-7702)
- [docs.monad.xyz/monad-arch/consensus/block-states](https://docs.monad.xyz/monad-arch/consensus/block-states)
- [blog.monad.xyz/blog/how-monad-works](https://blog.monad.xyz/blog/how-monad-works)
- Live `eth_chainId` / `eth_getCode` calls against `https://rpc.monad.xyz`
- [developers.uniswap.org/docs/protocols/v3/deployments/v3-monad-deployments](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-monad-deployments)
- `@pancakeswap/v2-sdk`, `@pancakeswap/universal-router-sdk`, `@pancakeswap/chains` npm packages (official PancakeSwap-published source, inspected directly, not via secondary summary)
- [circle.com/multi-chain-usdc/monad](https://www.circle.com/multi-chain-usdc/monad)
- [0x.org/post/powering-the-monad-ecosystem-with-swap-api](https://0x.org/post/powering-the-monad-ecosystem-with-swap-api)
- [docs.moralis.com/changelog/monad-evm-live](https://docs.moralis.com/changelog/monad-evm-live)
