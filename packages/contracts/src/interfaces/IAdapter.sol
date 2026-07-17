// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Interface every SweepExecutor-registered swap adapter must implement.
/// @dev Adapters never hold funds between calls and always settle output back to
/// `msg.sender` (the executor), which enforces `minAmountOut` itself via balance deltas
/// (PRD §5.4, §19.9) rather than trusting this function's return value.
interface IAdapter {
    /// @param tokenIn token the executor has already approved this adapter to pull
    /// @param amountIn exact amount to pull and swap
    /// @param tokenOut expected settlement token (WMON or the plan's outputToken)
    /// @param minAmountOut adapter must revert its own underlying swap if not met
    /// @param deadline swap-level deadline (may differ from the plan's own deadline)
    /// @param routeData adapter-specific path/route encoding
    /// @return amountOut observational only - the executor never trusts this value
    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 deadline,
        bytes calldata routeData
    ) external returns (uint256 amountOut);
}
