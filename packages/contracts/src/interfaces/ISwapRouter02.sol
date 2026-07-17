// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal SwapRouter02 interface (no `deadline` field - this is the "02"
/// generation router, distinct from the original SwapRouter). Verified against the live
/// deployed bytecode at 0xfE31F71C1B106EAC32F1a19239c9A9A72DDfB900 on Monad mainnet: the
/// no-deadline `exactInput` selector 0xb858183f and `exactInputSingle` selector
/// 0x04e45aaf are both present; the old deadline-inclusive `exactInput` selector
/// 0xc04b8d59 is absent. See docs/research/external-addresses.md.
interface ISwapRouter02 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
