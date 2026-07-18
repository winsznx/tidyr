import { encodeAbiParameters, zeroAddress } from "viem";
import type { Address, Hex, PublicClient } from "viem";
import {
  AdapterKind,
  MON_NATIVE_SENTINEL,
  type SweepPlan,
  type SwapAction,
  type TransferAction,
  type DiscardAction,
  type BurnAction,
} from "@tidyr/shared";
import { hashDisplayManifest, hashExecutionPlan } from "@tidyr/transaction-review";
import type { SweepManifest, SweepManifestAction } from "@tidyr/transaction-review";

import { erc20Abi } from "@/lib/abi/erc20";
import { pancakeV2FactoryAbi, pancakeV2PairAbi } from "@/lib/abi/factories";
import { uniswapV3QuoterV2Abi } from "@/lib/abi/quoter";
import { sweepExecutorAbi } from "@/lib/abi/sweep-executor";
import { EXTERNAL_ADDRESSES, MAINNET_CHAIN_ID, MAINNET_DEPLOYMENT } from "@/lib/deployment";
import { encodeUniswapV3Path } from "@/lib/routing/encode-path";
import { findUniswapV3DirectRoute } from "@/lib/routing/find-route";
import type { PlanAction } from "@/store/plan";

/**
 * Same window used by the real Phase 10 mainnet smoke sweep
 * (packages/contracts/script/Phase10SmokeSweepFinal.s.sol: `block.timestamp + 900`),
 * matching Permit2's short-lived witness-signature convention.
 */
const DEADLINE_WINDOW_SECONDS = 900n;

/** 2% slippage tolerance, matching deployments/mainnet.json's phase10.smokeSweep.slippageTolerancePct. */
const SLIPPAGE_TOLERANCE_BPS = 200n;

export interface WalletPlanWarning {
  token: Address;
  type: PlanAction["type"];
  message: string;
}

export interface WalletPlanResult {
  wallet: Address;
  /** Non-null only when every action in this wallet's plan resolved cleanly. */
  manifest: SweepManifest | null;
  plan: SweepPlan | null;
  displayManifestHash: Hex | null;
  executionPlanHash: Hex | null;
  /** Blocking problems — a valid SweepPlan could not be built while these exist. */
  errors: string[];
  /** Non-blocking, per-action limitations (e.g. no sell route found for a token). */
  warnings: WalletPlanWarning[];
}

interface TokenInfo {
  address: Address;
  symbol: string;
  decimals: number;
  balance: bigint;
}

function tokensForWallet(actions: PlanAction[]): Address[] {
  return [...new Set(actions.map((a) => a.token))];
}

async function fetchTokenInfo(
  client: PublicClient,
  wallet: Address,
  tokens: Address[],
): Promise<Map<Address, TokenInfo>> {
  const map = new Map<Address, TokenInfo>();
  if (tokens.length === 0) return map;

  const calls = tokens.flatMap((token) => [
    { address: token, abi: erc20Abi, functionName: "balanceOf", args: [wallet] } as const,
    { address: token, abi: erc20Abi, functionName: "symbol" } as const,
    { address: token, abi: erc20Abi, functionName: "decimals" } as const,
  ]);
  const results = await client.multicall({ contracts: calls, allowFailure: true });

  tokens.forEach((token, i) => {
    const balanceResult = results[i * 3];
    const symbolResult = results[i * 3 + 1];
    const decimalsResult = results[i * 3 + 2];
    map.set(token, {
      address: token,
      balance: balanceResult?.status === "success" ? (balanceResult.result as bigint) : 0n,
      symbol: symbolResult?.status === "success" ? (symbolResult.result as string) : "UNKNOWN",
      decimals: decimalsResult?.status === "success" ? (decimalsResult.result as number) : 18,
    });
  });

  return map;
}

interface ResolvedRoute {
  adapterKind: (typeof AdapterKind)[keyof typeof AdapterKind];
  routeData: Hex;
  routeLabel: string;
  quotedAmountOut: bigint;
}

async function quoteUniswapV3Single(
  client: PublicClient,
  tokenIn: Address,
  tokenOut: Address,
  fee: number,
  amountIn: bigint,
): Promise<bigint> {
  const { result } = await client.simulateContract({
    address: EXTERNAL_ADDRESSES.uniswapV3QuoterV2,
    abi: uniswapV3QuoterV2Abi,
    functionName: "quoteExactInputSingle",
    args: [{ tokenIn, tokenOut, amountIn, fee, sqrtPriceLimitX96: 0n }],
  });
  return result[0];
}

