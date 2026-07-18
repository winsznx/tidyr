// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {SweepExecutor} from "../src/SweepExecutor.sol";
import {SweepPlanLib} from "../src/libraries/SweepPlanLib.sol";
import {TidyrWitness} from "../src/libraries/TidyrWitness.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWMON} from "./mocks/MockWMON.sol";
import {MockAdapter} from "./mocks/MockAdapter.sol";

/// @notice Phase 7 Task 7.3: closes specific branch/scenario gaps identified while
/// auditing SweepExecutor.t.sol against the full completeness checklist - nonce
/// skip-ahead, cross-chain/cross-executor replay, pre-freeze mutation, repeated
/// freeze, and ownership transfer, none of which were previously exercised.
contract SweepExecutorCompletenessTest is Test {
    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    ISignatureTransfer internal permit2;
    SweepExecutor internal executor;
    MockWMON internal wmon;
    MockERC20 internal dust1;
    MockERC20 internal usdc;
    MockAdapter internal adapter;
    MockAdapter internal uniswapAdapter;

    uint256 internal ownerKey = 0xA11CE;
    address internal owner;
    address internal recipient = address(0xBEEF);
    address internal executorOwner = address(0xE0E0);

    function setUp() public {
        permit2 = ISignatureTransfer(deployCode("Permit2.sol:Permit2"));
        wmon = new MockWMON();
        adapter = new MockAdapter();
        uniswapAdapter = new MockAdapter();
        executor = new SweepExecutor(
            address(permit2), address(wmon), address(adapter), address(uniswapAdapter), executorOwner
        );

        dust1 = new MockERC20("Dust1", "DUST1");
        usdc = new MockERC20("USD Coin", "USDC");
        vm.prank(executorOwner);
        executor.registerOutputToken(address(usdc));

        owner = vm.addr(ownerKey);
        dust1.mint(owner, 1_000 ether);
        vm.prank(owner);
        dust1.approve(address(permit2), type(uint256).max);
    }

    function _emptyPlan(address outputToken, uint256 nonce) internal view returns (SweepPlanLib.SweepPlan memory plan) {
        plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: outputToken,
            deadline: block.timestamp + 600,
            nonce: nonce,
            displayManifestHash: keccak256("display"),
            swaps: new SweepPlanLib.SwapAction[](0),
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
    }

    function _signFor(SweepPlanLib.SweepPlan memory plan, address spender)
        internal
        view
        returns (bytes memory signature)
    {
        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);
        bytes32[] memory tokenPermissionHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPermissionHashes[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, tokens[i], amounts[i]));
        }
        bytes32 executionPlanHash = SweepPlanLib.hashPlan(plan, block.chainid, spender);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_STUB, TidyrWitness.WITNESS_TYPE_STRING));
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                spender,
                plan.nonce,
                plan.deadline,
                witness
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        signature = bytes.concat(r, s, bytes1(v));
    }

    // -----------------------------------------------------------------
    // Nonce edge cases
    // -----------------------------------------------------------------

    /// @dev Distinct from "reused nonce" (submitting nonce 0 twice): this submits a
    /// nonce *ahead* of the current counter (skip-ahead) with an otherwise valid
    /// signature, and must revert the same way - nonces increment by exactly one per
    /// successful sweep, never user-selectable.
    function test_skipAheadNonce_reverts() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc), 5);
        bytes memory sig = _signFor(plan, address(executor));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SweepExecutor.InvalidPlanNonce.selector, 0, 5));
        executor.executeSweep(plan, sig);
    }

    // -----------------------------------------------------------------
    // Cross-chain / cross-executor replay
    // -----------------------------------------------------------------

    /// @dev A signature produced for one chain ID must not authorize execution after
    /// the chain ID changes (e.g. replaying a mainnet-signed plan against a fork/testnet
    /// deployment at the same address) - chainId is bound into executionPlanHash.
    function test_signature_doesNotSurviveChainIdChange() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc), 0);
        bytes memory sig = _signFor(plan, address(executor));

        vm.chainId(block.chainid + 1);

        vm.prank(owner);
        vm.expectRevert();
        executor.executeSweep(plan, sig);
    }

    /// @dev A signature produced for one SweepExecutor deployment must not authorize
    /// execution against a second, independently deployed executor at a different
    /// address - executor address is bound into executionPlanHash.
    function test_signature_doesNotSurviveCrossExecutorReplay() public {
        SweepExecutor secondExecutor = new SweepExecutor(
            address(permit2), address(wmon), address(adapter), address(uniswapAdapter), executorOwner
        );
        vm.prank(executorOwner);
        secondExecutor.registerOutputToken(address(usdc));

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc), 0);
        bytes memory sigForFirstExecutor = _signFor(plan, address(executor));

        vm.prank(owner);
        vm.expectRevert();
        secondExecutor.executeSweep(plan, sigForFirstExecutor);
    }

    // -----------------------------------------------------------------
    // Configuration mutation before freeze / repeated freeze / ownership
    // -----------------------------------------------------------------

    function test_registerAndRemoveOutputToken_succeedBeforeFreeze() public {
        MockERC20 another = new MockERC20("Another", "ANO");

        vm.prank(executorOwner);
        executor.registerOutputToken(address(another));
        assertTrue(executor.allowedOutputTokens(address(another)));

        vm.prank(executorOwner);
        executor.removeOutputToken(address(another));
        assertFalse(executor.allowedOutputTokens(address(another)));
    }

    /// @dev `freezeConfiguration` has no `whenNotFrozen` guard on itself - calling it
    /// again after already frozen must be a harmless no-op (idempotent), not a
    /// revert or a way to re-run freeze-time side effects.
    function test_repeatedFreeze_isHarmlessNoOp() public {
        adapter.freezeConfiguration();
        uniswapAdapter.freezeConfiguration();

        vm.startPrank(executorOwner);
        executor.freezeConfiguration();
        assertTrue(executor.configurationFrozen());
        executor.freezeConfiguration();
        assertTrue(executor.configurationFrozen());
        vm.stopPrank();
    }

    /// @dev Ownable2Step's two-step transfer: pending owner must explicitly accept
    /// before administrative powers move, and the old owner retains them until then.
    function test_ownershipTransfer_requiresAcceptance() public {
        address newOwner = address(0xDECAF);

        vm.prank(executorOwner);
        executor.transferOwnership(newOwner);

        // Not yet accepted: old owner can still administer.
        MockERC20 another = new MockERC20("Another", "ANO");
        vm.prank(executorOwner);
        executor.registerOutputToken(address(another));

        // New owner must accept before gaining power.
        vm.prank(newOwner);
        vm.expectRevert();
        executor.registerOutputToken(address(another));

        vm.prank(newOwner);
        executor.acceptOwnership();

        assertEq(executor.owner(), newOwner);
        vm.prank(newOwner);
        executor.registerOutputToken(address(another));

        vm.prank(executorOwner);
        vm.expectRevert();
        executor.registerOutputToken(address(another));
    }

    // -----------------------------------------------------------------
    // Task 7.12 coverage closure: branches identified by `forge coverage` as
    // untested (zero-address admin inputs, native-MON output with no swap output)
    // -----------------------------------------------------------------

    function test_registerOutputToken_rejectsZeroAddress() public {
        vm.prank(executorOwner);
        vm.expectRevert(SweepExecutor.ZeroAddress.selector);
        executor.registerOutputToken(address(0));
    }

    function test_recoverStrayTokens_rejectsZeroAddressRecipient() public {
        vm.prank(executorOwner);
        vm.expectRevert(SweepExecutor.ZeroAddress.selector);
        executor.recoverStrayTokens(address(dust1), 0, address(0));
    }

    /// @dev A plan requesting native MON output but containing zero swap actions
    /// (only a transfer of a different token) - `_settleOutput`'s `wmonDelta` stays
    /// zero (nothing to unwrap) and `outputAmount` resolves to zero with no native
    /// transfer attempted. Must succeed, not revert, and send nothing.
    function test_nativeMonOutput_withNoSwapProducingMon_settlesToZero() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(executor.MON_NATIVE_SENTINEL(), 0);
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(dust1), amount: 10 ether, to: recipient});
        plan.transfers = transfers;

        bytes memory sig = _signFor(plan, address(executor));
        uint256 recipientBalBefore = recipient.balance;
        vm.prank(owner);
        executor.executeSweep(plan, sig);

        assertEq(recipient.balance, recipientBalBefore);
        assertEq(dust1.balanceOf(recipient), 10 ether);
    }
}
