// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPancakePair} from "../../src/interfaces/IPancakePair.sol";

/// @notice Test-only V2-style pair: real reserve accounting and constant-product
/// settlement behavior (transfers requested output, then recomputes reserves from
/// actual balances - exactly like the real PancakeSwap/Uniswap V2 pair does), but
/// without the real contract's `k`-invariant enforcement, since that's PancakeSwap's own
/// audited code and not what PancakeV2Adapter's tests are verifying.
contract MockPancakePair is IPancakePair {
    address public immutable token0;
    address public immutable token1;
    uint112 private _reserve0;
    uint112 private _reserve1;

    constructor(address tokenA, address tokenB) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @dev Test setup must have already transferred matching token balances to this pair.
    function seedReserves(uint112 reserve0_, uint112 reserve1_) external {
        _reserve0 = reserve0_;
        _reserve1 = reserve1_;
    }

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (_reserve0, _reserve1, uint32(block.timestamp));
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external {
        if (amount0Out > 0) IERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transfer(to, amount1Out);
        _reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        _reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
    }
}