async function quoteUniswapV3Path(
  client: PublicClient,
  path: Hex,
  amountIn: bigint,
): Promise<bigint> {
  const { result } = await client.simulateContract({
    address: EXTERNAL_ADDRESSES.uniswapV3QuoterV2,
    abi: uniswapV3QuoterV2Abi,
    functionName: "quoteExactInput",
    args: [path, amountIn],
  });
  return result[0];
}

/** Real UniswapV2-style constant-product quote (0.3% fee), reading live reserves — mirrors PancakeV2Adapter.sol's own `_getAmountsOut` math exactly. */
async function quotePancakeHop(
  client: PublicClient,
  tokenIn: Address,
  tokenOut: Address,
  amountIn: bigint,
): Promise<bigint> {
  const pair = await client.readContract({
    address: EXTERNAL_ADDRESSES.pancakeV2Factory,
    abi: pancakeV2FactoryAbi,
    functionName: "getPair",
    args: [tokenIn, tokenOut],
  });
  if (pair === zeroAddress) throw new Error(`no Pancake pair for ${tokenIn} -> ${tokenOut}`);

  const [reserves, token0] = await Promise.all([
    client.readContract({ address: pair, abi: pancakeV2PairAbi, functionName: "getReserves" }),
    client.readContract({ address: pair, abi: pancakeV2PairAbi, functionName: "token0" }),
  ]);
  const [reserve0, reserve1] = reserves;
  const [reserveIn, reserveOut] =
    token0.toLowerCase() === tokenIn.toLowerCase() ? [reserve0, reserve1] : [reserve1, reserve0];

  if (reserveIn === 0n || reserveOut === 0n) throw new Error("insufficient Pancake liquidity");
  const amountInWithFee = amountIn * 997n;
  const numerator = amountInWithFee * BigInt(reserveOut);
  const denominator = BigInt(reserveIn) * 1000n + amountInWithFee;
  return numerator / denominator;
}

/**
 * Resolves a real, executable sell route + quote for `tokenIn -> settlementToken`.
 * Tries a direct Uniswap V3 pool first, then a tokenIn->WMON->settlementToken
 * 2-hop Uniswap V3 path, then the same fallback shape on Pancake V2. Returns
 * `null` — never a fabricated route — when no real pool/pair supports the swap.
 */
async function resolveSellRoute(
  client: PublicClient,
  tokenIn: Address,
  settlementToken: Address,
  amountIn: bigint,
): Promise<ResolvedRoute | null> {
  const wmon = EXTERNAL_ADDRESSES.wmon;

  const direct = await findUniswapV3DirectRoute(client, tokenIn, settlementToken);
  if (direct) {
    const quotedAmountOut = await quoteUniswapV3Single(
      client,
      tokenIn,
      settlementToken,
      direct.fee,
      amountIn,
    );
    return {
      adapterKind: AdapterKind.UNISWAP_V3,
      routeData: encodeUniswapV3Path([
        { token: tokenIn, fee: direct.fee },
        { token: settlementToken },
      ]),
      routeLabel: `uniswap-v3: ${tokenIn} -> ${settlementToken} (fee ${direct.fee})`,
      quotedAmountOut,
    };
  }

  if (settlementToken.toLowerCase() !== wmon.toLowerCase()) {
    const [legIn, legOut] = await Promise.all([
      findUniswapV3DirectRoute(client, tokenIn, wmon),
      findUniswapV3DirectRoute(client, wmon, settlementToken),
    ]);
    if (legIn && legOut) {
      const path = encodeUniswapV3Path([
        { token: tokenIn, fee: legIn.fee },
        { token: wmon, fee: legOut.fee },
        { token: settlementToken },
      ]);
      const quotedAmountOut = await quoteUniswapV3Path(client, path, amountIn);
      return {
        adapterKind: AdapterKind.UNISWAP_V3,
        routeData: path,
        routeLabel: `uniswap-v3: ${tokenIn} -> WMON -> ${settlementToken} (fees ${legIn.fee}/${legOut.fee})`,
        quotedAmountOut,
      };
    }
  }

  try {
    if (settlementToken.toLowerCase() === wmon.toLowerCase()) {
      const quotedAmountOut = await quotePancakeHop(client, tokenIn, settlementToken, amountIn);
      return {
        adapterKind: AdapterKind.PANCAKE_V2,
        routeData: encodeAbiParameters([{ type: "address[]" }], [[tokenIn, settlementToken]]),
        routeLabel: `pancake-v2: ${tokenIn} -> ${settlementToken}`,
        quotedAmountOut,
      };
    }

    const directPair = await client.readContract({
      address: EXTERNAL_ADDRESSES.pancakeV2Factory,
      abi: pancakeV2FactoryAbi,
      functionName: "getPair",
      args: [tokenIn, settlementToken],
    });
    if (directPair !== zeroAddress) {
      const quotedAmountOut = await quotePancakeHop(client, tokenIn, settlementToken, amountIn);
      return {
        adapterKind: AdapterKind.PANCAKE_V2,
        routeData: encodeAbiParameters([{ type: "address[]" }], [[tokenIn, settlementToken]]),
        routeLabel: `pancake-v2: ${tokenIn} -> ${settlementToken}`,
        quotedAmountOut,
      };
    }

    const hopOut = await quotePancakeHop(client, tokenIn, wmon, amountIn);
    const finalOut = await quotePancakeHop(client, wmon, settlementToken, hopOut);
    return {
      adapterKind: AdapterKind.PANCAKE_V2,
      routeData: encodeAbiParameters([{ type: "address[]" }], [[tokenIn, wmon, settlementToken]]),
      routeLabel: `pancake-v2: ${tokenIn} -> WMON -> ${settlementToken}`,
      quotedAmountOut: finalOut,
    };
  } catch {
    return null;
  }
}

