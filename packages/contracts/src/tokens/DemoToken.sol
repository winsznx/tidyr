// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply TIDYR demonstration token (DUST1/DUST2/DUST3/DUST5). The full
/// 1,000,000-token supply mints to the deployer at construction; there is no `mint`
/// function, so supply can never change after deployment (PRD §3: "no owner mint after
/// deployment unless the PRD explicitly requires it" — it doesn't, for these).
contract DemoToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 ether;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
