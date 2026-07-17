// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MockERC20} from "./MockERC20.sol";

/// @notice Test-only ERC20 with `burn(uint256)`, standing in for DUST4.
contract MockBurnableERC20 is MockERC20 {
    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_) {}

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
