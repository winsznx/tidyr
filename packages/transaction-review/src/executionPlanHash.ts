import { encodeAbiParameters, keccak256, type Hex } from "viem";
import type {
  BurnAction,
  DiscardAction,
  SweepPlan,
  SwapAction,
  TransferAction,
} from "@tidyr/shared";

/**
 * Mirrors packages/contracts/src/libraries/SweepPlanLib.sol `hashPlan` field-for-field
 * and byte-for-byte. Any change here must be mirrored there and re-verified against
 * test-vectors/golden-vectors.md. Distinct from `displayManifestHash`
 * (./displayManifestHash.ts) — see PRD §19.3.
 */

function hashSwapActions(actions: readonly SwapAction[]): Hex {
  const hashes = actions.map((a) =>
    keccak256(
      encodeAbiParameters(
        [
          { type: "address" },
          { type: "uint256" },
          { type: "address" },
          { type: "uint256" },
          { type: "bytes32" },
          { type: "bool" },
        ],
        [a.tokenIn, a.amountIn, a.adapter, a.minAmountOut, keccak256(a.routeData), a.allowFailure],
      ),
    ),
  );
  return keccak256(encodeAbiParameters([{ type: "bytes32[]" }], [hashes]));
}

function hashTransferActions(actions: readonly TransferAction[]): Hex {
  const hashes = actions.map((a) =>
    keccak256(
      encodeAbiParameters(
        [{ type: "address" }, { type: "uint256" }, { type: "address" }],
        [a.token, a.amount, a.to],
      ),
    ),
  );
  return keccak256(encodeAbiParameters([{ type: "bytes32[]" }], [hashes]));
}

function hashDiscardActions(actions: readonly DiscardAction[]): Hex {
  const hashes = actions.map((a) =>
    keccak256(encodeAbiParameters([{ type: "address" }, { type: "uint256" }], [a.token, a.amount])),
  );
  return keccak256(encodeAbiParameters([{ type: "bytes32[]" }], [hashes]));
}

function hashBurnActions(actions: readonly BurnAction[]): Hex {
  const hashes = actions.map((a) =>
    keccak256(encodeAbiParameters([{ type: "address" }, { type: "uint256" }], [a.token, a.amount])),
  );
  return keccak256(encodeAbiParameters([{ type: "bytes32[]" }], [hashes]));
}

/** Deterministic hash of the on-chain-executed plan fields (`executionPlanHash`). */
export function hashExecutionPlan(plan: SweepPlan): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "address" }, // owner
        { type: "address" }, // recipient
        { type: "address" }, // outputToken
        { type: "uint256" }, // deadline
        { type: "uint256" }, // nonce
        { type: "bytes32" }, // displayManifestHash
        { type: "bytes32" }, // hash of swaps
        { type: "bytes32" }, // hash of transfers
        { type: "bytes32" }, // hash of discards
        { type: "bytes32" }, // hash of burns
      ],
      [
        plan.owner,
        plan.recipient,
        plan.outputToken,
        plan.deadline,
        plan.nonce,
        plan.displayManifestHash,
        hashSwapActions(plan.swaps),
        hashTransferActions(plan.transfers),
        hashDiscardActions(plan.discards),
        hashBurnActions(plan.burns),
      ],
    ),
  );
}
