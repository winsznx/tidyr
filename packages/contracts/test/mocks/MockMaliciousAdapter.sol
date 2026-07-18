// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAdapter} from "../../src/interfaces/IAdapter.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Test-only adapter exercising malicious-adapter behaviors that a real
/// deployed adapter (accidentally or maliciously) could exhibit, distinct from
/// MockAdapter's simple mode-based delivery ratios. Never reachable via a real
/// SweepPlan against a production SweepExecutor (Codex addendum re-audit finding
/// RA-01) - only reachable in tests that wire it directly into a throwaway
/// SweepExecutor's constructor slot. Phase 7 Task 7.6.
contract MockMaliciousAdapter is IAdapter {
    enum Mode {
        EXCESS_PULL, // attempts to pull more than `amountIn` from the caller
        SEND_ELSEWHERE, // mints the output to itself instead of the caller
        UNDER_DELIVER_AFTER_PARTIAL_MUTATION // pulls input, then reverts after mutating its own state
    }

    Mode public mode;
    uint256 public mutatedState;

    error ForcedRevertAfterMutation();

    function setMode(Mode m) external {
        mode = m;
    }

    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minAmountOut, uint256, bytes calldata)
        external
        returns (uint256 amountOut)
    {
        if (mode == Mode.EXCESS_PULL) {
            // Only ever succeeds if the caller's approval is loose enough to allow it -
            // proves forceApprove's exact-amount approval (not unlimited) is what
            // actually blocks this, not adapter goodwill.
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn + 1);
            amountOut = minAmountOut;
            MockERC20(tokenOut).mint(msg.sender, amountOut);
            return amountOut;
        }

        if (mode == Mode.SEND_ELSEWHERE) {
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
            // Mints the "output" to itself, not msg.sender (the executor) - the
            // executor's balance-delta accounting must see zero output and reject.
            MockERC20(tokenOut).mint(address(this), minAmountOut);
            return minAmountOut;
        }

        // UNDER_DELIVER_AFTER_PARTIAL_MUTATION
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        mutatedState += 1;
        revert ForcedRevertAfterMutation();
    }
}
