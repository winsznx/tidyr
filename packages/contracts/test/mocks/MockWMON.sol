// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWMON} from "../../src/interfaces/IWMON.sol";

/// @notice Test-only WMON stand-in implementing the same deposit/withdraw shape as the
/// verified canonical WMON at 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A. Adds a `mint`
/// convenience for tests that need to simulate an adapter settling WMON without routing
/// real native MON through a swap - the test must ensure this contract holds enough
/// native MON (`vm.deal`) to honor any `withdraw` the minted supply implies.
contract MockWMON is ERC20, IWMON {
    constructor() ERC20("Wrapped Monad", "WMON") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "MockWMON: native transfer failed");
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    receive() external payable {}
}
