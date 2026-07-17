# TIDYR — Production PRD
## Monad Multi-Wallet Cleanup Terminal
**Product:** TIDYR · `tidyr.xyz`  
**Chain:** Monad Mainnet · Chain ID `143`  
**Hackathon:** Spark by BuildAnything · Closes Jul 19 2026  
**Scope:** Production mainnet deployment, 5 demo tokens, real liquidity, real swaps  
**Hosting:** Railway — web, API, indexer, Postgres, and Redis

---

## Table of Contents

1. [Product Definition](#1-product-definition)
2. [What Gets Deployed on Mainnet](#2-what-gets-deployed-on-mainnet)
3. [Demo Token Strategy](#3-demo-token-strategy)
4. [Smart Contract Architecture](#4-smart-contract-architecture)
5. [Contract Security & Audit Patterns](#5-contract-security--audit-patterns)
6. [Swap Routing — How Tokens Become MON or USDC](#6-swap-routing--how-tokens-become-mon-or-usdc)
7. [Asset Discovery Pipeline](#7-asset-discovery-pipeline)
8. [Token Classification System](#8-token-classification-system)
9. [Action System](#9-action-system)
10. [Approval Architecture](#10-approval-architecture)
11. [Human-Readable Transaction Review](#11-human-readable-transaction-review)
12. [Multi-Wallet Execution Scheduler](#12-multi-wallet-execution-scheduler)
13. [Frontend — Build Plan](#13-frontend--build-plan)
14. [Backend API — Build Plan](#14-backend-api--build-plan)
15. [Infrastructure](#15-infrastructure)
16. [Status Report](#16-status-report)
17. [Deployment Sequence](#17-deployment-sequence)
18. [Non-Functional Requirements](#18-non-functional-requirements)
19. [Mandatory Implementation Addendum](#19-mandatory-implementation-addendum)

---

## 1. Product Definition

### Core Promise
Clean every Monad wallet without blindly signing anything.

### What TIDYR Is
A multi-wallet cleanup workspace for Monad. You connect multiple EOAs, the app scans all of them, you assign cleanup actions to every token across every wallet, review a human-readable explanation of exactly what will happen, sign once per wallet, and TIDYR broadcasts all wallet transactions simultaneously. Monad processes independent wallet transactions in parallel. You get a final report showing exactly what happened — reconstructed from on-chain events, not optimistic assumptions.

### The Personal Problem It Solves
You build on Monad. You have a main wallet, a dev wallet, two hackathon wallets, and a throwaway wallet from testing a bridge. Each one has dust tokens, old approvals, and small MON balances. Cleaning them today means switching wallets 15 times, trusting hex calldata in popup windows, selling tokens one at a time, and still not knowing if all approvals got revoked. TIDYR replaces that workflow with one workspace, one review session, and one execution.

### Why Monad Specifically
The multi-wallet concurrent broadcast is not a gimmick. Monad's parallel execution engine processes non-conflicting EOA transactions in the same block. Three independent wallet sweep transactions broadcast simultaneously can confirm in the same ~400ms block. That is not possible on Ethereum (serial per block) and feels meaningfully different from other chains. This is where Monad's architecture becomes the product feature, not just the deployment target.

---

## 2. What Gets Deployed on Mainnet

Everything below is a real mainnet deployment. No testnet fallback. No mock data.

| Contract | Purpose | Upgradeable |
|---|---|---|
| `SweepExecutor` | Core execution contract — pulls tokens, runs swaps, sends output | No |
| `PancakeV2Adapter` | Routes swaps through PancakeSwap V2 pairs | No |
| `UniswapV3Adapter` | Routes swaps through Uniswap V3 Universal Router | No |
| `DemoToken` × 5 | Five ERC-20 tokens for demonstration | No |
| `DemoDistributor` | Lets judges claim one of each demo token via `claimDemoBundle()` | No |

All contracts source-verified on MonadScan. All ABIs committed to the repository. All deployment addresses documented in `README.md` and a `deployments/mainnet.json` file.

---

## 3. Demo Token Strategy

### The Setup
Deploy 5 ERC-20 tokens. Add $1 worth of WMON liquidity to a PancakeSwap V2 pair for each. The goal: demonstrate a real sweep where all 5 tokens get converted to MON (or USDC) in a single plan, across multiple wallets if desired.

### Why $1 Per Token Is Enough
The demo only needs to prove that a live sell quote exists and that the swap executes. With $1 in a V2 pair, a small sell of the demo token will route successfully through PancakeSwap. The slippage will be high but the execution will be real. Judges watching MonadScan will see the actual swap transaction confirm.

### Token Definitions

| Token | Symbol | Behavior | Liquidity | Sweep Action |
|---|---|---|---|---|
| Token 1 | `DUST1` | Standard ERC-20 | ~$1 WMON/DUST1 V2 pair | Sell → MON |
| Token 2 | `DUST2` | Standard ERC-20 | ~$1 WMON/DUST2 V2 pair | Sell → MON |
| Token 3 | `DUST3` | Standard ERC-20 | ~$1 WMON/DUST3 V2 pair | Sell → USDC |
| Token 4 | `DUST4` | ERC-20 + `burn(uint256)` | ~$1 WMON/DUST4 V2 pair | Sell → MON or Burn |
| Token 5 | `DUST5` | Standard ERC-20, no pool | None | Consolidate or Discard |

Token 5 has no pool intentionally — it demonstrates the TRANSFERABLE classification and shows that Sweep handles tokens with no liquidity honestly rather than failing silently.

### Liquidity Provision
```
For each DUST1–DUST4:
  1. Deploy token → mint 1,000,000 DUST to deployer
  2. Wrap MON to WMON (equivalent of ~$1 at current price)
  3. Call PancakeRouter.addLiquidity(DUST, WMON, 10000, wmonAmount, 0, 0, deployer, deadline)
  4. Record pair address in deployments/mainnet.json

Example at MON = $0.50:
  WMON amount = 2 WMON (~$1)
  DUST amount = 10,000 DUST
  Pair is now live and quotable
```

### DemoDistributor
Deployed separately. Holds 1,000 of each demo token. Anyone calls `claimDemoBundle()` and receives 200 DUST1, 200 DUST2, 200 DUST3, 200 DUST4, 200 DUST5. One claim per address (enforced by mapping). Judges use this to get real balances in their wallets before running Sweep.

```solidity
contract DemoDistributor {
    mapping(address => bool) public claimed;
    IERC20[5] public tokens;

    function claimDemoBundle() external {
        require(!claimed[msg.sender], "already claimed");
        claimed[msg.sender] = true;
        for (uint i = 0; i < 5; i++) {
            tokens[i].transfer(msg.sender, 200 * 10**18);
        }
    }
}
```

---

## 4. Smart Contract Architecture

### SweepExecutor

The core contract. It receives a signed plan, pulls tokens from the user via Permit2, executes swaps through registered adapters, and sends the output to a designated recipient. It never holds user funds after a transaction completes.

#### Data Structures

```solidity
struct SweepPlan {
    address   owner;          // wallet being swept
    address   recipient;      // where output goes
    address   outputToken;    // MON address or USDC address
    uint256   deadline;       // unix timestamp — revert if expired
    uint256   nonce;          // replay protection (per-owner counter)
    bytes32   manifestHash;   // keccak256 of canonical plan JSON
    SwapAction[]     swaps;
    TransferAction[] transfers;
    DiscardAction[]  discards;
    RevokeAction[]   revocations;
}

struct SwapAction {
    address tokenIn;
    uint256 amountIn;
    address adapter;       // must be in allowedAdapters mapping
    uint256 minAmountOut;  // enforced — revert if not met (unless allowFailure)
    bytes   routeData;     // adapter-specific encoding
    bool    allowFailure;  // true only if user explicitly opted in
}

struct TransferAction {
    address token;
    uint256 amount;
    address to;           // recipient (primary wallet for consolidation)
}

struct DiscardAction {
    address token;
    uint256 amount;
    // destination is hardcoded: 0x000000000000000000000000000000000000dEaD
}

struct RevokeAction {
    address token;
    address spender;
    // sets allowance to 0 via token.approve(spender, 0)
}
```

#### Storage

```solidity
mapping(address => bool)    public allowedAdapters;
mapping(address => uint256) public nonces;          // per owner
address public immutable    PERMIT2;
address public immutable    WMON;
address public immutable    DEAD = 0x000000000000000000000000000000000000dEaD;
uint256 public constant     MAX_ACTIONS = 50;
```

#### Core Function Signature

```solidity
function executeSweep(
    SweepPlan calldata plan,
    bytes calldata permit2Sig   // EIP-712 Permit2 batch permit signature
) external nonReentrant
```

#### Execution Flow

```
1.  Validate plan.deadline >= block.timestamp                    → revert if expired
2.  Validate plan.owner == msg.sender OR signed by plan.owner    → revert if unauthorized
3.  Validate nonces[plan.owner] == plan.nonce                   → revert if replayed
4.  Increment nonces[plan.owner]                                 → prevent replay
5.  Validate plan.swaps.length + plan.transfers.length
      + plan.discards.length + plan.revocations.length <= 50    → revert if oversized
6.  Validate keccak256(abi.encode(plan)) == plan.manifestHash   → revert if plan tampered
7.  Pull tokens via Permit2.permitTransferFrom(batchPermit, sig) → exact amounts only
8.  For each SwapAction:
      a. Validate adapter in allowedAdapters                     → revert if not registered
      b. Record balanceBefore = outputToken.balanceOf(address(this))
      c. Approve adapter for amountIn (reset after)
      d. Call adapter.swap(action.routeData)
      e. Record balanceAfter
      f. actualOut = balanceAfter - balanceBefore
      g. If actualOut < action.minAmountOut:
           if allowFailure → emit SwapFailed, continue
           else            → revert
      h. Reset adapter approval to 0
9.  For each TransferAction:
      IERC20(action.token).safeTransfer(action.to, action.amount)
10. For each DiscardAction:
      IERC20(action.token).safeTransfer(DEAD, action.amount)
11. For each RevokeAction:
      IERC20(action.token).approve(action.spender, 0)
12. Return all remaining input token balances to plan.owner
      (any amount not consumed by actions returns to owner)
13. Transfer total accumulated outputToken to plan.recipient
14. Emit SweepCompleted(manifestHash, owner, recipient, outputToken, totalOut, successCount, failCount)
```

#### Events

```solidity
event SweepCompleted(
    bytes32 indexed manifestHash,
    address indexed owner,
    address indexed recipient,
    address  outputToken,
    uint256  outputAmount,
    uint256  successfulActions,
    uint256  failedActions
);

event SwapFailed(
    bytes32 indexed manifestHash,
    address  tokenIn,
    uint256  amountIn,
    uint256  actualOut,
    uint256  minRequired
);

event AdapterRegistered(address indexed adapter);
event AdapterRemoved(address indexed adapter);
```

### PancakeV2Adapter

Routes a token → WMON → outputToken path through PancakeSwap V2.

```solidity
struct V2RouteData {
    address[] path;      // e.g. [DUST1, WMON] or [DUST1, WMON, USDC]
    uint256   deadline;
}

function swap(bytes calldata routeData) external returns (uint256 amountOut) {
    V2RouteData memory r = abi.decode(routeData, (V2RouteData));
    // transfer tokenIn from SweepExecutor (already approved)
    // call PancakeRouter.swapExactTokensForTokens(...)
    // return actual amountOut
}
```

### UniswapV3Adapter

Wraps Uniswap Universal Router for V3 pool paths.

```solidity
struct V3RouteData {
    bytes    path;       // encoded V3 path: token0 | fee | token1 | fee | token2
    uint256  deadline;
    uint256  amountIn;
}
```

---

## 5. Contract Security & Audit Patterns

This is a production mainnet deployment handling real user funds. Every security pattern below is mandatory — not optional.

### 5.1 Reentrancy Guard

Use OpenZeppelin `ReentrancyGuard`. Apply `nonReentrant` to `executeSweep`. Rationale: the contract calls external adapters mid-execution. A malicious adapter could call back into `executeSweep` before state is finalized.

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SweepExecutor is ReentrancyGuard {
    function executeSweep(...) external nonReentrant { ... }
}
```

Additional CEI (Checks-Effects-Interactions) enforcement: all state writes (nonce increment, balance recording) happen before external calls to adapters.

### 5.2 No Arbitrary External Calls

The contract never accepts a user-provided `target` address for a raw call. Every external call goes through a registered adapter in the `allowedAdapters` mapping. Adapter registration is owner-only with an event. Any call to an address not in `allowedAdapters` reverts immediately.

```solidity
modifier onlyAllowedAdapter(address adapter) {
    require(allowedAdapters[adapter], "adapter not registered");
    _;
}
```

### 5.3 No delegatecall

The word `delegatecall` does not appear anywhere in SweepExecutor or its adapters. Using `delegatecall` to an adapter would give the adapter full control over SweepExecutor's storage. This is never used.

### 5.4 Balance Delta Accounting

Never trust return values from external swap calls. Always use balance deltas:

```solidity
uint256 before = IERC20(outputToken).balanceOf(address(this));
adapter.swap(action.routeData);                                   // external call
uint256 actual = IERC20(outputToken).balanceOf(address(this)) - before;
require(actual >= action.minAmountOut || action.allowFailure, "slippage");
```

This defends against adapters that lie about their return value and against fee-on-transfer tokens that reduce the received amount.

### 5.5 Approval Reset After Each Swap

Before calling an adapter, the contract grants it exactly `action.amountIn` approval:

```solidity
IERC20(action.tokenIn).safeApprove(action.adapter, action.amountIn);
adapter.swap(action.routeData);
IERC20(action.tokenIn).safeApprove(action.adapter, 0); // always reset
```

Even if the swap reverts or partially executes, the approval resets. A registered-but-compromised adapter cannot pull more than the single-action amount.

### 5.6 Deadline Enforcement

Every plan carries a `uint256 deadline`. The contract rejects plans where `block.timestamp > deadline`. Deadlines should be set to `now + 10 minutes` in the frontend. This prevents signed plans from being replayed hours later.

```solidity
require(block.timestamp <= plan.deadline, "plan expired");
```

### 5.7 Nonce / Replay Protection

Per-owner nonce counter. Invalidated immediately on execution (before external calls). A plan with a reused nonce always reverts.

```solidity
require(nonces[plan.owner] == plan.nonce, "invalid nonce");
nonces[plan.owner]++;  // increment before any external interaction
```

### 5.8 Manifest Hash Binding

The plan struct is hashed and the hash is stored in `plan.manifestHash`. The contract recomputes the hash and verifies it matches. This means the calldata the user's wallet actually signs is the same calldata the contract executes — a discrepancy reverts.

```solidity
bytes32 computed = keccak256(abi.encode(
    plan.owner, plan.recipient, plan.outputToken,
    plan.deadline, plan.nonce,
    plan.swaps, plan.transfers, plan.discards, plan.revocations
));
require(computed == plan.manifestHash, "manifest tampered");
```

### 5.9 Exact Amount Limits via Permit2

Permit2 batch permits specify each token and exact maximum amount. The contract cannot pull more than the user signed for, even if an adapter tries. There are no unlimited approvals.

### 5.10 Maximum Action Count

```solidity
uint256 total = plan.swaps.length + plan.transfers.length
              + plan.discards.length + plan.revocations.length;
require(total > 0 && total <= MAX_ACTIONS, "invalid action count");
```

This prevents gas griefing via unbounded arrays and keeps execution within predictable gas bounds.

### 5.11 No Retained User Funds

After execution completes, the contract holds zero user tokens. Any token balance remaining (unconsumed inputs, partial swap remainders) is returned to `plan.owner` in a final sweep loop before the function returns.

```solidity
// After all actions complete
for (uint i = 0; i < plan.swaps.length; i++) {
    uint256 remaining = IERC20(plan.swaps[i].tokenIn).balanceOf(address(this));
    if (remaining > 0) {
        IERC20(plan.swaps[i].tokenIn).safeTransfer(plan.owner, remaining);
    }
}
```

### 5.12 Integer Overflow Protection

Use Solidity 0.8.x. All arithmetic is checked by default. No `unchecked` blocks unless explicitly profiling a gas-critical loop with proof that overflow is impossible.

### 5.13 safeTransfer / safeApprove

Use OpenZeppelin `SafeERC20` for all token interactions. Some tokens return `false` instead of reverting on failure (USDT-style). `SafeERC20` wraps these and reverts on false returns.

```solidity
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;
```

### 5.14 Fee-on-Transfer Token Detection

Fee-on-transfer tokens reduce the received amount below `amountIn`. Since the contract uses balance deltas, it measures the actual received amount correctly. The `minAmountOut` check catches cases where the fee makes the swap unprofitable. However, fee-on-transfer tokens are explicitly not supported for inputs — the contract measures the actual pulled amount and if it is less than `action.amountIn`, the swap is treated as partially failed.

### 5.15 Owner-Only Adapter Management

Adapter registration and removal is restricted to the contract owner. The owner is set at deployment to the deployer address. There is no onlyOwner modifier on `executeSweep` — any user can call it with a valid signed plan.

```solidity
function registerAdapter(address adapter) external onlyOwner {
    require(adapter != address(0), "zero address");
    allowedAdapters[adapter] = true;
    emit AdapterRegistered(adapter);
}

function removeAdapter(address adapter) external onlyOwner {
    allowedAdapters[adapter] = false;
    emit AdapterRemoved(adapter);
}
```

### 5.16 Immutable Addresses

`PERMIT2`, `WMON`, and `DEAD` are `immutable` — set at construction and never changeable. This eliminates an entire class of admin-key attacks where an owner could point the contract at a malicious Permit2 replacement.

### 5.17 Input Validation Summary

| Input | Validation |
|---|---|
| `plan.owner` | Must equal `msg.sender` (no delegated execution in V1) |
| `plan.recipient` | Non-zero address |
| `plan.outputToken` | Non-zero address, must be MON or USDC (allowlisted output tokens) |
| `plan.deadline` | `>= block.timestamp` |
| `plan.nonce` | `== nonces[plan.owner]` |
| `plan.manifestHash` | `== keccak256(abi.encode(plan without manifestHash))` |
| Each `adapter` | `allowedAdapters[adapter] == true` |
| Each `minAmountOut` | `> 0` (zero minimum is disallowed — forces honest slippage) |
| Total action count | `<= MAX_ACTIONS (50)` |

### 5.18 What a Real Audit Would Catch (Pre-Audit Checklist)

Before mainnet, run through these manually or with Slither/Mythril:

- [ ] Every external call is preceded by all state updates (CEI)
- [ ] No storage variable is read after an external call that could modify it
- [ ] `safeApprove` reset is inside a `try/catch` if the token's approval behavior is non-standard
- [ ] The nonce increment cannot be skipped by any code path
- [ ] The manifestHash check cannot be bypassed by empty swaps array
- [ ] `allowedAdapters` cannot be manipulated by anyone except owner
- [ ] `claimDemoBundle` has the claimed-once guard and cannot drain more than intended
- [ ] All `uint256` arithmetic that could overflow is either impossible to overflow or uses checked math
- [ ] No `tx.origin` usage
- [ ] No timestamp dependency beyond deadline comparison (which is acceptable)
- [ ] Events are emitted for every state-changing operation

---

## 6. Swap Routing — How Tokens Become MON or USDC

### User Choice
At the action assignment step, the user picks one output token for the entire sweep:
- **Sweep to MON** — all sold tokens convert to native MON
- **Sweep to USDC** — all sold tokens convert to USDC

Both options are supported. The `plan.outputToken` field encodes this choice.

### Routing for the 5 Demo Tokens

All 5 demo tokens use PancakeSwap V2 because that is where the liquidity pools are deployed. The V2 path is simple and auditable.

```
DUST1 → WMON (direct pair)     → unwrap to MON
DUST2 → WMON (direct pair)     → unwrap to MON
DUST3 → WMON → USDC            → hold as USDC
DUST4 → WMON (direct pair)     → unwrap to MON
DUST5 → no pool                → consolidate or discard (not sold)
```

### WMON Unwrapping
Monad native MON is wrapped as WMON for DEX compatibility. After all swaps complete, if the output token is native MON, the executor calls `WMON.withdraw(totalWMON)` to unwrap, then sends native MON to the recipient.

```solidity
if (plan.outputToken == MON_NATIVE_SENTINEL) {
    uint256 wmonBal = IWMON(WMON).balanceOf(address(this));
    IWMON(WMON).withdraw(wmonBal);
    (bool ok,) = plan.recipient.call{value: wmonBal}("");
    require(ok, "MON transfer failed");
}
```

The contract must be `receive() external payable {}` to accept MON from WMON unwrap.

### Quote Flow (Frontend)

```
Portfolio screen    →  indicative price  (0x price endpoint or PancakeV2 getAmountsOut)
User presses Review →  firm quote        (0x quote endpoint or live getAmountsOut)
Quote age > 45s     →  auto-refresh      (re-request firm quote, re-simulate)
User presses Sign   →  verify freshness  (reject if quote > 60s old)
```

### Routing Decision Per Token

```typescript
async function getRoute(tokenIn: Address, amountIn: bigint, outputToken: OutputToken) {
  // 1. Check if PancakeV2 pair exists and has liquidity
  const v2Quote = await pancakeV2Adapter.getAmountsOut(tokenIn, amountIn, outputToken);
  
  // 2. Check 0x if V2 has no quote or outputToken needs multi-hop
  const zeroXQuote = await zeroXService.getIndicativeQuote(tokenIn, amountIn, outputToken);
  
  // 3. Return best quote with adapter reference
  if (!v2Quote && !zeroXQuote) return null; // TRANSFERABLE — no route
  if (!v2Quote) return { adapter: 'zeroX', ...zeroXQuote };
  if (!zeroXQuote) return { adapter: 'pancakeV2', ...v2Quote };
  return v2Quote.amountOut >= zeroXQuote.amountOut
    ? { adapter: 'pancakeV2', ...v2Quote }
    : { adapter: 'zeroX', ...zeroXQuote };
}
```

---

## 7. Asset Discovery Pipeline

### Step-by-Step

```
Moralis ERC-20 balance API (chain ID 143)
     ↓
Candidate token address list
     ↓
Multicall3 batch — per token, per wallet:
  • balanceOf(wallet)
  • extcodesize(token) > 0 (contract exists)
  • decimals()
  • symbol() — 3s timeout, 32 char cap
  • name()   — 3s timeout, 32 char cap
     ↓
Verified token records
     ↓
Allowance scan — per token, per known spender:
  • Permit2 address
  • PancakeSwap V2 Router
  • Uniswap V3 Universal Router
  • Any spender with historical approval events (from Moralis)
     ↓
Quote attempt (indicative)
     ↓
Transfer simulation (Tenderly dry-run)
     ↓
Classification → TRADABLE / TRANSFERABLE / BURNABLE / UNKNOWN
```

### Moralis API Call

```typescript
// Chain ID 143 = Monad Mainnet
GET https://deep-index.moralis.io/api/v2.2/{walletAddress}/erc20
  ?chain=0x8f      // 0x8f = 143 decimal
  &limit=100
Headers: X-API-Key: {MORALIS_KEY}
```

### Multicall3 Batch Pattern

```typescript
// Never trust Moralis metadata directly — verify on-chain
const calls = tokens.flatMap(token => [
  { target: token, callData: encodeCall('balanceOf', [wallet]) },
  { target: token, callData: encodeCall('decimals', []) },
  { target: token, callData: encodeCall('symbol', []) },
  { target: token, callData: encodeCall('name', []) },
]);

// Max 100 calls per batch to stay within gas bounds
const chunks = chunk(calls, 100);
const results = await Promise.all(chunks.map(c => multicall3.aggregate3(c)));
```

### Malicious Token Defenses

| Defense | Implementation |
|---|---|
| Metadata timeout | `Promise.race([call, timeout(3000)])` — timeout → UNKNOWN |
| String truncation | All symbol/name values `.slice(0, 32)` before storing |
| Always show address | Contract address shown in UI regardless of symbol |
| Unicode normalization | `str.normalize('NFKC')` — collapses homoglyph attacks |
| Revert on metadata | If any required call reverts → classify UNKNOWN |
| Empty code check | `extcodesize == 0` → reject, not a contract |

---

## 8. Token Classification System

Four states. Exclusive. Honest about uncertainty.

### TRADABLE
- Criterion: fresh executable sell quote exists (PancakeV2 or 0x returns `amountOut > 0`)
- Transfer simulation also succeeds
- UI shows: balance, USD estimate, best route name, estimated output
- Available actions: Sell, Consolidate, Discard, Revoke

### TRANSFERABLE
- Criterion: no sell quote, but `transfer()` simulation succeeds
- UI shows: "No verified market — can consolidate or discard"
- Available actions: Consolidate, Discard, Revoke

### BURNABLE
- Criterion: contract ABI contains `burn(uint256)` AND simulation of `burn(balance)` succeeds
- UI shows: "Supply-reducing burn supported"
- Available actions: Burn, Consolidate, Discard, Revoke
- Note: DUST4 in the demo is burnable AND tradable — user chooses which action to apply

### UNKNOWN
- Criterion: any verification step failed — metadata reverts, timeout, simulation failure, empty code
- UI shows: "Manual review required — signing disabled"
- Available actions: None by default. Expert override requires typed confirmation and is logged.
- Hard rule: never convert UNKNOWN to a green state. Show the failure reason.

---

## 9. Action System

### SELL
Convert a TRADABLE token to MON or USDC.

Frontend encodes `SwapAction`:
```typescript
{
  tokenIn: tokenAddress,
  amountIn: userSelectedBalance,      // in wei
  adapter: pancakeV2AdapterAddress,   // or uniswapV3Adapter
  minAmountOut: firmQuote.amountOut * 99n / 100n,  // 1% slippage
  routeData: encodePancakeV2Route(path, deadline),
  allowFailure: false                 // default — revert on slippage
}
```

### CONSOLIDATE
Move token to designated primary wallet.

Frontend encodes `TransferAction`:
```typescript
{
  token: tokenAddress,
  amount: walletBalance,
  to: primaryWalletAddress
}
```

No swap involved. Uses standard `safeTransfer` inside executor.

### DISCARD
Send token to dead address.

Frontend encodes `DiscardAction`:
```typescript
{
  token: tokenAddress,
  amount: walletBalance
  // to is hardcoded in contract: 0x000...dEaD
}
```

UI shows non-dismissible warning: *"Discard is irreversible. This does not reduce total token supply."*

### BURN
Call token's `burn(uint256)` directly. Only shown when classification is BURNABLE.

This is NOT encoded in `SweepPlan` as a swap — it is a separate action type:
```solidity
struct BurnAction {
    address token;
    uint256 amount;
}
```
The executor calls `IBurnable(action.token).burn(action.amount)` directly. Re-simulation at review time confirms it still works before the card is shown.

### REVOKE
Set allowance to zero for a specific spender.

Frontend encodes `RevokeAction` per spender found during allowance scan:
```typescript
{
  token: tokenAddress,
  spender: spenderAddress  // e.g. Uniswap V3 Router address
}
```

UI shows:
```
Token:            DUST1 (0x1234...abcd)
Current spender:  PancakeSwap V2 Router (0xabcd...1234)
Current allowance: Unlimited
Action:           Set to 0
```

### TOP UP
Distribute MON from one source wallet to others.

This is a native transfer, not an ERC-20 action. The executor receives native MON and splits it:
```solidity
function topUp(address[] calldata recipients, uint256[] calldata amounts)
    external payable nonReentrant
{
    require(recipients.length == amounts.length);
    uint256 total = 0;
    for (uint i = 0; i < amounts.length; i++) total += amounts[i];
    require(msg.value >= total, "insufficient MON");
    for (uint i = 0; i < recipients.length; i++) {
        (bool ok,) = recipients[i].call{value: amounts[i]}("");
        require(ok, "transfer failed");
    }
    // return dust
    if (msg.value > total) {
        (bool ok,) = msg.sender.call{value: msg.value - total}("");
        require(ok);
    }
}
```

### MULTI-SEND
Send one token or MON to multiple recipients. Implemented as a simple loop inside the executor (or as a standalone `multiSend` function to keep gas accounting clean).

---

## 10. Approval Architecture

### First Use — Path A: EIP-5792 Atomic Batch

Detect wallet support:
```typescript
try {
  const caps = await wallet.request({ method: 'wallet_getCapabilities' });
  const hasAtomicBatch = caps?.[chainId]?.atomicBatch?.supported === true;
} catch { hasAtomicBatch = false; }
```

If supported, bundle all approvals + sweep into one `wallet_sendCalls`:
```typescript
await wallet.request({
  method: 'wallet_sendCalls',
  params: [{
    calls: [
      { to: DUST1, data: encodeApprove(PERMIT2, dust1Amount) },
      { to: DUST2, data: encodeApprove(PERMIT2, dust2Amount) },
      { to: SWEEP_EXECUTOR, data: encodeSweep(plan, sig) }
    ]
  }]
});
```

UI label: *"Your wallet supports atomic batching. All approvals and execution happen in one step."*

### First Use — Path B: Sequential Fallback

Standard flow:
```
Tx 1: DUST1.approve(Permit2, dust1Amount)     ← user signs
Tx 2: DUST2.approve(Permit2, dust2Amount)     ← user signs
Tx 3: SweepExecutor.executeSweep(plan, sig)   ← user signs
```

UI label: *"3 transactions required for this wallet."*

### Repeat Use — Permit2 Batch Permit

After tokens have approved Permit2 once, subsequent sweeps require only one EIP-712 signature:

```typescript
const batchPermit = {
  permitted: [
    { token: DUST1, amount: dust1Balance },
    { token: DUST2, amount: dust2Balance },
  ],
  spender: SWEEP_EXECUTOR,
  nonce: userNonce,
  deadline: Math.floor(Date.now() / 1000) + 600  // 10 minutes
};

const sig = await wallet.signTypedData(permit2Domain, permitTypes, batchPermit);
// One signature → submit executeSweep(plan, sig)
```

### EIP-7702 Policy

Monad-specific restriction: a 7702-delegated EOA cannot reduce its MON balance below 10 MON.

- Do not auto-delegate any wallet
- Do not require 7702
- Detect if a wallet is already 7702-delegated by checking its code
- Show warning if detected: *"This wallet uses EIP-7702 delegation. Monad requires a minimum 10 MON reserve. Your cleanup will preserve this balance."*
- Offer `undelegation` transaction before sweep if user wants to recover the reserve

---

## 11. Human-Readable Transaction Review

Three layers. All three must pass before the signature card is shown. Signing is blocked if any layer fails.

### Layer 1 — Intent Manifest

Before encoding, create a canonical typed object:

```typescript
interface SweepManifest {
  wallet:    string;   // checksummed address
  recipient: string;
  outputToken: 'MON' | 'USDC';
  deadline:  number;   // unix timestamp
  actions: Array<{
    type:        'SWAP' | 'CONSOLIDATE' | 'DISCARD' | 'BURN' | 'REVOKE';
    token:       string;
    tokenSymbol: string;
    amount:      string;  // human readable: "200.0"
    amountWei:   string;  // exact wei string
    // SWAP only:
    outputToken?:   string;
    minimumOutput?: string;
    route?:         string;
    slippageBps?:   number;
  }>;
}

// Hash it
const manifestJSON = JSON.stringify(canonicalize(manifest)); // RFC 8785 deterministic
const manifestHash = keccak256(toUtf8Bytes(manifestJSON));
```

`manifestHash` is embedded into `SweepPlan.manifestHash` before encoding the calldata.

### Layer 2 — Calldata Verification

After encoding the transaction, decode it again and verify every field. If mismatch → block signing, show diff.

```typescript
function verifyCalldata(encodedTx: Hex, manifest: SweepManifest): VerifyResult {
  const decoded = decodeFunctionData({ abi: sweepAbi, data: encodedTx });
  const plan = decoded.args[0];

  const checks = [
    { name: 'Target is SweepExecutor',      pass: decoded.to === SWEEP_EXECUTOR },
    { name: 'Owner matches wallet',          pass: plan.owner === manifest.wallet },
    { name: 'Recipient matches destination', pass: plan.recipient === manifest.recipient },
    { name: 'Deadline matches',              pass: plan.deadline === BigInt(manifest.deadline) },
    { name: 'No unlimited approvals',        pass: !containsUnlimitedApproval(encodedTx) },
    { name: 'No unexpected native value',    pass: decoded.value === 0n },
    { name: 'Manifest hash matches',         pass: plan.manifestHash === manifest.hash },
    // ...per-action amount and token checks
  ];

  return { allPassed: checks.every(c => c.pass), checks };
}
```

Any failed check produces: *"Calldata mismatch detected. Signing blocked. [Show diff]"*

### Layer 3 — Simulation (Tenderly)

```typescript
// Tenderly bundle simulation
const sim = await tenderly.simulateBundle({
  chainId: 143,
  transactions: [
    { from: wallet, to: SWEEP_EXECUTOR, data: encodedCalldata }
  ]
});

// Parse expected balance changes
const balanceChanges = sim.transactions[0].balance_changes;
const storageChanges = sim.transactions[0].storage_changes;
```

The signature card is populated from simulation output — not from quote assumptions.

### Signature Card (What the User Sees)

```
┌─────────────────────────────────────────────────────┐
│  WALLET  0xA17...92B  · Dev Wallet 1                │
├─────────────────────────────────────────────────────┤
│  LEAVING                                            │
│    200 DUST1   (0x1234...abcd)                      │
│    200 DUST2   (0x5678...efgh)                      │
│    200 DUST4   (0xabcd...1234)                      │
│                                                     │
│  RECEIVING                                          │
│    At least 0.431 MON → Main Wallet (0x91C...337)  │
│                                                     │
│  PERMISSIONS                                        │
│    Permit2 may pull exactly 200 DUST1               │
│    Permit2 may pull exactly 200 DUST2               │
│    Permit2 may pull exactly 200 DUST4               │
│    Permit expires in 9 min 32 sec                   │
│    No unlimited approvals                           │
│                                                     │
│  EXECUTION                                          │
│    3 swaps · 0 transfers · 2 revocations            │
│                                                     │
│  SIMULATION                                         │
│    ✓ All actions succeeded                          │
│    ✓ Recipient matched                              │
│    ✓ No unexpected asset movement                   │
│    ✓ Calldata verified against manifest             │
│                                                     │
│  [ Sign with 0xA17...92B ]                          │
└─────────────────────────────────────────────────────┘
```

---

## 12. Multi-Wallet Execution Scheduler

### Execution Graph

Each connected wallet with a SIGNER status gets one execution graph. Graphs run concurrently. Within each graph, transactions run in nonce order.

```
Wallet A (Dev Wallet 1):
  ├─ Tx A1: DUST1.approve(Permit2, ...)    nonce: 47
  ├─ Tx A2: DUST2.approve(Permit2, ...)    nonce: 48
  └─ Tx A3: executeSweep(planA, sigA)      nonce: 49

Wallet B (Airdrop Wallet):
  └─ Tx B1: executeSweep(planB, sigB)      nonce: 12   ← concurrent with A

Wallet C (Hackathon Wallet):
  ├─ Tx C1: DUST3.approve(Permit2, ...)    nonce: 3
  └─ Tx C2: executeSweep(planC, sigC)      nonce: 4    ← concurrent with A3, B1
```

### Scheduler Rules

1. Collect all signatures before broadcasting anything
2. Broadcast each wallet's first transaction simultaneously
3. For each wallet, after tx N confirms, broadcast tx N+1
4. Wallet failure is isolated — other wallets continue
5. Expired quotes refresh per-wallet only — other wallets unaffected
6. Confirmed wallets are never rerun — nonce would fail anyway

### State Machine Per Wallet

```
PENDING → SIGNING → SIGNED → BROADCASTING → CONFIRMING → CONFIRMED
                                                        ↘ FAILED → RETRY or ABANDONED
```

### Broadcast Implementation

```typescript
// All wallets broadcast their first tx simultaneously
await Promise.allSettled(
  wallets.map(w => provider(w.connector).sendTransaction(w.txQueue[0]))
);

// Then listen per wallet for confirmation and advance queue
wallets.forEach(wallet => {
  subscribeToConfirmation(wallet.pendingTxHash, async (receipt) => {
    wallet.confirmedTxs.push(receipt);
    const next = wallet.txQueue[wallet.confirmedTxs.length];
    if (next) await provider(wallet.connector).sendTransaction(next);
    else markWalletComplete(wallet);
  });
});
```

### WebSocket Confirmation

```typescript
const ws = new WebSocket(MONAD_WS_RPC);

ws.send(JSON.stringify({
  jsonrpc: '2.0',
  method: 'eth_subscribe',
  params: ['newHeads']   // or 'logs' filtered to SweepCompleted events
}));

ws.onmessage = (msg) => {
  const data = JSON.parse(msg.data);
  // check if any pending tx hashes appear in the new block
  // update UI confirmation state in real time
};
```

---

## 13. Frontend — Build Plan

**Framework:** Next.js 14 (App Router)  
**Wallet:** wagmi v2 + viem  
**Styling:** Tailwind CSS  
**State:** Zustand (client-only wallet/workspace state)

### Module Structure

```
app/
├── page.tsx                    ← landing: single CTA "Clean my wallets"
├── workspace/
│   ├── page.tsx                ← main workspace shell
│   ├── components/
│   │   ├── WalletConnector.tsx         ← add wallets, show status badges
│   │   ├── AssetScanner.tsx            ← triggers discovery, shows progress
│   │   ├── TokenList.tsx               ← classified token table per wallet
│   │   ├── ActionAssigner.tsx          ← select tokens, assign actions
│   │   ├── OutputTokenSelector.tsx     ← "Sweep to MON" or "Sweep to USDC"
│   │   ├── ReviewPanel.tsx             ← signature cards per wallet
│   │   ├── SignatureQueue.tsx          ← step-by-step signing flow
│   │   ├── ExecutionMonitor.tsx        ← real-time block confirmation view
│   │   └── StatusReport.tsx            ← final indexed report

lib/
├── moralis.ts             ← ERC-20 balance fetching
├── multicall.ts           ← batched on-chain reads
├── classification.ts      ← token classification logic
├── routing.ts             ← quote fetching, adapter selection
├── manifest.ts            ← plan creation and canonicalization
├── calldata.ts            ← encoding + verification (decode and re-verify)
├── simulation.ts          ← Tenderly API wrapper
├── scheduler.ts           ← multi-wallet execution graph
├── websocket.ts           ← WS subscription for confirmations
└── report.ts              ← SweepCompleted event indexing
```

### Key UI States

```
1. IDLE          → landing page, connect wallets
2. SCANNING      → discovery pipeline running, show progress per wallet
3. PLANNING      → token table visible, user assigns actions
4. REVIEWING     → manifest built, calldata verified, simulation running
5. SIGNING       → per-wallet signature queue active
6. EXECUTING     → live block confirmation monitor
7. COMPLETE      → status report dashboard
```

### Real-Time Confirmation View

During execution, show a live block feed:

```
Block #8,204,411                                    ~400ms ago

  Dev Wallet 1    DUST1 approve    ✓  confirmed   412ms
  Airdrop Wallet  sweep            ✓  confirmed   418ms
  Hackathon       DUST3 approve    ✓  confirmed   431ms

Block #8,204,412

  Dev Wallet 1    DUST2 approve    ✓  confirmed   396ms
  Hackathon       sweep            ✓  confirmed   408ms

Block #8,204,413

  Dev Wallet 1    sweep            ✓  confirmed   421ms

────────────────────────────────────────────────────────
  3 wallets · 6 transactions · all confirmed in 3 blocks
```

This view is driven by WebSocket, not polling. Each row appears when the transaction actually confirms.

---

## 14. Backend API — Build Plan

**Runtime:** Node.js / Bun  
**Framework:** Hono or Express  
**Deployed:** Vercel Functions or Railway

### Endpoints

```
GET  /api/tokens/:wallet
     → Moralis balance fetch + Multicall3 verification
     → Returns: verified token list with classification

GET  /api/quote?tokenIn=&amountIn=&outputToken=&wallet=
     → PancakeV2 getAmountsOut + 0x price endpoint
     → Returns: { adapter, amountOut, route, expires }

POST /api/quote/firm
     Body: { tokenIn, amountIn, outputToken, taker }
     → 0x quote endpoint for firm quote
     → Returns: { amountOut, routeData, expiresAt }

POST /api/simulate
     Body: { wallet, encodedTx }
     → Tenderly simulation API
     → Returns: { success, balanceChanges, error? }

GET  /api/report/:manifestHash
     → Query SweepCompleted events indexed from chain
     → Returns: full report with before/after balances

GET  /api/allowances/:wallet
     → Multicall3 allowance scan for known spenders
     → Returns: { token, spender, allowance }[]
```

### Caching Strategy

| Data | TTL | Reason |
|---|---|---|
| Token metadata | 5 minutes | Rarely changes |
| Moralis balances | 30 seconds | Changes after txs |
| Indicative quotes | 15 seconds | Prices move |
| Firm quotes | Track expiry from 0x response | ~60s RFQ limit |
| Allowances | 60 seconds | Changes after revoke |
| SweepCompleted events | Permanent | On-chain events are immutable |

---

## 15. Infrastructure

| Component | Provider | Notes |
|---|---|---|
| Monad RPC (HTTP) | Official Monad RPC | Primary read/write, chain ID 143 |
| Monad RPC (WebSocket) | Official Monad WS endpoint | Real-time tx confirmation subscriptions |
| ERC-20 indexer | Moralis | Chain ID `0x8f`, balance + transfer history |
| Simulation | Tenderly | Bundle simulation, trace decoding, balance diff |
| Swap aggregator | 0x Swap API | Chain ID 143, Swap + Gasless API |
| Direct AMM | PancakeSwap V2 | Direct pair contract reads and router calls |
| Block explorer links | MonadScan | Tx hash links in status report |
| Frontend hosting | Vercel | Next.js deployment |
| Backend hosting | Vercel Functions | Serverless API routes |
| Contract verification | MonadScan | Source + ABI verified post-deploy |

### Environment Variables

```bash
# RPC
MONAD_RPC_URL=https://rpc.monad.xyz
MONAD_WS_URL=wss://rpc.monad.xyz/ws

# Indexer
MORALIS_API_KEY=

# Simulation
TENDERLY_ACCOUNT=
TENDERLY_PROJECT=
TENDERLY_ACCESS_KEY=

# Aggregator
ZEROX_API_KEY=

# Contracts (populated after deployment)
SWEEP_EXECUTOR_ADDRESS=
PANCAKE_V2_ADAPTER_ADDRESS=
UNIV3_ADAPTER_ADDRESS=
PERMIT2_ADDRESS=
PANCAKE_V2_ROUTER=
WMON_ADDRESS=
USDC_ADDRESS=

# Demo tokens
DUST1_ADDRESS=
DUST2_ADDRESS=
DUST3_ADDRESS=
DUST4_ADDRESS=
DUST5_ADDRESS=
DEMO_DISTRIBUTOR_ADDRESS=
```

---

## 16. Status Report

### Source of Truth
All report data is derived from on-chain events. Zero hardcoded success states. Zero optimistic state assumptions.

The `SweepCompleted` event provides `manifestHash`, `outputAmount`, `successfulActions`, `failedActions`. The frontend cross-references this against the original manifest to reconstruct per-action detail.

### Report Structure

```
CLEANUP COMPLETE
────────────────────────────────────────────────

Wallets processed:     3
Assets reviewed:       12
Time to completion:    1.4 seconds

CONVERTED
  DUST1  200 tokens  →  0.18 MON   via PancakeSwap V2  [tx hash]
  DUST2  200 tokens  →  0.21 MON   via PancakeSwap V2  [tx hash]
  DUST4  200 tokens  →  0.14 MON   via PancakeSwap V2  [tx hash]
  ─────────────────────────────────
  Total: 0.53 MON received by Main Wallet

CONSOLIDATED
  DUST5  200 tokens  →  Main Wallet (0x91C...337)       [tx hash]

DISCARDED
  [none]

APPROVALS REVOKED
  DUST1  Uniswap V3 Router — was Unlimited              [tx hash]
  DUST2  Old DEX Router    — was Unlimited              [tx hash]

SKIPPED
  Token #6  0x9999...  — UNKNOWN classification, no action taken

EXECUTION
  3 successful wallet batches
  0 retried transactions
  0 unresolved failures

────────────────────────────────────────────────
Every row links to: tx hash · wallet · block · before/after balance
```

### Per-Row Detail (Expandable)

| Field | Value |
|---|---|
| Transaction hash | `0x...` (MonadScan link) |
| Wallet | Address + label |
| Block | `#8,204,413` |
| Token | Address + verified symbol |
| Balance before | `200.0 DUST1` |
| Balance after | `0.0 DUST1` |
| Quoted output | `0.18 MON` (from firm quote) |
| Simulated output | `0.18 MON` (Tenderly) |
| Actual output | `0.181 MON` (from SweepCompleted event) |
| Finality | `Confirmed · Block 8,204,413 · 412ms` |

---

## 17. Deployment Sequence

Deploy in this exact order. Each step depends on the previous.

```
Step 1:  Deploy WMON (if not already on chain — use canonical address if exists)
Step 2:  Deploy USDC (if not already — use canonical address if exists)
Step 3:  Verify Permit2 canonical address on chain (do not redeploy)
Step 4:  Deploy PancakeV2Adapter(pancakeRouterAddress, wmonAddress)
Step 5:  Deploy UniswapV3Adapter(universalRouterAddress)
Step 6:  Deploy SweepExecutor(permit2, wmon, owner)
Step 7:  Call SweepExecutor.registerAdapter(pancakeV2AdapterAddress)
Step 8:  Call SweepExecutor.registerAdapter(uniswapV3AdapterAddress)
Step 9:  Deploy DemoToken x5 (DUST1–DUST5, 1,000,000 supply each, 18 decimals)
Step 10: Wrap MON → WMON (~$1 worth per token = ~2 WMON per token at $0.50/MON)
Step 11: Approve PancakeRouter for WMON and each DUST token
Step 12: PancakeRouter.addLiquidity(DUST1, WMON, 10000e18, 2e18, ...) × 4 tokens
Step 13: Record all 4 pair addresses
Step 14: Deploy DemoDistributor(dust1, dust2, dust3, dust4, dust5)
Step 15: Transfer 1000 of each DUST to DemoDistributor
Step 16: Source-verify all contracts on MonadScan
Step 17: Write deployments/mainnet.json with all addresses
Step 18: Update .env.local with all deployed addresses
Step 19: Test claimDemoBundle() from a fresh wallet
Step 20: Run a full sweep dry-run on the demo bundle (testWallet → simulate only)
Step 21: Run a live sweep on the demo bundle — confirm on MonadScan
Step 22: Document TX hash of first successful real sweep in README
```

---

## 18. Non-Functional Requirements

| Requirement | Value | Enforcement |
|---|---|---|
| Quote max age (indicative) | 15 seconds | UI countdown, auto-refresh |
| Quote max age (firm) | 45 seconds | Re-request before signing |
| Quote hard reject age | 60 seconds | Never sign a stale firm quote |
| Token metadata call timeout | 3 seconds | `Promise.race` with timeout |
| String max length | 32 characters | Applied before storage and display |
| Max actions per plan | 50 | Frontend validation + contract `require` |
| Multicall batch size | 100 calls | Chunked in frontend lib |
| WebSocket reconnect | Exponential backoff, max 5 attempts | Then fallback to 2s polling |
| Moralis fallback | Known token address list | If Moralis returns 5xx |
| Private key policy | Never stored, never transmitted | Architecture — all signing in wallet provider |
| Signature scope | Scoped to specific `manifestHash` | Cannot replay plan A signature on plan B |
| Contract upgradeability | None | Immutable deployment — no proxy |
| Retained user funds post-execution | Zero | Enforced by remainder-return loop in contract |
| Adapter approval residue | Zero | Reset to 0 after every swap action |
| Unknown token default | Signing blocked | Require typed override confirmation |

---

## 19. Mandatory Implementation Addendum

> **Status:** Binding. This addendum overrides any conflicting implementation detail in Sections 1–18. It does not reduce product scope; it corrects contract ownership semantics, Monad-specific execution behavior, signing safety, deployment architecture, and mainnet security assumptions before implementation.

### 19.1 Final Product Identity

- **Product name:** TIDYR
- **Domain:** `tidyr.xyz`
- **Public descriptor:** Monad multi-wallet cleanup terminal
- **Core promise:** Clean every Monad wallet without blindly signing anything.
- **Contracts may retain descriptive names** such as `SweepExecutor`, `executeSweep`, and `SweepCompleted`; the consumer-facing product is always branded **TIDYR**.

---

### 19.2 Approval Revocations Are Wallet-Level Transactions

The executor cannot revoke an allowance owned by the user's EOA. If `SweepExecutor` calls:

```solidity
IERC20(token).approve(spender, 0);
```

it changes `allowance[SweepExecutor][spender]`, not `allowance[userEOA][spender]`.

Therefore, remove `RevokeAction[] revocations` from `SweepPlan` and remove executor-side revoke execution. Revocations remain a full TIDYR feature, but each revoke is encoded as a direct wallet transaction:

```typescript
type WalletTransaction =
  | RevokeTransaction
  | Permit2ApprovalTransaction
  | SweepExecutionTransaction
  | TopUpTransaction
  | MultiSendTransaction;
```

Correct per-wallet graph:

```text
Wallet A
├── ERC20.approve(oldSpender, 0)
├── ERC20.approve(Permit2, exactAmount)       // only where required
└── SweepExecutor.executeSweep(plan, permit2Signature)
```

If the wallet supports EIP-5792 atomic batching, TIDYR may package these calls into one wallet batch. Otherwise, they remain sequential user-signed transactions.

#### Revised `SweepPlan`

```solidity
struct SweepPlan {
    address owner;
    address recipient;
    address outputToken;
    uint256 deadline;
    uint256 nonce;
    bytes32 displayManifestHash;
    SwapAction[] swaps;
    TransferAction[] transfers;
    DiscardAction[] discards;
    BurnAction[] burns;
}
```

---

### 19.3 Use Two Distinct Hashes

The canonical human-readable JSON manifest and Solidity ABI encoding are different byte representations and must not be expected to hash to the same value.

Use:

```text
displayManifestHash
= keccak256(RFC 8785 canonical human-readable JSON)

executionPlanHash
= keccak256(ABI-encoded typed execution fields)
```

The frontend shows and stores `displayManifestHash`. The contract validates `executionPlanHash`. Permit2 witness data must bind token authorization to `executionPlanHash` so a valid permit cannot be reused for a different execution plan.

Recommended event:

```solidity
event SweepCompleted(
    bytes32 indexed executionPlanHash,
    bytes32 indexed displayManifestHash,
    address indexed owner,
    address recipient,
    address outputToken,
    uint256 outputAmount,
    uint256 successfulActions,
    uint256 failedActions
);
```

Recommended typed hash helper:

```solidity
function hashPlan(SweepPlan calldata plan) public pure returns (bytes32) {
    return keccak256(
        abi.encode(
            plan.owner,
            plan.recipient,
            plan.outputToken,
            plan.deadline,
            plan.nonce,
            plan.displayManifestHash,
            hashSwapActions(plan.swaps),
            hashTransferActions(plan.transfers),
            hashDiscardActions(plan.discards),
            hashBurnActions(plan.burns)
        )
    );
}
```

Dynamic arrays must be hashed deterministically per action type rather than relying on an ambiguous frontend serialization.

---

### 19.4 ERC-7730 Clear-Signing Descriptors

TIDYR's human-readable review must not exist only inside the website. After contracts are deployed, publish ERC-7730 descriptors for chain ID `143` so compatible wallets can independently render TIDYR calls and typed signatures.

Repository layout:

```text
erc7730/
├── tidyr-sweep-executor.json
├── tidyr-permit2-witness.json
├── tidyr-top-up.json
└── tidyr-multisend.json
```

Descriptors must cover:

- owner;
- recipient;
- output token;
- action counts;
- deadline;
- execution plan hash;
- display manifest hash;
- exact Permit2 token limits;
- top-up recipients and amounts;
- multi-send recipients and amounts.

The frontend's three-layer review remains mandatory:

1. typed intent manifest;
2. calldata decode-and-compare verification;
3. transaction simulation and balance-delta review.

ERC-7730 is an additional independent wallet-level rendering layer.

---

### 19.5 Monad Gas-Limit Accounting

Monad charges the sender according to the submitted transaction gas limit. TIDYR must not use oversized multipliers such as `estimate * 2`.

Required policy:

```typescript
const estimate = await publicClient.estimateContractGas(request);
const gasLimit = estimate + estimate / 10n; // default 10% buffer
```

Apply action-specific sanity ceilings and reject abnormal estimates:

```typescript
const GAS_SANITY_CEILINGS = {
  revoke: 100_000n,
  permit2Approval: 110_000n,
  executeBase: 250_000n,
  perV2Swap: 250_000n,
  perV3Swap: 400_000n,
  perTransfer: 80_000n,
  perDiscard: 80_000n,
  perBurn: 120_000n,
};
```

These are defensive ceilings, not hardcoded transaction limits. Recalibrate them from deployed-contract measurements before production release.

Every review card must display:

```text
Maximum network charge
Gas limit
Gas price
Estimated fee in MON
```

Signing is blocked when:

- estimation fails;
- estimate exceeds configured sanity limits without an explicit supported reason;
- simulation and gas estimation disagree materially;
- wallet-provided gas differs unexpectedly from the reviewed gas.

---

### 19.6 Monad Commitment States

Do not represent the first seen block as final confirmation. The execution monitor must model:

```text
BROADCAST → PROPOSED → VOTED → FINALIZED → VERIFIED
```

UI behavior:

- **Proposed:** immediate responsive status;
- **Voted:** consensus progress;
- **Finalized:** irreversible completion for user-facing reports;
- **Verified:** delayed execution verification where available.

A wallet is marked complete only after the relevant transaction/event is finalized. Permanent status reports are generated from finalized events.

Recommended record:

```typescript
interface TransactionCommitment {
  hash: Hex;
  submittedAt: number;
  proposedAt?: number;
  votedAt?: number;
  finalizedAt?: number;
  verifiedAt?: number;
  blockNumber?: bigint;
}
```

If an RPC provider does not expose every commitment phase, show only phases actually supported and never relabel `latest` as `finalized`.

---

### 19.7 Pending-Transaction Tracking

Do not depend on `newPendingTransactions` or immediate `eth_getTransactionByHash` visibility.

Persist the locally known transaction state after RPC acceptance:

```typescript
interface SubmittedTransaction {
  wallet: Address;
  hash: Hex;
  nonce: bigint;
  submittedAt: number;
  rpcAccepted: boolean;
  blockSeen?: bigint;
  receipt?: TransactionReceipt;
  commitment: 'BROADCAST' | 'PROPOSED' | 'VOTED' | 'FINALIZED' | 'VERIFIED' | 'FAILED';
}
```

Tracking flow:

1. calculate or retain the transaction hash locally;
2. record the RPC submission response;
3. subscribe to new heads/logs;
4. query receipts as blocks advance;
5. optionally use Monad-specific txpool status methods where supported;
6. do not classify a transaction as failed merely because a hash lookup temporarily returns `null`;
7. fail only after a configured block/time threshold or an explicit failed receipt/rejection.

---

### 19.8 Reserve-Aware Native MON Scheduling

TIDYR must account for Monad's reserve-balance behavior.

#### Undelegated EOA

When a user wants to move almost all native MON:

1. complete token approvals, revocations, swaps, and token transfers;
2. wait at least three new blocks after the wallet's preceding transaction;
3. submit the native-MON emptying transaction last;
4. reserve enough MON for that final transaction's maximum network fee.

#### EIP-7702-Delegated EOA

A delegated account must preserve Monad's required native reserve. TIDYR must:

- detect delegation by reading account code;
- show the reserve warning before planning;
- prevent a native MON sweep below the required reserve;
- offer an explicit undelegation workflow before attempting to empty the wallet;
- never auto-delegate an account;
- never require EIP-7702 for ordinary use.

The scheduler must calculate a safe sweepable native balance:

```text
safeNativeSweep = currentBalance
                - requiredReserve
                - maximumReviewedGasCost
                - optionalUserBuffer
```

---

### 19.9 Correct `allowFailure` Semantics

The executor cannot allow a successful swap to remain committed and then retroactively treat low output as a harmless partial failure.

Correct flow:

1. adapter calls the DEX router with `minAmountOut` enforced inside the router call;
2. router reverts atomically when minimum output is not met;
3. executor catches the adapter revert;
4. if `allowFailure == true`, emit failure and continue;
5. otherwise revert the entire sweep;
6. the input remains available because the failed external call reverted atomically.

Pattern:

```solidity
try IAdapter(action.adapter).swap(action, plan.recipient) returns (uint256 reportedOut) {
    uint256 actualOut = outputAfter - outputBefore;
    if (actualOut < action.minAmountOut) {
        revert AdapterInvariantViolation(action.adapter, reportedOut, actualOut);
    }
    successCount++;
} catch (bytes memory reason) {
    token.forceApprove(action.adapter, 0);
    if (!action.allowFailure) {
        assembly { revert(add(reason, 32), mload(reason)) }
    }
    emit SwapFailed(
        executionPlanHash,
        action.tokenIn,
        action.amountIn,
        reason
    );
    failCount++;
}
```

The adapter must deliver output to `SweepExecutor`, not directly to an arbitrary address, so the executor can enforce balance-delta accounting before final settlement.

---

### 19.10 Isolate Plan Funds from Pre-Existing Contract Balances

Never transfer the executor's entire token balance to the current user. Tokens can be forcibly or accidentally sent to the contract before another plan executes.

For every touched token, record the starting balance before pulling plan funds:

```solidity
uint256 startingBalance = token.balanceOf(address(this));
```

At settlement:

```solidity
uint256 endingBalance = token.balanceOf(address(this));
uint256 planRemainder = endingBalance - startingBalance;
```

Only `planRemainder` belongs to the active plan. Apply the same delta model to the output token and native MON.

Additional requirements:

- de-duplicate touched token addresses before recording baselines;
- never let one action consume another plan's pre-existing balance;
- reject the output token as an input where accounting would become ambiguous unless explicitly handled;
- include a narrowly scoped owner recovery function only for balances that predate or are unrelated to an active plan;
- recovery must never run during execution and must emit an event.

---

### 19.11 OpenZeppelin v5 Patterns

Use Solidity `^0.8.26` or the compiler version recommended by current Monad tooling, pinned exactly in CI and deployment configuration.

Use OpenZeppelin v5 imports:

```solidity
import {ReentrancyGuard} from
    "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from
    "@openzeppelin/contracts/access/Ownable2Step.sol";
```

Use:

```solidity
using SafeERC20 for IERC20;
token.forceApprove(spender, amount);
token.forceApprove(spender, 0);
```

Use `Ownable2Step` for adapter administration. After deployment, transfer ownership to a dedicated Safe or operational owner, then accept ownership from that account.

No proxy, no `delegatecall`, no arbitrary external target, and no `tx.origin`.

---

### 19.12 Demo Liquidity Must Be Dynamically Sized

Do not assume a fixed MON/USD price. The deployment script must calculate or clearly display the live approximate value of liquidity before broadcasting.

Preferred configuration:

```bash
DEMO_WMON_PER_POOL=50
DEMO_TOKEN_PER_POOL=10000
```

The script must:

1. read canonical WMON and router addresses from version-controlled chain constants;
2. verify bytecode exists at each external contract address;
3. verify router/factory relationships where possible;
4. print the MON amount and estimated fiat value;
5. require explicit deployment confirmation;
6. record pair addresses and liquidity transaction hashes;
7. verify each pair has non-zero reserves;
8. run a small buy and sell smoke test before marking the pair usable.

Never deploy substitute WMON or USDC when canonical mainnet assets already exist. Abort if canonical addresses cannot be verified.

---

### 19.13 Railway-Only Infrastructure

Replace Vercel hosting references in Section 15 with Railway.

Repository:

```text
tidyr/
├── apps/
│   ├── web/                  # Next.js frontend
│   ├── api/                  # Hono API
│   └── indexer/              # finalized-event worker
├── packages/
│   ├── contracts/            # Foundry contracts, tests, scripts
│   ├── shared/               # types, ABIs, chain constants
│   ├── execution/            # multi-wallet scheduler
│   ├── routing/              # Pancake, Uniswap, 0x routing
│   └── transaction-review/   # manifests, calldata checks, ERC-7730
├── deployments/
│   └── mainnet.json
├── erc7730/
├── railway.json
└── pnpm-workspace.yaml
```

Railway services:

| Service | Responsibility |
|---|---|
| `tidyr-web` | Next.js UI and static assets |
| `tidyr-api` | asset discovery, quotes, simulations, allowance scans |
| `tidyr-indexer` | finalized event ingestion and report reconstruction |
| `tidyr-postgres` | manifests, wallet labels, execution sessions, indexed reports |
| `tidyr-redis` | short-lived quotes, scan cache, distributed locks, execution progress |

Postgres is not the source of truth for successful execution. Finalized Monad receipts and contract events are authoritative.

#### Railway health requirements

- `/health/live` for process liveness;
- `/health/ready` for RPC, Postgres, and Redis readiness;
- graceful shutdown for the indexer;
- idempotent event processing keyed by `chainId + txHash + logIndex`;
- migration job before API/indexer rollout;
- separate staging and production Railway environments;
- secrets restricted by service rather than globally exposed.

---

### 19.14 Deployment-Key Policy

The deployed TIDYR application is non-custodial and does not require a private key at runtime.

The deployment key is used only for:

- contract deployment;
- initial adapter registration;
- demo liquidity provisioning;
- distributor funding;
- initial ownership transfer.

Required environment variable for deployment only:

```bash
DEPLOYER_PRIVATE_KEY=
```

Rules:

- never prefix it with `NEXT_PUBLIC_`;
- never expose it to `tidyr-web`;
- preferably keep it local or in a temporary Railway deployment job;
- remove it from Railway after deployment completes;
- transfer `SweepExecutor` ownership using `Ownable2Step`;
- verify ownership acceptance before deleting the deployment secret;
- the API and indexer must operate using RPC URLs and public addresses only.

User wallet signing always occurs through wallet providers. TIDYR never stores, receives, transmits, or reconstructs user private keys or seed phrases.

---

### 19.15 Corrected Contract Boundaries

#### `SweepExecutor`

Responsible for:

- validating plan owner, recipient, output asset, nonce, deadline, and hashes;
- consuming exact Permit2-authorized token amounts;
- executing allowlisted adapter swaps;
- transfers, discards, and supported burns;
- WMON unwrap and final output settlement;
- balance-delta isolation;
- emitting execution/report events.

Not responsible for:

- revoking allowances owned by an EOA;
- arbitrary calls;
- wallet connection;
- quote generation;
- token classification;
- finality monitoring;
- storing user funds between transactions.

#### `PancakeV2Adapter`

- immutable router and WMON addresses;
- validates path starts at `tokenIn` and ends at expected output;
- pulls the exact approved amount from executor;
- executes router swap with non-zero `minAmountOut` and deadline;
- sends output back to executor;
- returns a value for observability only; executor trusts balance deltas.

#### `UniswapV3Adapter`

- immutable Universal Router/Permit2 dependencies as required;
- strict command allowlist;
- path token validation;
- no arbitrary Universal Router command bytes from the user;
- deadline and minimum output enforced;
- output returned to executor.

#### `DemoDistributor`

- one claim per address;
- checks all transfer results through `SafeERC20`;
- fixed claim amount per token;
- owner may pause claims only for emergency depletion or token error;
- no arbitrary withdrawal of user funds because it holds only demo inventory.

---

### 19.16 Revised Action and Classification Rules

A token may have multiple capabilities. Classification and action availability must not be incorrectly modeled as one strictly exclusive enum.

Use a primary risk state plus capability flags:

```typescript
interface TokenAssessment {
  riskState: 'VERIFIED' | 'UNKNOWN';
  capabilities: {
    tradable: boolean;
    transferable: boolean;
    burnable: boolean;
  };
  quote?: Quote;
  transferSimulation?: SimulationResult;
  burnSimulation?: SimulationResult;
  failureReasons: string[];
}
```

Examples:

- DUST4 can be both tradable and burnable;
- a token may be tradable but not safely discardable due to transfer restrictions;
- metadata failure must not erase a verified balance, but it must force UNKNOWN presentation and block default signing;
- actions appear only when their own simulation and verification requirements pass.

No expert override may bypass contract target allowlists or calldata verification. It may only allow a user to proceed with a specifically simulated direct token action that remains within supported action types.

---

### 19.17 Final Status Report Source of Truth

The report combines:

1. finalized transaction receipts;
2. `SweepCompleted`, per-action success/failure, transfer, discard, and burn events;
3. pre-execution manifest stored by `displayManifestHash`;
4. finalized before/after balance reads;
5. direct wallet transaction receipts for revokes and approvals.

The report must not infer per-action success only from aggregate counters. Emit enough action-level data to reconstruct every row.

Recommended action event:

```solidity
event ActionExecuted(
    bytes32 indexed executionPlanHash,
    uint256 indexed actionIndex,
    uint8 indexed actionType,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    address destination
);
```

Recommended failure event:

```solidity
event ActionFailed(
    bytes32 indexed executionPlanHash,
    uint256 indexed actionIndex,
    uint8 indexed actionType,
    address token,
    bytes32 reasonHash
);
```

Keep full revert bytes offchain in the execution session when available; store a deterministic hash onchain to prevent oversized logs.

---

### 19.18 Updated Environment Variables

```bash
# Public chain configuration
MONAD_CHAIN_ID=143
MONAD_RPC_URL=
MONAD_WS_URL=
MONAD_FINALITY_RPC_URL=

# Indexing and simulation
MORALIS_API_KEY=
TENDERLY_ACCOUNT=
TENDERLY_PROJECT=
TENDERLY_ACCESS_KEY=
ZEROX_API_KEY=

# Railway data services
DATABASE_URL=
REDIS_URL=

# Contracts — public after deployment
SWEEP_EXECUTOR_ADDRESS=
PANCAKE_V2_ADAPTER_ADDRESS=
UNIV3_ADAPTER_ADDRESS=
PERMIT2_ADDRESS=
PANCAKE_V2_FACTORY=
PANCAKE_V2_ROUTER=
UNISWAP_UNIVERSAL_ROUTER=
WMON_ADDRESS=
USDC_ADDRESS=
DEMO_DISTRIBUTOR_ADDRESS=
DUST1_ADDRESS=
DUST2_ADDRESS=
DUST3_ADDRESS=
DUST4_ADDRESS=
DUST5_ADDRESS=

# Deployment only — remove after ownership transfer
DEPLOYER_PRIVATE_KEY=

# Operational owner — public address only
PROTOCOL_OWNER_ADDRESS=
```

Only browser-safe public values may use `NEXT_PUBLIC_`. API keys, database URLs, Redis URLs, and deployment secrets remain server-only.

---

### 19.19 Updated Build and Deployment Sequence

Execute in this order:

```text
1.  Register and configure tidyr.xyz.
2.  Create the Railway-ready pnpm monorepo.
3.  Pin compiler, Foundry, Node/Bun, OpenZeppelin, viem, and wagmi versions.
4.  Implement corrected action structs without executor-side revocations.
5.  Implement deterministic execution-plan hashing and display-manifest hashing.
6.  Implement Permit2 witness binding to executionPlanHash.
7.  Implement PancakeV2Adapter with strict path validation.
8.  Implement UniswapV3Adapter with strict command/path allowlists.
9.  Add balance-delta isolation and corrected allowFailure behavior.
10. Add Foundry unit, fuzz, invariant, and fork tests.
11. Run Slither and document all accepted findings.
12. Deploy adapter contracts and SweepExecutor to Monad mainnet.
13. Register adapters and transfer ownership through Ownable2Step.
14. Deploy five demo tokens and DemoDistributor.
15. Verify canonical WMON, USDC, Permit2, Pancake, and Uniswap addresses onchain.
16. Provision four real Pancake V2 pools using dynamically reviewed liquidity amounts.
17. Run buy/sell smoke tests for every tradable demo token.
18. Source-verify every TIDYR contract and publish deployments/mainnet.json.
19. Publish ERC-7730 descriptors for deployed addresses.
20. Deploy Railway Postgres and Redis.
21. Deploy tidyr-indexer with finalized, idempotent event ingestion.
22. Deploy tidyr-api with indexer, quote, simulation, and allowance endpoints.
23. Deploy tidyr-web and connect tidyr.xyz.
24. Test claimDemoBundle() from at least three fresh EOAs.
25. Run complete multi-wallet planning, review, signing, and concurrent broadcast.
26. Verify Proposed/Voted/Finalized/Verified UI behavior against RPC capabilities.
27. Test reserve-aware native MON cleanup for undelegated and delegated accounts.
28. Generate a finalized event-derived report with no hardcoded success state.
29. Record the first successful TIDYR mainnet cleanup transaction in README.
30. Remove DEPLOYER_PRIVATE_KEY from Railway and confirm runtime services remain functional.
```

---

### 19.20 Release Gate

TIDYR is not submission-ready until all boxes below pass:

#### Contracts

- [ ] Revocations are direct EOA transactions, not executor actions.
- [ ] Permit2 authorization is bound to `executionPlanHash`.
- [ ] Display and execution hashes are independently verified.
- [ ] No arbitrary calls or `delegatecall` exist.
- [ ] Adapters enforce route, deadline, input, output, and minimum return.
- [ ] `allowFailure` preserves unsold input on adapter failure.
- [ ] Plan balances are isolated from pre-existing executor balances.
- [ ] Temporary allowances reset with `forceApprove`.
- [ ] Action-level events reconstruct the complete report.
- [ ] Ownership has moved to the intended operational owner.

#### Frontend and Signing

- [ ] Every signature card is derived from verified calldata and simulation.
- [ ] Direct revokes and approvals appear in the same review session.
- [ ] Unknown calls block signing.
- [ ] ERC-7730 descriptors are published.
- [ ] Gas limit and maximum MON fee are shown.
- [ ] Quote expiry is visible and enforced.
- [ ] Wallet capability claims come from `wallet_getCapabilities`.

#### Monad Execution

- [ ] Transactions are scheduled concurrently across EOAs and sequentially within each EOA.
- [ ] Local transaction hashes persist before block inclusion.
- [ ] Missing mempool lookup is not treated as failure.
- [ ] Reports wait for finalized receipts/events.
- [ ] Native MON sweeps respect reserve and delegation rules.
- [ ] WebSocket failure falls back to polling without duplicating state.

#### Infrastructure

- [ ] All services run on Railway.
- [ ] Event ingestion is idempotent.
- [ ] Postgres stores manifests and indexed reports, not fabricated success.
- [ ] Redis contains only disposable state.
- [ ] Deployment key is absent from runtime services.
- [ ] `tidyr.xyz` resolves to the production web service.

#### Demonstration

- [ ] Five demo tokens are live and verified.
- [ ] Four pools have real reserves and working sell paths.
- [ ] DUST5 is honestly classified as non-tradable.
- [ ] Judges can claim a real demo bundle.
- [ ] At least three EOAs complete one concurrent TIDYR run.
- [ ] Every report row links to a real Monad mainnet transaction.

