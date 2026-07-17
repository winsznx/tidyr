// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Action and plan structs plus deterministic hashing for TIDYR sweep plans.
/// @dev Reflects PRD Section 19 Mandatory Implementation Addendum: no executor-side
/// RevokeAction (§19.2), and `executionPlanHash` is distinct from the frontend's
/// `displayManifestHash` (§19.3). This library only defines shape and hashing — plan
/// authorization and execution live in SweepExecutor (Phase 4).
library SweepPlanLib {
    /// @dev Total action count bound enforced by SweepExecutor; kept here so
    /// `validatePlanShape` can be exercised independently of the executor.
    uint256 internal constant MAX_ACTIONS = 50;

    struct SwapAction {
        address tokenIn;
        uint256 amountIn;
        address adapter;
        uint256 minAmountOut;
        bytes routeData;
        bool allowFailure;
    }

    struct TransferAction {
        address token;
        uint256 amount;
        address to;
    }

    struct DiscardAction {
        address token;
        uint256 amount;
    }

    struct BurnAction {
        address token;
        uint256 amount;
    }

    /// @dev No `revocations` field — revocations are direct EOA transactions (§19.2).
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

    error EmptyPlan();
    error TooManyActions(uint256 total, uint256 max);

    function totalActions(SweepPlan memory plan) internal pure returns (uint256) {
        return plan.swaps.length + plan.transfers.length + plan.discards.length + plan.burns.length;
    }

    /// @notice Reverts unless the plan has between 1 and MAX_ACTIONS actions inclusive.
    function validatePlanShape(SweepPlan memory plan) internal pure {
        uint256 total = totalActions(plan);
        if (total == 0) revert EmptyPlan();
        if (total > MAX_ACTIONS) revert TooManyActions(total, MAX_ACTIONS);
    }

    /// @notice Deterministic hash of the on-chain-executed plan fields. Distinct from
    /// `displayManifestHash`, which hashes the frontend's RFC 8785 canonical JSON.
    /// Dynamic arrays are hashed element-wise (hash each action, then hash the array of
    /// hashes) rather than relying on a single `abi.encode(plan)` call, so that nested
    /// dynamic `bytes` fields (SwapAction.routeData) cannot introduce encoding ambiguity.
    function hashPlan(SweepPlan memory plan) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                plan.owner,
                plan.recipient,
                plan.outputToken,
                plan.deadline,
                plan.nonce,
                plan.displayManifestHash,
                _hashSwapActions(plan.swaps),
                _hashTransferActions(plan.transfers),
                _hashDiscardActions(plan.discards),
                _hashBurnActions(plan.burns)
            )
        );
    }

    function _hashSwapActions(SwapAction[] memory actions) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](actions.length);
        for (uint256 i = 0; i < actions.length; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    actions[i].tokenIn,
                    actions[i].amountIn,
                    actions[i].adapter,
                    actions[i].minAmountOut,
                    keccak256(actions[i].routeData),
                    actions[i].allowFailure
                )
            );
        }
        return keccak256(abi.encode(hashes));
    }

    function _hashTransferActions(TransferAction[] memory actions) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](actions.length);
        for (uint256 i = 0; i < actions.length; i++) {
            hashes[i] = keccak256(abi.encode(actions[i].token, actions[i].amount, actions[i].to));
        }
        return keccak256(abi.encode(hashes));
    }

    function _hashDiscardActions(DiscardAction[] memory actions) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](actions.length);
        for (uint256 i = 0; i < actions.length; i++) {
            hashes[i] = keccak256(abi.encode(actions[i].token, actions[i].amount));
        }
        return keccak256(abi.encode(hashes));
    }

    function _hashBurnActions(BurnAction[] memory actions) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](actions.length);
        for (uint256 i = 0; i < actions.length; i++) {
            hashes[i] = keccak256(abi.encode(actions[i].token, actions[i].amount));
        }
        return keccak256(abi.encode(hashes));
    }
}
