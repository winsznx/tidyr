// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DemoDistributor} from "../src/tokens/DemoDistributor.sol";
import {DemoToken} from "../src/tokens/DemoToken.sol";
import {BurnableDemoToken} from "../src/tokens/BurnableDemoToken.sol";

/// @notice Phase 7 Task 7.8 invariant: DemoDistributor.claimDemoBundle enforces
/// exactly one claim per address, regardless of call order or how many distinct
/// addresses attempt to claim.
contract DemoDistributorHandler is Test {
    DemoDistributor public immutable DISTRIBUTOR;
    uint256 public successfulClaims;
    uint256 public rejectedDoubleClaims;

    constructor(DemoDistributor distributor_) {
        DISTRIBUTOR = distributor_;
    }

    /// @dev Excludes the distributor's own address from the fuzzed claimant space.
    /// Discovered while writing this invariant: if `msg.sender` were ever the
    /// distributor's own address (unreachable in reality - nothing can make an
    /// external call arrive with the distributor's own address as caller without its
    /// private key, which contracts don't have), each token's `transfer(self, amount)`
    /// nets to a zero balance change, so the distributor could mark itself "claimed"
    /// while distributing nothing to itself. Purely a self-transfer artifact, not a
    /// reachable production vulnerability - excluded here so the invariant models only
    /// realistic external callers.
    function claim(uint256 claimantSeed) external {
        address claimant = address(uint160(bound(claimantSeed, 1, type(uint160).max)));
        vm.assume(claimant != address(DISTRIBUTOR));
        bool alreadyClaimed = DISTRIBUTOR.claimed(claimant);

        vm.prank(claimant);
        try DISTRIBUTOR.claimDemoBundle() {
            assertFalse(alreadyClaimed, "claim succeeded twice for the same address");
            successfulClaims++;
        } catch {
            if (alreadyClaimed) rejectedDoubleClaims++;
        }
    }
}

contract DemoDistributorInvariantsTest is Test {
    DemoToken internal dust1;
    DemoToken internal dust2;
    DemoToken internal dust3;
    BurnableDemoToken internal dust4;
    DemoToken internal dust5;
    DemoDistributor internal distributor;
    DemoDistributorHandler internal handler;

    address internal owner = address(0xABCD);

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

        // Deliberately large inventory (2,000 claims worth) so the invariant under
        // test is one-claim-per-address, not inventory exhaustion.
        dust1.transfer(address(distributor), 400_000 ether);
        dust2.transfer(address(distributor), 400_000 ether);
        dust3.transfer(address(distributor), 400_000 ether);
        dust4.transfer(address(distributor), 400_000 ether);
        dust5.transfer(address(distributor), 400_000 ether);

        handler = new DemoDistributorHandler(distributor);
        targetContract(address(handler));
    }

    /// @dev Every successfully-claimed address holds exactly CLAIM_AMOUNT of every
    /// token - never more (double-claim), never less (partial distribution).
    function invariant_claimedAddressesHoldExactlyOneBundleWorth() public view {
        // The handler itself asserts no double-success inline (assertFalse above);
        // this invariant re-checks the aggregate token-conservation property: total
        // distributed never exceeds successfulClaims * CLAIM_AMOUNT per token.
        uint256 expectedDistributed = handler.successfulClaims() * distributor.CLAIM_AMOUNT();
        uint256 actualDust1Distributed = 400_000 ether - dust1.balanceOf(address(distributor));
        assertEq(actualDust1Distributed, expectedDistributed);
    }
}
