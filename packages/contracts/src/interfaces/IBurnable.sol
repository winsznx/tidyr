// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal interface for tokens supporting a self-balance burn, e.g. DUST4.
interface IBurnable {
    function burn(uint256 amount) external;
}
