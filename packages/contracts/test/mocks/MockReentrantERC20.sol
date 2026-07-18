// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SweepExecutor} from "../../src/SweepExecutor.sol";

/// @notice Test-only ERC20 that attempts to re-enter `SweepExecutor.recoverStrayTokens`
/// from inside its own `transfer` hook - simulating a malicious/compromised token
/// callback (comparable to ERC-777 hooks) rather than a malicious adapter. Phase 7
/// Task 7.6: proves `nonReentrant` blocks reentrancy that originates from a token
/// transfer during action execution, not just from an adapter's own callback.
contract MockReentrantERC20 is ERC20 {
    SweepExecutor public immutable EXECUTOR;
    bool public armed;

    constructor(SweepExecutor executor_) ERC20("ReentrantToken", "REENT") {
        EXECUTOR = executor_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm() external {
        armed = true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _maybeReenter();
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _maybeReenter();
        return super.transferFrom(from, to, amount);
    }

    function _maybeReenter() private {
        if (armed) {
            armed = false;
            EXECUTOR.recoverStrayTokens(address(this), 0, address(this));
        }
    }
}