async function buildWalletPlan(
  client: PublicClient,
  wallet: Address,
  actionsForWallet: PlanAction[],
): Promise<WalletPlanResult> {
  const errors: string[] = [];
  const warnings: WalletPlanWarning[] = [];

  const consolidateActions = actionsForWallet.filter((a) => a.type === "consolidate");
  const sellActions = actionsForWallet.filter((a) => a.type === "sell");

  const recipients = new Set(consolidateActions.map((a) => a.recipient));
  if (consolidateActions.some((a) => !a.recipient)) {
    errors.push("A consolidate action is missing a recipient wallet.");
  } else if (recipients.size > 1) {
    errors.push(
      "This wallet's consolidate actions specify different recipients — a SweepPlan can only pay out to one recipient per wallet.",
    );
  }

  const outputTokens = new Set(sellActions.map((a) => a.outputToken));
  if (sellActions.some((a) => !a.outputToken)) {
    errors.push("A sell action is missing an output token.");
  } else if (outputTokens.size > 1) {
    errors.push(
      "This wallet's sell actions specify different output tokens — a SweepPlan can only settle to one output token per wallet.",
    );
  }

  if (errors.length > 0) {
    return {
      wallet,
      manifest: null,
      plan: null,
      displayManifestHash: null,
      executionPlanHash: null,
      errors,
      warnings,
    };
  }

  const recipient: Address = consolidateActions[0]?.recipient ?? wallet;
  const outputToken: Address = sellActions[0]?.outputToken ?? MON_NATIVE_SENTINEL;
  const settlementToken: Address =
    outputToken.toLowerCase() === MON_NATIVE_SENTINEL.toLowerCase()
      ? EXTERNAL_ADDRESSES.wmon
      : outputToken;

  const tokenInfo = await fetchTokenInfo(client, wallet, tokensForWallet(actionsForWallet));

  const swaps: SwapAction[] = [];
  const transfers: TransferAction[] = [];
  const discards: DiscardAction[] = [];
  const burns: BurnAction[] = [];
  const manifestActions: SweepManifestAction[] = [];

  for (const action of actionsForWallet) {
    const info = tokenInfo.get(action.token);
    if (!info || info.balance === 0n) {
      warnings.push({
        token: action.token,
        type: action.type,
        message: "Wallet currently holds a zero balance of this token — excluded from the plan.",
      });
      continue;
    }

    const amountHuman = formatAmount(info.balance, info.decimals);

    if (action.type === "discard") {
      discards.push({ token: action.token, amount: info.balance });
      manifestActions.push({
        type: "DISCARD",
        token: action.token,
        tokenSymbol: info.symbol,
        amount: amountHuman,
        amountWei: info.balance.toString(),
      });
    } else if (action.type === "burn") {
      burns.push({ token: action.token, amount: info.balance });
      manifestActions.push({
        type: "BURN",
        token: action.token,
        tokenSymbol: info.symbol,
        amount: amountHuman,
        amountWei: info.balance.toString(),
      });
    } else if (action.type === "consolidate") {
      transfers.push({ token: action.token, amount: info.balance, to: recipient });
      manifestActions.push({
        type: "CONSOLIDATE",
        token: action.token,
        tokenSymbol: info.symbol,
        amount: amountHuman,
        amountWei: info.balance.toString(),
      });
    } else if (action.type === "sell") {
      const route = await resolveSellRoute(client, action.token, settlementToken, info.balance);
      if (!route) {
        warnings.push({
          token: action.token,
          type: "sell",
          message: "No real on-chain route was found to swap this token — excluded from the plan.",
        });
        continue;
      }
      const minAmountOut = (route.quotedAmountOut * (10_000n - SLIPPAGE_TOLERANCE_BPS)) / 10_000n;
      swaps.push({
        tokenIn: action.token,
        amountIn: info.balance,
        adapterKind: route.adapterKind,
        minAmountOut,
        routeData: route.routeData,
        allowFailure: false,
      });
      manifestActions.push({
        type: "SWAP",
        token: action.token,
        tokenSymbol: info.symbol,
        amount: amountHuman,
        amountWei: info.balance.toString(),
        outputToken,
        minimumOutput: minAmountOut.toString(),
        route: route.routeLabel,
        slippageBps: Number(SLIPPAGE_TOLERANCE_BPS),
      });
    }
  }

  const totalActions = swaps.length + transfers.length + discards.length + burns.length;
  if (totalActions === 0) {
    errors.push("No executable actions remain for this wallet — every planned action was excluded.");
    return {
      wallet,
      manifest: null,
      plan: null,
      displayManifestHash: null,
      executionPlanHash: null,
      errors,
      warnings,
    };
  }

  const nonce = await client.readContract({
    address: MAINNET_DEPLOYMENT.addresses.sweepExecutor,
    abi: sweepExecutorAbi,
    functionName: "nonces",
    args: [wallet],
  });

  const deadline = BigInt(Math.floor(Date.now() / 1000)) + DEADLINE_WINDOW_SECONDS;

  const manifest: SweepManifest = {
    wallet,
    recipient,
    outputToken: outputToken.toLowerCase() === MON_NATIVE_SENTINEL.toLowerCase() ? "MON" : "USDC",
    deadline: Number(deadline),
    actions: manifestActions,
  };

  const displayManifestHash = hashDisplayManifest(manifest);

  const plan: SweepPlan = {
    owner: wallet,
    recipient,
    outputToken,
    deadline,
    nonce,
    displayManifestHash,
    swaps,
    transfers,
    discards,
    burns,
  };

  const executionPlanHash = hashExecutionPlan(
    plan,
    BigInt(MAINNET_CHAIN_ID),
    MAINNET_DEPLOYMENT.addresses.sweepExecutor,
  );

  return {
    wallet,
    manifest,
    plan,
    displayManifestHash,
    executionPlanHash,
    errors,
    warnings,
  };
}

function formatAmount(balance: bigint, decimals: number): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = balance / divisor;
  const fraction = balance % divisor;
  if (fraction === 0n) return whole.toString();
  const fractionStr = fraction.toString().padStart(decimals, "0").replace(/0+$/, "");
  return fractionStr.length > 0 ? `${whole}.${fractionStr}` : whole.toString();
}

/**
 * Groups the plan store's actions by wallet (one SweepPlan per wallet, since
 * `executeSweep` is called once per owner), excludes "revoke" actions entirely
 * (per PRD §19.2 those are direct EOA transactions, never part of a SweepPlan),
 * and builds a real, on-chain-verified SweepPlan + SweepManifest for each
 * wallet that still has at least one non-revoke action.
 */
export async function buildSweepPlans(
  client: PublicClient,
  actions: PlanAction[],
): Promise<WalletPlanResult[]> {
  const relevant = actions.filter((a) => a.type !== "revoke");
  const wallets = [...new Set(relevant.map((a) => a.wallet))];

  return Promise.all(
    wallets.map((wallet) =>
      buildWalletPlan(
        client,
        wallet,
        relevant.filter((a) => a.wallet === wallet),
      ),
    ),
  );
}
