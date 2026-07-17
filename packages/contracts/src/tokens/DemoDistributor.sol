// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DemoDistributor
/// @notice Lets judges/testers claim one bundle of all five TIDYR demo tokens. Holds
/// only pre-funded demo inventory transferred to it once at deployment - never receives
/// arbitrary user funds, so it has no withdrawal function for the owner (PRD §19.15:
/// "no arbitrary withdrawal of user funds because it holds only demo inventory").
/// `pause` exists only for emergency inventory depletion or a token-level error, per
/// §19.15 - it never blocks anything other than new claims.
contract DemoDistributor is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant CLAIM_AMOUNT = 200 ether;

    IERC20[5] public tokens;
    mapping(address => bool) public claimed;

    event Claimed(address indexed claimant);

    error AlreadyClaimed();
    error ZeroAddress();

    constructor(IERC20[5] memory tokens_, address initialOwner_) Ownable(initialOwner_) {
        for (uint256 i = 0; i < 5; i++) {
            if (address(tokens_[i]) == address(0)) revert ZeroAddress();
        }
        tokens = tokens_;
    }

    /// @notice Transfers 200 of each of the five demo tokens to the caller. One claim
    /// per address, enforced before any external call (CEI). Reverts entirely (no
    /// partial distribution) if inventory for any token is insufficient - an honest
    /// failure rather than a silent short-claim.
    function claimDemoBundle() external whenNotPaused {
        if (claimed[msg.sender]) revert AlreadyClaimed();
        claimed[msg.sender] = true;

        for (uint256 i = 0; i < 5; i++) {
            tokens[i].safeTransfer(msg.sender, CLAIM_AMOUNT);
        }

        emit Claimed(msg.sender);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
