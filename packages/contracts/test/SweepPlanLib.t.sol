// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SweepPlanLib} from "../src/libraries/SweepPlanLib.sol";

/// @notice Phase 2 acceptance tests: hash correctness, sensitivity, and shape validation.
/// Cross-language golden values are recorded in test-vectors/golden-vectors.md and
/// asserted identically here and in packages/transaction-review's TS test.
contract SweepPlanLibTest is Test {
    address constant OWNER = 0x1111111111111111111111111111111111111111;
    address constant RECIPIENT = 0x2222222222222222222222222222222222222222;
    address constant OUTPUT_TOKEN = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603; // USDC (Monad)
    address constant TOKEN_IN = 0x3333333333333333333333333333333333333333;
    address constant ADAPTER = 0x4444444444444444444444444444444444444444;
    uint256 constant TEST_CHAIN_ID = 143; // Monad mainnet
    address constant TEST_EXECUTOR = 0x9999999999999999999999999999999999999999;

    /// @dev Golden vector A: one swap, one transfer, no discards/burns.
    /// Independently reproduced in packages/transaction-review/src/executionPlanHash.test.ts
    bytes32 constant VECTOR_A_EXPECTED_HASH =
        0xdf7a8dd0108003ffa8b036d6471d7a6479a56d02b6b7737737c398e3515100d1;

    function _vectorA() internal pure returns (SweepPlanLib.SweepPlan memory plan) {
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: TOKEN_IN,
            amountIn: 200 ether,
            adapter: ADAPTER,
            minAmountOut: 100,
            routeData: hex"1234",
            allowFailure: false
        });

        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: TOKEN_IN, amount: 50 ether, to: RECIPIENT});

        plan = SweepPlanLib.SweepPlan({
            owner: OWNER,
            recipient: RECIPIENT,
            outputToken: OUTPUT_TOKEN,
            deadline: 1_800_000_000,
            nonce: 0,
            displayManifestHash: keccak256("display-manifest-vector-a"),
            swaps: swaps,
            transfers: transfers,
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
    }

    function test_vectorA_hashIsDeterministic() public pure {
        bytes32 h1 = SweepPlanLib.hashPlan(_vectorA(), TEST_CHAIN_ID, TEST_EXECUTOR);
        bytes32 h2 = SweepPlanLib.hashPlan(_vectorA(), TEST_CHAIN_ID, TEST_EXECUTOR);
        assertEq(h1, h2);
    }

    /// @dev Prints the hash so it can be cross-checked against the TypeScript
    /// implementation's output for the identical vector (see test-vectors/golden-vectors.md).
    function test_vectorA_printHash() public pure {
        bytes32 h = SweepPlanLib.hashPlan(_vectorA(), TEST_CHAIN_ID, TEST_EXECUTOR);
        // forge test -vvvv will show this in the trace; also asserted below.
        assertEq(h, VECTOR_A_EXPECTED_HASH, "vector A hash must match recorded golden value");
    }

    function test_amountChangesHash() public pure {
        SweepPlanLib.SweepPlan memory a = _vectorA();
        SweepPlanLib.SweepPlan memory b = _vectorA();
        b.swaps[0].amountIn = 201 ether;
        assertTrue(SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR) != SweepPlanLib.hashPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR));
    }

    function test_recipientChangesHash() public pure {
        SweepPlanLib.SweepPlan memory a = _vectorA();
        SweepPlanLib.SweepPlan memory b = _vectorA();
        b.recipient = 0x5555555555555555555555555555555555555555;
        assertTrue(SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR) != SweepPlanLib.hashPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR));
    }

    function test_outputTokenChangesHash() public pure {
        SweepPlanLib.SweepPlan memory a = _vectorA();
        SweepPlanLib.SweepPlan memory b = _vectorA();
        b.outputToken = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A; // WMON instead of USDC
        assertTrue(SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR) != SweepPlanLib.hashPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR));
    }

    function test_deadlineChangesHash() public pure {
        SweepPlanLib.SweepPlan memory a = _vectorA();
        SweepPlanLib.SweepPlan memory b = _vectorA();
        b.deadline = a.deadline + 1;
        assertTrue(SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR) != SweepPlanLib.hashPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR));
    }

    function test_nonceChangesHash() public pure {
        SweepPlanLib.SweepPlan memory a = _vectorA();
        SweepPlanLib.SweepPlan memory b = _vectorA();
        b.nonce = a.nonce + 1;
        assertTrue(SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR) != SweepPlanLib.hashPlan(b, TEST_CHAIN_ID, TEST_EXECUTOR));
    }

    /// @dev Swapping the order of two swap actions must change the hash — proves the
    /// per-element array hashing is order-sensitive, not a commutative aggregate.
    function test_actionOrderChangesHash() public pure {
        SweepPlanLib.SweepPlan memory a = _vectorA();

        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](2);
        swaps[0] = a.swaps[0];
        swaps[1] = SweepPlanLib.SwapAction({
            tokenIn: TOKEN_IN,
            amountIn: 10 ether,
            adapter: ADAPTER,
            minAmountOut: 1,
            routeData: hex"56",
            allowFailure: true
        });
        a.swaps = swaps;
        bytes32 forwardHash = SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR);

        SweepPlanLib.SwapAction[] memory reversed = new SweepPlanLib.SwapAction[](2);
        reversed[0] = swaps[1];
        reversed[1] = swaps[0];
        a.swaps = reversed;
        bytes32 reversedHash = SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR);

        assertTrue(forwardHash != reversedHash);
    }

    /// @dev displayManifestHash is one input among many to executionPlanHash, but the
    /// two hashes must never be the same value for the same logical plan (§19.3).
    function test_executionHashDiffersFromDisplayManifestHash() public pure {
        SweepPlanLib.SweepPlan memory a = _vectorA();
        bytes32 executionHash = SweepPlanLib.hashPlan(a, TEST_CHAIN_ID, TEST_EXECUTOR);
        assertTrue(executionHash != a.displayManifestHash);
    }

    function test_emptyPlanReverts() public {
        SweepPlanLib.SweepPlan memory plan = _vectorA();
        plan.swaps = new SweepPlanLib.SwapAction[](0);
        plan.transfers = new SweepPlanLib.TransferAction[](0);

        vm.expectRevert(abi.encodeWithSelector(SweepPlanLib.EmptyPlan.selector));
        this.validateExternal(plan);
    }

    function test_oversizedPlanReverts() public {
        SweepPlanLib.SweepPlan memory plan = _vectorA();
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](50);
        for (uint256 i = 0; i < 50; i++) {
            transfers[i] = SweepPlanLib.TransferAction({token: TOKEN_IN, amount: 1, to: RECIPIENT});
        }
        plan.transfers = transfers; // 1 swap + 50 transfers = 51 > MAX_ACTIONS

        vm.expectRevert(
            abi.encodeWithSelector(SweepPlanLib.TooManyActions.selector, uint256(51), SweepPlanLib.MAX_ACTIONS)
        );
        this.validateExternal(plan);
    }

    function test_exactlyMaxActionsAccepted() public view {
        SweepPlanLib.SweepPlan memory plan = _vectorA();
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](49);
        for (uint256 i = 0; i < 49; i++) {
            transfers[i] = SweepPlanLib.TransferAction({token: TOKEN_IN, amount: 1, to: RECIPIENT});
        }
        plan.transfers = transfers; // 1 swap + 49 transfers = 50 == MAX_ACTIONS
        this.validateExternal(plan);
    }

    /// @dev calldata-only library functions require an external call boundary from a
    /// `memory`-constructed test fixture.
    function validateExternal(SweepPlanLib.SweepPlan calldata plan) external pure {
        SweepPlanLib.validatePlanShape(plan);
    }
}
