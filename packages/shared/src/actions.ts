import { z } from "zod";

/**
 * Mirrors packages/contracts/src/libraries/SweepPlanLib.sol exactly. Any field
 * added/removed/reordered here must be mirrored there and re-verified against the
 * golden vectors in test-vectors/golden-vectors.md.
 */

/** Branded hex string types, compatible with viem's `Address`/`Hex` types. */
export type Address = `0x${string}`;
export type Hex = `0x${string}`;

const addressSchema = z
  .string()
  .regex(/^0x[a-fA-F0-9]{40}$/, "must be a 20-byte hex address")
  .transform((v) => v as Address);

const hexSchema = z
  .string()
  .regex(/^0x[a-fA-F0-9]*$/, "must be 0x-prefixed hex")
  .transform((v) => v as Hex);

const uint256Schema = z.bigint().nonnegative();

/** Total action count bound — must match SweepPlanLib.MAX_ACTIONS. */
export const MAX_ACTIONS = 50;

/**
 * Native MON sentinel address. The PRD names this `MON_NATIVE_SENTINEL` without fixing
 * a literal value. We use the widely-adopted cross-protocol convention
 * (0xEeee...EEeE, as used by 0x, Aave, and others) rather than address(0), so that
 * "native asset" and "unset/invalid address" remain distinguishable throughout the
 * codebase (plan.recipient, plan.outputToken, etc. are validated as non-zero).
 */
export const MON_NATIVE_SENTINEL: Address = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

export const swapActionSchema = z.object({
  tokenIn: addressSchema,
  amountIn: uint256Schema,
  adapter: addressSchema,
  minAmountOut: uint256Schema,
  routeData: hexSchema,
  allowFailure: z.boolean(),
});
export type SwapAction = z.infer<typeof swapActionSchema>;

export const transferActionSchema = z.object({
  token: addressSchema,
  amount: uint256Schema,
  to: addressSchema,
});
export type TransferAction = z.infer<typeof transferActionSchema>;

export const discardActionSchema = z.object({
  token: addressSchema,
  amount: uint256Schema,
});
export type DiscardAction = z.infer<typeof discardActionSchema>;

export const burnActionSchema = z.object({
  token: addressSchema,
  amount: uint256Schema,
});
export type BurnAction = z.infer<typeof burnActionSchema>;

/**
 * No `revocations` field. Per PRD §19.2, the executor cannot revoke an allowance owned
 * by the user's EOA — revocations are direct wallet transactions (see
 * `WalletTransaction` below), never a SweepPlan action.
 */
export const sweepPlanSchema = z.object({
  owner: addressSchema,
  recipient: addressSchema,
  outputToken: addressSchema,
  deadline: uint256Schema,
  nonce: uint256Schema,
  displayManifestHash: hexSchema,
  swaps: z.array(swapActionSchema),
  transfers: z.array(transferActionSchema),
  discards: z.array(discardActionSchema),
  burns: z.array(burnActionSchema),
});
export type SweepPlan = z.infer<typeof sweepPlanSchema>;

export function totalActions(plan: SweepPlan): number {
  return plan.swaps.length + plan.transfers.length + plan.discards.length + plan.burns.length;
}

/**
 * Direct wallet-level transactions (PRD §19.2). These are never encoded inside a
 * SweepPlan — each is its own EOA-signed transaction, optionally bundled via EIP-5792
 * atomic batching when `wallet_getCapabilities` proves support (see
 * docs/research/monad-source-map.md §6).
 */
export const revokeTransactionSchema = z.object({
  type: z.literal("revoke"),
  token: addressSchema,
  spender: addressSchema,
});
export type RevokeTransaction = z.infer<typeof revokeTransactionSchema>;

export const permit2ApprovalTransactionSchema = z.object({
  type: z.literal("permit2Approval"),
  token: addressSchema,
  amount: uint256Schema,
});
export type Permit2ApprovalTransaction = z.infer<typeof permit2ApprovalTransactionSchema>;

export const sweepExecutionTransactionSchema = z.object({
  type: z.literal("sweepExecution"),
  plan: sweepPlanSchema,
  permit2Signature: hexSchema,
});
export type SweepExecutionTransaction = z.infer<typeof sweepExecutionTransactionSchema>;

export const topUpTransactionSchema = z.object({
  type: z.literal("topUp"),
  recipients: z.array(addressSchema),
  amounts: z.array(uint256Schema),
});
export type TopUpTransaction = z.infer<typeof topUpTransactionSchema>;

export const multiSendTransactionSchema = z.object({
  type: z.literal("multiSend"),
  token: addressSchema,
  recipients: z.array(addressSchema),
  amounts: z.array(uint256Schema),
});
export type MultiSendTransaction = z.infer<typeof multiSendTransactionSchema>;

export const walletTransactionSchema = z.discriminatedUnion("type", [
  revokeTransactionSchema,
  permit2ApprovalTransactionSchema,
  sweepExecutionTransactionSchema,
  topUpTransactionSchema,
  multiSendTransactionSchema,
]);
export type WalletTransaction = z.infer<typeof walletTransactionSchema>;

/**
 * Capability-based token assessment (PRD §19.16 override): a token may be both
 * tradable and burnable (DUST4), so classification is not a single exclusive enum.
 */
export const tokenAssessmentSchema = z.object({
  riskState: z.enum(["VERIFIED", "UNKNOWN"]),
  capabilities: z.object({
    tradable: z.boolean(),
    transferable: z.boolean(),
    burnable: z.boolean(),
  }),
  failureReasons: z.array(z.string()),
});
export type TokenAssessment = z.infer<typeof tokenAssessmentSchema>;
