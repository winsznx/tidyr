// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DemoDistributor} from "../src/tokens/DemoDistributor.sol";
import {DemoToken} from "../src/tokens/DemoToken.sol";
import {BurnableDemoToken} from "../src/tokens/BurnableDemoToken.sol";

contract DemoDistributorTest is Test {
    DemoToken internal dust1;
    DemoToken internal dust2;
    DemoToken internal dust3;
    BurnableDemoToken internal dust4;
    DemoToken internal dust5;
    DemoDistributor internal distributor;

    address internal owner = address(0xABCD);
    address internal claimant = address(0xF00D);

    function setUp() public {
        dust1 = new DemoToken("TIDYR Dust 1", "DUST1");
        dust2 = new DemoToken("TIDYR Dust 2", "DUST2");
        dust3 = new DemoToken("TIDYR Dust 3", "DUST3");
        dust4 = new BurnableDemoToken("TIDYR Dust 4", "DUST4");
        dust5 = new DemoToken("TIDYR Dust 5", "DUST5");

        IERC20[5] memory tokens = [
            IERC20(address(dust1)),
            IERC20(address(dust2)),
            IERC20(address(dust3)),
            IERC20(address(dust4)),
            IERC20(address(dust5))
        ];
        distributor = new DemoDistributor(tokens, owner);

        dust1.transfer(address(distributor), 1_000 ether);
        dust2.transfer(address(distributor), 1_000 ether);
        dust3.transfer(address(distributor), 1_000 ether);
        dust4.transfer(address(distributor), 1_000 ether);
        dust5.transfer(address(distributor), 1_000 ether);
    }

    function test_claimDemoBundle_transfersAllFiveTokens() public {
        vm.prank(claimant);
        distributor.claimDemoBundle();

        assertEq(dust1.balanceOf(claimant), 200 ether);
        assertEq(dust2.balanceOf(claimant), 200 ether);
        assertEq(dust3.balanceOf(claimant), 200 ether);
        assertEq(dust4.balanceOf(claimant), 200 ether);
        assertEq(dust5.balanceOf(claimant), 200 ether);
        assertTrue(distributor.claimed(claimant));
    }

    function test_secondClaim_reverts() public {
        vm.prank(claimant);
        distributor.claimDemoBundle();

        vm.prank(claimant);
        vm.expectRevert(DemoDistributor.AlreadyClaimed.selector);
        distributor.claimDemoBundle();
    }

    function test_freshWallet_canClaim() public {
        address fresh = address(0x1234);
        assertFalse(distributor.claimed(fresh));

        vm.prank(fresh);
        distributor.claimDemoBundle();

        assertEq(dust1.balanceOf(fresh), 200 ether);
    }

    /// @dev Inventory depletion must fail honestly (whole claim reverts), never a
    /// silent partial distribution. 1000 ether / 200 ether per claim = exactly 5 claims
    /// of inventory; a 6th claimant must revert entirely rather than receive a partial
    /// or short bundle.
    function test_insufficientInventory_revertsEntireClaim() public {
        for (uint256 i = 0; i < 5; i++) {
            address claimant_i = address(uint160(1000 + i));
            vm.prank(claimant_i);
            distributor.claimDemoBundle();
        }

        address sixthClaimant = address(uint160(2000));
        vm.prank(sixthClaimant);
        vm.expectRevert();
        distributor.claimDemoBundle();

        // The failed claim must not have been recorded as claimed (whole tx reverted).
        assertFalse(distributor.claimed(sixthClaimant));
        assertEq(dust1.balanceOf(sixthClaimant), 0);
    }

    function test_pause_blocksClaims() public {
        vm.prank(owner);
        distributor.pause();

        vm.prank(claimant);
        vm.expectRevert();
        distributor.claimDemoBundle();
    }

    function test_unpause_allowsClaimsAgain() public {
        vm.prank(owner);
        distributor.pause();
        vm.prank(owner);
        distributor.unpause();

        vm.prank(claimant);
        distributor.claimDemoBundle();
        assertTrue(distributor.claimed(claimant));
    }

    function test_onlyOwner_canPause() public {
        vm.expectRevert();
        distributor.pause();
    }

    function test_constructor_rejectsZeroAddressToken() public {
        IERC20[5] memory tokens = [
            IERC20(address(dust1)),
            IERC20(address(0)),
            IERC20(address(dust3)),
            IERC20(address(dust4)),
            IERC20(address(dust5))
        ];
        vm.expectRevert(DemoDistributor.ZeroAddress.selector);
        new DemoDistributor(tokens, owner);
    }
}
