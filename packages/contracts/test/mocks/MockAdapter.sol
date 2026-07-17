// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAdapter} from "../../src/interfaces/IAdapter.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Test-only controllable adapter for exercising SweepExecutor's handling of
/// adapter results in isolation from any real DEX (PancakeV2Adapter/UniswapV3Adapter get
/// their own dedicated tests in Phase 5). Pulls `amountIn` of `tokenIn` from the caller
/// (already approved) and mints/settles a configured amount of `tokenOut`.
contract MockAdapter is IAdapter {
    enum Mode {
        NORMAL, // mints exactly the configured output ratio
        REVERT, // always reverts (simulates a DEX rejecting for insufficient output)
        UNDER_DELIVER // mints less than minAmountOut without reverting (malicious adapter)
    }

    Mode public mode = Mode.NORMAL;
    /// @dev amountOut = amountIn * outputNumerator / outputDenominator
    uint256 public outputNumerator = 1;
    uint256 public outputDenominator = 1;

    function setMode(Mode m) external {
        mode = m;
    }

    function setRatio(uint256 numerator, uint256 denominator) external {
        outputNumerator = numerator;
        outputDenominator = denominator;
    }

    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minAmountOut, uint256, bytes calldata)
        external
        returns (uint256 amountOut)
    {
        if (mode == Mode.REVERT) revert("MockAdapter: forced revert");

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        if (mode == Mode.UNDER_DELIVER) {
            amountOut = minAmountOut > 0 ? minAmountOut - 1 : 0;
        } else {
            amountOut = (amountIn * outputNumerator) / outputDenominator;
        }

        MockERC20(tokenOut).mint(msg.sender, amountOut);
        return amountOut;
    }
}
