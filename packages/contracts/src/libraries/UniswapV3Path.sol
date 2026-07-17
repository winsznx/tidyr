// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal Uniswap V3 packed-path decoding: `token(20) | fee(3) | token(20) | fee(3) | token(20) ...`.
/// `toAddress` is the standard BytesLib-style extraction used by Uniswap's own
/// `Path.sol` - reimplemented locally to avoid an extra dependency for one function.
library UniswapV3Path {
    uint256 internal constant ADDR_SIZE = 20;
    uint256 internal constant FEE_SIZE = 3;
    uint256 internal constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;

    error MalformedPath();

    function numHops(bytes memory path) internal pure returns (uint256) {
        if (path.length < ADDR_SIZE + FEE_SIZE + ADDR_SIZE) revert MalformedPath();
        if ((path.length - ADDR_SIZE) % NEXT_OFFSET != 0) revert MalformedPath();
        return (path.length - ADDR_SIZE) / NEXT_OFFSET;
    }

    function tokenAt(bytes memory path, uint256 hopIndex) internal pure returns (address token) {
        uint256 offset = hopIndex * NEXT_OFFSET;
        if (path.length < offset + ADDR_SIZE) revert MalformedPath();
        assembly {
            token := div(mload(add(add(path, 0x20), offset)), 0x1000000000000000000000000)
        }
    }
}
