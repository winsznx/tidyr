// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SweepExecutor} from "../src/SweepExecutor.sol";
import {SweepPlanLib} from "../src/libraries/SweepPlanLib.sol";
import {TidyrWitness} from "../src/libraries/TidyrWitness.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWMON} from "./mocks/MockWMON.sol";
import {MockBurnableERC20} from "./mocks/MockBurnableERC20.sol";
import {MockAdapter} from "./mocks/MockAdapter.sol";
import {MockReentrantAdapter} from "./mocks/MockReentrantAdapter.sol";

contract SweepExecutorTest is Test {
    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    ISignatureTransfer internal permit2;
    SweepExecutor internal executor;
    MockWMON internal wmon;
    MockERC20 internal dust1;
    MockERC20 internal usdc;
    MockBurnableERC20 internal dust4;
    MockAdapter internal adapter;

    uint256 internal ownerKey = 0xA11CE;
    address internal owner;
    address internal recipient = address(0xBEEF);
    address internal executorOwner = address(0xE0E0);

    function setUp() public {
        permit2 = ISignatureTransfer(deployCode("Permit2.sol:Permit2"));
        wmon = new MockWMON();
        executor = new SweepExecutor(address(permit2), address(wmon), executorOwner);

        dust1 = new MockERC20("Dust1", "DUST1");
        usdc = new MockERC20("USD Coin", "USDC");
        dust4 = new MockBurnableERC20("Dust4", "DUST4");
        adapter = new MockAdapter();

        vm.startPrank(executorOwner);
        executor.registerAdapter(address(adapter));
        executor.registerOutputToken(address(usdc));
        vm.stopPrank();

        owner = vm.addr(ownerKey);
        dust1.mint(owner, 1_000 ether);
        dust4.mint(owner, 1_000 ether);

        vm.startPrank(owner);
        dust1.approve(address(permit2), type(uint256).max);
        dust4.approve(address(permit2), type(uint256).max);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------
    // Plan / signing helpers
    // -----------------------------------------------------------------

    function _emptyPlan(address outputToken) internal view returns (SweepPlanLib.SweepPlan memory plan) {
        plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: outputToken,
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: new SweepPlanLib.SwapAction[](0),
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
    }

    function _sign(SweepPlanLib.SweepPlan memory plan) internal view returns (bytes memory signature) {
        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);
        bytes32[] memory tokenPermissionHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPermissionHashes[i] =
                keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, tokens[i], amounts[i]));
        }

        bytes32 executionPlanHash = SweepPlanLib.hashPlan(plan);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_STUB, TidyrWitness.WITNESS_TYPE_STRING));

        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                address(executor), // spender is SweepExecutor itself
                plan.nonce,
                plan.deadline,
                witness
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        signature = bytes.concat(r, s, bytes1(v));
    }

    function _execute(SweepPlanLib.SweepPlan memory plan) internal returns (bytes32) {
        bytes memory sig = _sign(plan);
        vm.prank(owner);
        return executor.executeSweep(plan, sig);
    }

    // -----------------------------------------------------------------
    // Happy paths
    // -----------------------------------------------------------------

    function test_swapToERC20Output_succeeds() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapter: address(adapter),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        uint256 ownerBalBefore = dust1.balanceOf(owner);
        _execute(plan);

        assertEq(usdc.balanceOf(recipient), 100 ether);
        assertEq(dust1.balanceOf(owner), ownerBalBefore - 100 ether);
        assertEq(dust1.balanceOf(address(executor)), 0);
        assertEq(executor.nonces(owner), 1);
    }

    function test_swapToNativeMON_succeeds() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(executor.MON_NATIVE_SENTINEL());
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapter: address(adapter),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        // MockAdapter will mint 100 ether of WMON to the executor; MockWMON.withdraw
        // needs real native MON backing that mint for the unwrap to succeed.
        vm.deal(address(wmon), 100 ether);

        uint256 recipientBalBefore = recipient.balance;
        _execute(plan);

        assertEq(recipient.balance - recipientBalBefore, 100 ether);
    }

    function test_transferAction_consolidates() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 30 ether, to: recipient});
        plan.transfers = transfers;

        _execute(plan);
        assertEq(dust1.balanceOf(recipient), 30 ether);
    }

    function test_discardAction_sendsToDeadAddress() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.DiscardAction[] memory discards = new SweepPlanLib.DiscardAction[](1);
        discards[0] = SweepPlanLib.DiscardAction({token: address(dust1), amount: 15 ether});
        plan.discards = discards;

        _execute(plan);
        assertEq(dust1.balanceOf(executor.DEAD()), 15 ether);
    }

    function test_burnAction_reducesSupply() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.BurnAction[] memory burns = new SweepPlanLib.BurnAction[](1);
        burns[0] = SweepPlanLib.BurnAction({token: address(dust4), amount: 40 ether});
        plan.burns = burns;

        uint256 supplyBefore = dust4.totalSupply();
        _execute(plan);
        assertEq(dust4.totalSupply(), supplyBefore - 40 ether);
    }

    // -----------------------------------------------------------------
    // allowFailure semantics (§19.9)
    // -----------------------------------------------------------------

    function test_allowFailure_adapterReverts_planContinuesAndReturnsInput() public {
        adapter.setMode(MockAdapter.Mode.REVERT);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapter: address(adapter),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: true
        });
        plan.swaps = swaps;

        uint256 ownerBalBefore = dust1.balanceOf(owner);
        _execute(plan);

        // Input was pulled, but since the adapter reverted, it comes straight back.
        assertEq(dust1.balanceOf(owner), ownerBalBefore);
        assertEq(usdc.balanceOf(recipient), 0);
        assertEq(dust1.balanceOf(address(executor)), 0);
    }

    function test_requiredSwapFails_revertsEntirePlan() public {
        adapter.setMode(MockAdapter.Mode.REVERT);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapter: address(adapter),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert("MockAdapter: forced revert");
        executor.executeSweep(plan, sig);
    }

    function test_adapterUnderDelivers_revertsInvariantViolation_regardlessOfAllowFailure() public {
        adapter.setMode(MockAdapter.Mode.UNDER_DELIVER);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapter: address(adapter),
            minAmountOut: 50 ether,
            routeData: hex"12",
            allowFailure: true // must NOT save it - a "successful" under-delivery is never tolerated
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SweepExecutor.AdapterInvariantViolation.selector, address(adapter), 50 ether - 1, 50 ether
            )
        );
        executor.executeSweep(plan, sig);
    }

    // -----------------------------------------------------------------
    // Validation failures
    // -----------------------------------------------------------------

    function test_notPlanOwner_reverts() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 1 ether, to: recipient});
        plan.transfers = transfers;

        bytes memory sig = _sign(plan);
        vm.expectRevert(SweepExecutor.NotPlanOwner.selector);
        executor.executeSweep(plan, sig); // called by test contract, not `owner`
    }

    function test_zeroRecipient_reverts() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        plan.recipient = address(0);
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 1 ether, to: recipient});
        plan.transfers = transfers;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(SweepExecutor.ZeroRecipient.selector);
        executor.executeSweep(plan, sig);
    }

    function test_outputTokenNotAllowed_reverts() public {
        MockERC20 notAllowed = new MockERC20("Not Allowed", "NA");
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(notAllowed));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 1 ether, to: recipient});
        plan.transfers = transfers;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SweepExecutor.OutputTokenNotAllowed.selector, address(notAllowed)));
        executor.executeSweep(plan, sig);
    }

    function test_expiredPlan_reverts() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        plan.deadline = block.timestamp + 1;
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 1 ether, to: recipient});
        plan.transfers = transfers;

        bytes memory sig = _sign(plan);
        vm.warp(block.timestamp + 2);
        vm.prank(owner);
        vm.expectRevert(SweepExecutor.PlanExpired.selector);
        executor.executeSweep(plan, sig);
    }

    function test_reusedNonce_reverts() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 1 ether, to: recipient});
        plan.transfers = transfers;

        _execute(plan); // consumes nonce 0

        // Re-sign an identical-shape plan still claiming nonce 0.
        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SweepExecutor.InvalidPlanNonce.selector, 1, 0));
        executor.executeSweep(plan, sig);
    }

    function test_unregisteredAdapter_reverts() public {
        MockAdapter rogue = new MockAdapter();
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapter: address(rogue),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SweepExecutor.AdapterNotAllowed.selector, address(rogue)));
        executor.executeSweep(plan, sig);
    }

    function test_ambiguousSwapToken_reverts() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(usdc), // same as output/settlement token
            amountIn: 100 ether,
            adapter: address(adapter),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SweepExecutor.AmbiguousSwapToken.selector, address(usdc)));
        executor.executeSweep(plan, sig);
    }

    function test_emptyPlan_reverts() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(SweepPlanLib.EmptyPlan.selector);
        executor.executeSweep(plan, sig);
    }

    // -----------------------------------------------------------------
    // Isolation from pre-existing contract balances (§19.10)
    // -----------------------------------------------------------------

    function test_preExistingExecutorBalance_isNotSweptIntoPlan() public {
        // Tokens forcibly/accidentally sent to the executor before this plan runs.
        dust1.mint(address(executor), 500 ether);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 30 ether, to: recipient});
        plan.transfers = transfers;

        _execute(plan);

        // Only the plan's own 30 ether moved; the pre-existing 500 ether is untouched
        // and was not attributed to this plan's owner or recipient.
        assertEq(dust1.balanceOf(recipient), 30 ether);
        assertEq(dust1.balanceOf(address(executor)), 500 ether);
    }

    function test_recoverStrayTokens_onlyOwner() public {
        dust1.mint(address(executor), 10 ether);

        vm.expectRevert();
        executor.recoverStrayTokens(address(dust1), 10 ether, address(this));

        vm.prank(executorOwner);
        executor.recoverStrayTokens(address(dust1), 10 ether, executorOwner);
        assertEq(dust1.balanceOf(executorOwner), 10 ether);
    }

    function test_maliciousReentrantAdapter_reverts() public {
        MockReentrantAdapter reentrant = new MockReentrantAdapter(executor);
        vm.prank(executorOwner);
        executor.registerAdapter(address(reentrant));

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 10 ether,
            adapter: address(reentrant),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(); // ReentrancyGuardReentrantCall, surfaced through the adapter's try/catch as a bubbled revert
        executor.executeSweep(plan, sig);
    }

    // -----------------------------------------------------------------
    // Fuzz tests
    // -----------------------------------------------------------------

    function testFuzz_swapAmount_fullyConserved(uint96 amountInRaw) public {
        uint256 amountIn = bound(uint256(amountInRaw), 1, 1_000 ether);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: amountIn,
            adapter: address(adapter),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        uint256 ownerBalBefore = dust1.balanceOf(owner);
        _execute(plan);

        assertEq(dust1.balanceOf(owner), ownerBalBefore - amountIn);
        assertEq(usdc.balanceOf(recipient), amountIn);
        assertEq(dust1.balanceOf(address(executor)), 0);
        assertEq(usdc.balanceOf(address(executor)), 0);
    }

    function testFuzz_transferAndDiscard_neverRetainsFunds(uint96 transferRaw, uint96 discardRaw) public {
        uint256 transferAmount = bound(uint256(transferRaw), 0, 400 ether);
        uint256 discardAmount = bound(uint256(discardRaw), 0, 400 ether);
        vm.assume(transferAmount + discardAmount > 0);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: transferAmount, to: recipient});
        plan.transfers = transfers;
        SweepPlanLib.DiscardAction[] memory discards = new SweepPlanLib.DiscardAction[](1);
        discards[0] = SweepPlanLib.DiscardAction({token: address(dust1), amount: discardAmount});
        plan.discards = discards;

        _execute(plan);

        assertEq(dust1.balanceOf(recipient), transferAmount);
        assertEq(dust1.balanceOf(executor.DEAD()), discardAmount);
        assertEq(dust1.balanceOf(address(executor)), 0);
    }

    function testFuzz_preExistingBalance_neverAttributedToPlan(uint96 strayRaw, uint96 planAmountRaw) public {
        uint256 stray = bound(uint256(strayRaw), 1, 1_000 ether);
        uint256 planAmount = bound(uint256(planAmountRaw), 1, 500 ether);

        dust1.mint(address(executor), stray);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: planAmount, to: recipient});
        plan.transfers = transfers;

        _execute(plan);

        assertEq(dust1.balanceOf(recipient), planAmount);
        assertEq(dust1.balanceOf(address(executor)), stray);
    }
}
