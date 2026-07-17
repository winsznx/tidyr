// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DemoToken} from "../src/tokens/DemoToken.sol";
import {BurnableDemoToken} from "../src/tokens/BurnableDemoToken.sol";

contract DemoTokenTest is Test {
    function test_fixedSupply_mintedToDeployer() public {
        DemoToken token = new DemoToken("TIDYR Dust 1", "DUST1");
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(token.balanceOf(address(this)), 1_000_000 ether);
    }

    function test_noMintFunctionExists() public {
        // Compile-time guarantee: DemoToken has no `mint` selector at all. This is a
        // documentation test - if a future edit added one, this assertion would need
        // updating, making the change visible in review.
        DemoToken token = new DemoToken("TIDYR Dust 2", "DUST2");
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", address(this), 1));
        assertFalse(ok, "DemoToken must not expose a mint function");
    }

    function test_burnableDemoToken_fixedSupply() public {
        BurnableDemoToken token = new BurnableDemoToken("TIDYR Dust 4", "DUST4");
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(token.balanceOf(address(this)), 1_000_000 ether);
    }

    function test_burnableDemoToken_burnReducesBalanceAndSupply() public {
        BurnableDemoToken token = new BurnableDemoToken("TIDYR Dust 4", "DUST4");
        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(address(this));

        token.burn(100 ether);

        assertEq(token.totalSupply(), supplyBefore - 100 ether);
        assertEq(token.balanceOf(address(this)), balBefore - 100 ether);
    }

    function test_burnableDemoToken_burnMoreThanBalance_reverts() public {
        BurnableDemoToken token = new BurnableDemoToken("TIDYR Dust 4", "DUST4");
        uint256 excessive = token.balanceOf(address(this)) + 1;
        vm.expectRevert();
        token.burn(excessive);
    }

    function test_standardToken_isFreelyTransferable() public {
        // DUST5 is the same contract shape as DUST1-3; "no pool" is purely a liquidity
        // decision made at deployment time (Phase 8/10), not a contract-level restriction.
        DemoToken dust5 = new DemoToken("TIDYR Dust 5", "DUST5");
        address recipient = address(0xBEEF);
        dust5.transfer(recipient, 500 ether);
        assertEq(dust5.balanceOf(recipient), 500 ether);
    }
}
