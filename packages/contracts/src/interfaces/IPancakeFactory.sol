// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal PancakeSwap V2 factory interface. Verified on Monad mainnet at
/// 0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E (see docs/research/external-addresses.md).
/// No classic Router exists on Monad (conflict C-1) - PancakeV2Adapter reads pairs
/// directly from this factory instead.
interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
