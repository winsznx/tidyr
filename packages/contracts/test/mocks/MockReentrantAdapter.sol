// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAdapter} from "../../src/interfaces/IAdapter.sol";
import {SweepExecutor} from "../../src/SweepExecutor.sol";

/// @notice Test-only malicious adapter that tries to call back into SweepExecutor
/// mid-swap, proving `nonReentrant` blocks it (PRD §5.1, §19.10 recovery-during-
/// execution restriction).
contract MockReentrantAdapter is IAdapter {
    SweepExecutor public immutable EXECUTOR;

    constructor(SweepExecutor executor) {
        EXECUTOR = executor;
    }

    function swap(address, uint256, address, uint256, uint256, bytes calldata) external returns (uint256) {
        EXECUTOR.recoverStrayTokens(address(0x1), 0, address(this));
        return 0;
    }
}
