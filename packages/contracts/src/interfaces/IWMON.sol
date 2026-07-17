// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Wrapped native MON, matching the canonical WETH9-style interface verified
/// on-chain at 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A (Monad mainnet).
interface IWMON is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
