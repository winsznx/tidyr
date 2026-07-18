// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Test-only contract with no `receive`/`payable fallback` - any native MON
/// sent to it reverts. Phase 7 Task 7.6/threat model: proves a plan whose recipient
/// cannot accept native MON output fails atomically (`NativeTransferFailed`, whole
/// `executeSweep` reverts) rather than losing or stranding the swept funds.
contract MockRevertingRecipient {}
