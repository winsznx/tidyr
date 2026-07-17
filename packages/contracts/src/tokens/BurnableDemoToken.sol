// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @notice Fixed-supply TIDYR demonstration token with `burn(uint256)` (DUST4). Same
/// fixed-supply-at-construction, no-further-mint policy as DemoToken; adds OpenZeppelin's
/// audited `ERC20Burnable` (burns the caller's own balance, or another account's balance
/// with sufficient allowance - standard OZ semantics, nothing custom).
contract BurnableDemoToken is ERC20, ERC20Burnable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 ether;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
