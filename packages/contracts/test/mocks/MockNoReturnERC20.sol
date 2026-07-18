// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Test-only ERC20 that mimics USDT-style non-compliant tokens: `transfer`/
/// `transferFrom`/`approve` return no value at all (not even `bool`). `SafeERC20`
/// handles this via low-level call + optional-return-data decoding rather than a
/// direct interface call, which would revert on missing return data. Phase 7 Task 7.6.
contract MockNoReturnERC20 {
    string public name = "NoReturn";
    string public symbol = "NORET";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}
