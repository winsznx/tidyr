// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {SweepPlanLib} from "../src/libraries/SweepPlanLib.sol";
import {TidyrWitness} from "../src/libraries/TidyrWitness.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Phase 3: proves Permit2 SignatureTransfer witness binding to
/// `executionPlanHash` against a real, unmodified Permit2 deployment (not a mock),
/// deployed via `deployCode` because Permit2 pragmas an exact `0.8.17` incompatible with
/// this file's own `^0.8.26` — see foundry.toml's `auto_detect_solc` comment. This test
/// calls Permit2 directly (standing in for the not-yet-built SweepExecutor, which is
/// Phase 4); the "spender" bound into every signature below is this test contract
/// itself, matching Permit2's own test suite convention (`address(this)`).
contract Permit2WitnessTest is Test {
    ISignatureTransfer internal permit2;
    MockERC20 internal token;
    MockERC20 internal tokenB;

    uint256 internal ownerKey = 0xA11CE;
    address internal owner;
    address internal recipient = address(0xBEEF);

    // Mirrors PermitHash._PERMIT_BATCH_WITNESS_TRANSFER_FROM_TYPEHASH_STUB exactly
    // (packages/contracts/lib/permit2/src/libraries/PermitHash.sol) - not re-derived,
    // copied verbatim so a future permit2 upgrade that changes this stub causes a
    // visible test failure rather than a silent binding mismatch.
    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";

    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    function setUp() public {
        permit2 = ISignatureTransfer(deployCode("Permit2.sol:Permit2"));
        token = new MockERC20("Dust", "DUST");
        tokenB = new MockERC20("Dust2", "DUST2");
        owner = vm.addr(ownerKey);

        token.mint(owner, 1_000 ether);
        tokenB.mint(owner, 1_000 ether);

        vm.prank(owner);
        token.approve(address(permit2), type(uint256).max);
        vm.prank(owner);
        tokenB.approve(address(permit2), type(uint256).max);
    }

    /// @dev A plan with two swap-like actions touching the same token plus one action
    /// on a different token, so aggregation must produce exactly two unique entries.
    function _plan(address tokenAddr, address tokenBAddr) internal view returns (SweepPlanLib.SweepPlan memory plan) {
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](2);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: tokenAddr,
            amountIn: 100 ether,
            adapter: address(0x4444),
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        swaps[1] = SweepPlanLib.SwapAction({
            tokenIn: tokenAddr,
            amountIn: 50 ether,
            adapter: address(0x4444),
            minAmountOut: 1,
            routeData: hex"34",
            allowFailure: false
        });

        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: tokenBAddr, amount: 20 ether, to: recipient});

        plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: tokenBAddr,
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: swaps,
            transfers: transfers,
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
    }

    function test_aggregateTokenAmounts_dedupesAndSums() public view {
        SweepPlanLib.SweepPlan memory plan = _plan(address(token), address(tokenB));
        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);

        assertEq(tokens.length, 2);
        // token (150 ether total from the two swap actions)
        assertEq(tokens[0], address(token));
        assertEq(amounts[0], 150 ether);
        // tokenB (20 ether from the single transfer action)
        assertEq(tokens[1], address(tokenB));
        assertEq(amounts[1], 20 ether);
    }

    function _buildPermit(SweepPlanLib.SweepPlan memory plan, uint256 permitNonce)
        internal
        view
        returns (ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 executionPlanHash)
    {
        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);
        ISignatureTransfer.TokenPermissions[] memory permitted =
            new ISignatureTransfer.TokenPermissions[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            permitted[i] = ISignatureTransfer.TokenPermissions({token: tokens[i], amount: amounts[i]});
        }

        executionPlanHash = SweepPlanLib.hashPlan(plan, block.chainid, address(this));
        permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permitted,
            nonce: permitNonce,
            deadline: plan.deadline
        });
    }

    function _sign(ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 witness, uint256 signerKey)
        internal
        view
        returns (bytes memory signature)
    {
        uint256 n = permit.permitted.length;
        bytes32[] memory tokenPermissionHashes = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            tokenPermissionHashes[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i]));
        }

        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_STUB, TidyrWitness.WITNESS_TYPE_STRING));
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                address(this), // spender == this test contract, the caller below
                permit.nonce,
                permit.deadline,
                witness
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        signature = bytes.concat(r, s, bytes1(v));
    }

    function _transferDetails(ISignatureTransfer.PermitBatchTransferFrom memory permit, address to)
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails[] memory details)
    {
        details = new ISignatureTransfer.SignatureTransferDetails[](permit.permitted.length);
        for (uint256 i = 0; i < permit.permitted.length; i++) {
            details[i] =
                ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: permit.permitted[i].amount});
        }
    }

    function test_validWitness_succeeds() public {
        SweepPlanLib.SweepPlan memory plan = _plan(address(token), address(tokenB));
        (ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 executionPlanHash) = _buildPermit(plan, 0);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes memory sig = _sign(permit, witness, ownerKey);

        uint256 recipientBalBefore = token.balanceOf(recipient);
        permit2.permitWitnessTransferFrom(
            permit, _transferDetails(permit, recipient), owner, witness, TidyrWitness.WITNESS_TYPE_STRING, sig
        );
        assertEq(token.balanceOf(recipient) - recipientBalBefore, 150 ether);
        assertEq(tokenB.balanceOf(recipient), 20 ether);
    }

    function test_modifiedPlan_fails() public {
        SweepPlanLib.SweepPlan memory plan = _plan(address(token), address(tokenB));
        (ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 executionPlanHash) = _buildPermit(plan, 0);
        bytes32 signedWitness = TidyrWitness.hashWitness(executionPlanHash);
        bytes memory sig = _sign(permit, signedWitness, ownerKey);

        // Attacker (or a buggy caller) submits a witness for a *different* plan hash
        // than the one actually signed over.
        bytes32 tamperedWitness = TidyrWitness.hashWitness(keccak256("a-different-plan"));

        vm.expectRevert(); // SignatureVerification.InvalidSigner
        permit2.permitWitnessTransferFrom(
            permit, _transferDetails(permit, recipient), owner, tamperedWitness, TidyrWitness.WITNESS_TYPE_STRING, sig
        );
    }

    function test_reusedNonce_fails() public {
        SweepPlanLib.SweepPlan memory plan = _plan(address(token), address(tokenB));
        (ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 executionPlanHash) = _buildPermit(plan, 7);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes memory sig = _sign(permit, witness, ownerKey);

        permit2.permitWitnessTransferFrom(
            permit, _transferDetails(permit, recipient), owner, witness, TidyrWitness.WITNESS_TYPE_STRING, sig
        );

        vm.expectRevert(); // InvalidNonce
        permit2.permitWitnessTransferFrom(
            permit, _transferDetails(permit, recipient), owner, witness, TidyrWitness.WITNESS_TYPE_STRING, sig
        );
    }

    function test_expiredDeadline_fails() public {
        SweepPlanLib.SweepPlan memory plan = _plan(address(token), address(tokenB));
        plan.deadline = block.timestamp + 1;
        (ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 executionPlanHash) = _buildPermit(plan, 0);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes memory sig = _sign(permit, witness, ownerKey);

        vm.warp(block.timestamp + 2);

        vm.expectRevert(); // SignatureExpired
        permit2.permitWitnessTransferFrom(
            permit, _transferDetails(permit, recipient), owner, witness, TidyrWitness.WITNESS_TYPE_STRING, sig
        );
    }

    function test_wrongSpender_fails() public {
        SweepPlanLib.SweepPlan memory plan = _plan(address(token), address(tokenB));
        (ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 executionPlanHash) = _buildPermit(plan, 0);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        // Signed with address(this) as the implicit spender (see _sign).
        bytes memory sig = _sign(permit, witness, ownerKey);

        // A different contract calls Permit2 - msg.sender differs from what was signed,
        // so the recomputed struct hash (and therefore the signature check) fails.
        WrongSpenderCaller attacker = new WrongSpenderCaller(permit2);
        vm.expectRevert(); // SignatureVerification.InvalidSigner
        attacker.pull(permit, _transferDetails(permit, recipient), owner, witness, TidyrWitness.WITNESS_TYPE_STRING, sig);
    }

    function test_excessivePull_fails() public {
        SweepPlanLib.SweepPlan memory plan = _plan(address(token), address(tokenB));
        (ISignatureTransfer.PermitBatchTransferFrom memory permit, bytes32 executionPlanHash) = _buildPermit(plan, 0);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes memory sig = _sign(permit, witness, ownerKey);

        ISignatureTransfer.SignatureTransferDetails[] memory details = _transferDetails(permit, recipient);
        details[0].requestedAmount = permit.permitted[0].amount + 1; // more than signed

        vm.expectRevert(); // InvalidAmount
        permit2.permitWitnessTransferFrom(permit, details, owner, witness, TidyrWitness.WITNESS_TYPE_STRING, sig);
    }
}

/// @dev Minimal helper contract so `test_wrongSpender_fails` can call Permit2 from a
/// `msg.sender` other than the test contract itself.
contract WrongSpenderCaller {
    ISignatureTransfer internal immutable PERMIT2;

    constructor(ISignatureTransfer permit2) {
        PERMIT2 = permit2;
    }

    function pull(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails[] memory details,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory signature
    ) external {
        PERMIT2.permitWitnessTransferFrom(permit, details, owner, witness, witnessTypeString, signature);
    }
}
