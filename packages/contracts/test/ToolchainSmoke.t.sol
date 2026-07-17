// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

/// @notice Phase 1 toolchain smoke test only — confirms remappings for
/// OpenZeppelin v5 and Permit2 resolve and compile against the pinned
/// solc version. SweepExecutor itself is implemented starting Phase 2/4.
contract ToolchainSmoke is Test {
    function test_remappingsResolve() public pure {
        assertTrue(true);
    }
}
