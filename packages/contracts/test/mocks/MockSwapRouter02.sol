// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter02} from "../../src/interfaces/ISwapRouter02.sol";
import {UniswapV3Path} from "../../src/libraries/UniswapV3Path.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Test-only controllable SwapRouter02 stand-in, mirroring MockAdapter's shape
/// (Normal/Revert/UnderDeliver) so UniswapV3Adapter's handling of router results can be
/// tested independently of a real Uniswap V3 pool.
contract MockSwapRouter02 is ISwapRouter02 {
    using UniswapV3Path for bytes;

    enum Mode {
        NORMAL,
        REVERT,
        UNDER_DELIVER
    }

    Mode public mode = Mode.NORMAL;
    uint256 public outputNumerator = 1;
    uint256 public outputDenominator = 1;

    function setMode(Mode m) external {
        mode = m;
    }

    function setRatio(uint256 numerator, uint256 denominator) external {
        outputNumerator = numerator;
        outputDenominator = denominator;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {
        if (mode == Mode.REVERT) revert("MockSwapRouter02: forced revert");

        uint256 hops = params.path.numHops();
        address tokenIn = params.path.tokenAt(0);
        address tokenOut = params.path.tokenAt(hops);

        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        if (mode == Mode.UNDER_DELIVER) {
            amountOut = params.amountOutMinimum > 0 ? params.amountOutMinimum - 1 : 0;
        } else {
            amountOut = (params.amountIn * outputNumerator) / outputDenominator;
        }

        MockERC20(tokenOut).mint(params.recipient, amountOut);
    }
}
