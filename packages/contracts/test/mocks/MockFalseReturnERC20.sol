// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Test-only ERC20 that mutates balances correctly but returns `false` from
/// both `transfer` and `transferFrom` instead of reverting on failure - the classic
/// non-compliant-token footgun `SafeERC20` exists to catch. Phase 7 Task 7.6: proves
/// `forceApprove`/`safeTransfer`/`safeTransferFrom` in SweepExecutor and the adapters
/// correctly treat a `false` return as failure rather than silently trusting it.
contract MockFalseReturnERC20 {
    string public name = "FalseReturn";
    string public symbol = "FALSE";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @dev Mutates state (so a caller checking balances directly would be fooled) but
    /// always reports failure via return value.
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return false;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return false;
    }
}
