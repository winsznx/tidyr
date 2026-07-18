// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test-only ERC20 that burns a configurable basis-point fee on every
/// `transfer`/`transferFrom`, so the recipient receives strictly less than the amount
/// requested - the deflationary/fee-on-transfer footgun. Phase 7 Task 7.6: proves
/// SweepExecutor's `UnexpectedPulledAmount` check (comparing the exact Permit2-
/// requested amount against the measured balance delta) correctly rejects this token
/// as a swap/transfer input rather than silently under-crediting the plan.
contract MockFeeOnTransferERC20 is ERC20 {
    uint256 public feeBps;

    constructor(string memory name_, string memory symbol_, uint256 feeBps_) ERC20(name_, symbol_) {
        feeBps = feeBps_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferWithFee(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transferWithFee(from, to, amount);
        return true;
    }

    function _transferWithFee(address from, address to, uint256 amount) private {
        uint256 fee = (amount * feeBps) / 10_000;
        super._update(from, address(0), fee);
        super._update(from, to, amount - fee);
    }
}
