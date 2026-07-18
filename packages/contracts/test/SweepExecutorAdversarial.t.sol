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
import {MockAdapter} from "./mocks/MockAdapter.sol";
import {MockMaliciousAdapter} from "./mocks/MockMaliciousAdapter.sol";
import {MockFalseReturnERC20} from "./mocks/MockFalseReturnERC20.sol";
import {MockNoReturnERC20} from "./mocks/MockNoReturnERC20.sol";
import {MockFeeOnTransferERC20} from "./mocks/MockFeeOnTransferERC20.sol";
import {MockRevertingRecipient} from "./mocks/MockRevertingRecipient.sol";
import {MockReentrantERC20} from "./mocks/MockReentrantERC20.sol";

/// @notice Phase 7 Tasks 7.5 (balance accounting edge cases) and 7.6 (adversarial
/// token/adapter mocks). Each token-behavior test explicitly classifies the outcome
/// as safely-supported, safely-rejected, or explicitly-unsupported per Task 7.6 - this
/// suite never claims support beyond what's actually exercised.
contract SweepExecutorAdversarialTest is Test {
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

    function _sign(SweepPlanLib.SweepPlan memory plan) internal view returns (bytes memory signature) {
        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);
        bytes32[] memory tokenPermissionHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPermissionHashes[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, tokens[i], amounts[i]));
        }
        bytes32 executionPlanHash = SweepPlanLib.hashPlan(plan, block.chainid, address(executor));
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_STUB, TidyrWitness.WITNESS_TYPE_STRING));
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                address(executor),
                plan.nonce,
                plan.deadline,
                witness
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        signature = bytes.concat(r, s, bytes1(v));
    }

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

    // -----------------------------------------------------------------
    // Task 7.5: balance accounting edge cases
    // -----------------------------------------------------------------

    /// @dev Settlement token also appears as a TRANSFER action's token (not a swap
    /// input - that's independently guarded by AmbiguousSwapToken). Proves the
    /// _settleOutput-before-_returnRemainders ordering correctly avoids double-counting
    /// the transfer's own pulled amount as swap-produced output.
    function test_outputTokenAlsoUsedAsTransferInput_noDoubleCount() public {
        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));

        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        // A separate USDC balance the owner also authorizes as a plain transfer -
        // pulled via Permit2, then sent straight to `recipient` as a TRANSFER action.
        usdc.mint(owner, 40 ether);
        vm.prank(owner);
        usdc.approve(address(permit2), type(uint256).max);

        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(usdc), amount: 40 ether, to: recipient});
        plan.transfers = transfers;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        executor.executeSweep(plan, sig);

        // Recipient gets exactly: 100 ether from the swap output + 40 ether from the
        // transfer - never double-counted, never short.
        assertEq(usdc.balanceOf(recipient), 140 ether);
        assertEq(usdc.balanceOf(address(executor)), 0);
        assertEq(dust1.balanceOf(address(executor)), 0);
    }

    /// @dev A pre-existing stray balance of the *settlement* token (not just an
    /// unrelated token, already covered by test_preExistingExecutorBalance_
    /// isNotSweptIntoPlan in SweepExecutor.t.sol) must never be swept into this plan's
    /// output.
    function test_preExistingOutputTokenBalance_isNotSweptIntoPlan() public {
        usdc.mint(address(executor), 500 ether);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        executor.executeSweep(plan, sig);

        // Only the 100 ether this plan actually produced moved to the recipient; the
        // pre-existing 500 ether stray balance stays put.
        assertEq(usdc.balanceOf(recipient), 100 ether);
        assertEq(usdc.balanceOf(address(executor)), 500 ether);
    }

    // -----------------------------------------------------------------
    // Task 7.6: adversarial ERC20 behaviors
    // -----------------------------------------------------------------

    /// @dev Classification: safely rejected. A token whose transfer/transferFrom
    /// returns `false` instead of reverting must cause SafeERC20 to revert, not
    /// silently proceed as if the transfer succeeded.
    function test_falseReturnToken_asOutputToken_reverts() public {
        MockFalseReturnERC20 falseToken = new MockFalseReturnERC20();
        falseToken.mint(address(0xDEAD1), 0); // no-op, just confirms deployment

        vm.prank(executorOwner);
        executor.registerOutputToken(address(falseToken));

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(falseToken));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        // MockAdapter mints `falseToken` 1:1 as output, then _settleOutput's
        // safeTransfer to `recipient` must revert because the token reports failure.
        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert();
        executor.executeSweep(plan, sig);
    }

    /// @dev Classification: safely supported. A token with no return value at all
    /// (USDT-style) must work normally through SafeERC20's low-level-call handling.
    function test_noReturnToken_asOutputToken_succeeds() public {
        MockNoReturnERC20 noReturnToken = new MockNoReturnERC20();

        vm.prank(executorOwner);
        executor.registerOutputToken(address(noReturnToken));

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(noReturnToken));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](0);
        plan.transfers = transfers;
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        executor.executeSweep(plan, sig);

        assertEq(noReturnToken.balanceOf(recipient), 100 ether);
    }

    /// @dev Classification: safely rejected. A fee-on-transfer input token means the
    /// executor receives strictly less than the exact amount Permit2 was authorized
    /// to pull - UnexpectedPulledAmount must catch this, not silently under-credit.
    function test_feeOnTransferToken_asSwapInput_reverts() public {
        MockFeeOnTransferERC20 feeToken = new MockFeeOnTransferERC20("Fee", "FEE", 500); // 5%
        feeToken.mint(owner, 1_000 ether);
        vm.prank(owner);
        feeToken.approve(address(permit2), type(uint256).max);

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(feeToken),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SweepExecutor.UnexpectedPulledAmount.selector, address(feeToken), 100 ether, 95 ether
            )
        );
        executor.executeSweep(plan, sig);
    }

    /// @dev Classification: explicitly unsupported (documented, not silently broken).
    /// Native MON output sent to a recipient with no receive/fallback must revert the
    /// entire plan atomically - swept funds are never stranded or lost, but the plan
    /// itself cannot complete for that recipient.
    function test_moneyRejectingRecipient_revertsWholePlan() public {
        MockRevertingRecipient badRecipient = new MockRevertingRecipient();

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(executor.MON_NATIVE_SENTINEL());
        plan.recipient = address(badRecipient);
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;
        vm.deal(address(wmon), 100 ether);

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert(SweepExecutor.NativeTransferFailed.selector);
        executor.executeSweep(plan, sig);

        // Atomic revert: nothing moved, dust1 stays with the owner.
        assertEq(dust1.balanceOf(owner), 1_000 ether);
    }

    /// @dev Classification: safely rejected. A token that tries to reenter
    /// `recoverStrayTokens` from inside its own transfer hook (simulating an
    /// ERC-777-style callback) must be blocked by `nonReentrant`, which
    /// `executeSweep` and `recoverStrayTokens` share.
    function test_reentrantToken_transferHook_blockedByReentrancyGuard() public {
        MockReentrantERC20 reentrantToken = new MockReentrantERC20(executor);
        reentrantToken.mint(owner, 1_000 ether);
        vm.prank(owner);
        reentrantToken.approve(address(permit2), type(uint256).max);

        vm.prank(executorOwner);
        executor.registerOutputToken(address(reentrantToken));

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(reentrantToken));
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
        transfers[0] = SweepPlanLib.TransferAction({token: address(reentrantToken), amount: 10 ether, to: recipient});
        plan.transfers = transfers;

        reentrantToken.arm();
        bytes memory sig = _sign(plan);
        vm.prank(owner);
        vm.expectRevert();
        executor.executeSweep(plan, sig);
    }

    // -----------------------------------------------------------------
    // Task 7.6: adversarial adapter behaviors
    // -----------------------------------------------------------------

    /// @dev Classification: safely rejected. A malicious adapter attempting to pull
    /// more than the exact `amountIn` the executor approved must fail on the ERC20
    /// allowance itself - `forceApprove` grants an exact, single-use amount, not
    /// unlimited approval.
    function test_maliciousAdapter_excessPull_reverts() public {
        MockMaliciousAdapter malicious = new MockMaliciousAdapter();
        malicious.setMode(MockMaliciousAdapter.Mode.EXCESS_PULL);
        SweepExecutor maliciousExecutor = new SweepExecutor(
            address(permit2), address(wmon), address(malicious), address(uniswapAdapter), executorOwner
        );
        vm.prank(executorOwner);
        maliciousExecutor.registerOutputToken(address(usdc));

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: new SweepPlanLib.SwapAction[](1),
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
        plan.swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });

        bytes memory sig = _signFor(plan, address(maliciousExecutor));
        vm.prank(owner);
        vm.expectRevert();
        maliciousExecutor.executeSweep(plan, sig);
    }

    /// @dev Classification: safely rejected. An adapter that mints the "output" to
    /// itself instead of the executor must be caught by balance-delta accounting
    /// (the executor never trusts the adapter's own reported return value) and
    /// treated as an under-delivery invariant violation.
    function test_maliciousAdapter_sendsOutputElsewhere_reverts() public {
        MockMaliciousAdapter malicious = new MockMaliciousAdapter();
        malicious.setMode(MockMaliciousAdapter.Mode.SEND_ELSEWHERE);
        SweepExecutor maliciousExecutor = new SweepExecutor(
            address(permit2), address(wmon), address(malicious), address(uniswapAdapter), executorOwner
        );
        vm.prank(executorOwner);
        maliciousExecutor.registerOutputToken(address(usdc));

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: new SweepPlanLib.SwapAction[](1),
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
        plan.swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });

        bytes memory sig = _signFor(plan, address(maliciousExecutor));
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(SweepExecutor.AdapterInvariantViolation.selector, address(malicious), 0, 1)
        );
        maliciousExecutor.executeSweep(plan, sig);
    }

    /// @dev Classification: safely rejected. An adapter that pulls input, mutates its
    /// own state, then reverts must leave the executor's world exactly as if the call
    /// never happened - EVM-level atomicity, not something the executor has to
    /// implement itself, but worth an explicit regression proof.
    function test_maliciousAdapter_revertsAfterPartialMutation_leavesNoTrace() public {
        MockMaliciousAdapter malicious = new MockMaliciousAdapter();
        malicious.setMode(MockMaliciousAdapter.Mode.UNDER_DELIVER_AFTER_PARTIAL_MUTATION);
        SweepExecutor maliciousExecutor = new SweepExecutor(
            address(permit2), address(wmon), address(malicious), address(uniswapAdapter), executorOwner
        );
        vm.prank(executorOwner);
        maliciousExecutor.registerOutputToken(address(usdc));

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: new SweepPlanLib.SwapAction[](1),
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
        plan.swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: true
        });

        uint256 ownerBalBefore = dust1.balanceOf(owner);
        bytes memory sig = _signFor(plan, address(maliciousExecutor));
        vm.prank(owner);
        maliciousExecutor.executeSweep(plan, sig);

        // allowFailure=true: the adapter's revert is tolerated, its state mutation
        // never happened (EVM revert), and the input is returned to the owner intact.
        assertEq(dust1.balanceOf(owner), ownerBalBefore);
        assertEq(malicious.mutatedState(), 0);
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
    // Task 7.4: Permit2 substitution/replay through executeSweep (end-to-end, not
    // just direct Permit2 calls - Permit2Witness.t.sol covers the direct-call layer)
    // -----------------------------------------------------------------

    function _swapPlan(SweepPlanLib.AdapterKind kind) internal view returns (SweepPlanLib.SweepPlan memory plan) {
        plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 100 ether,
            adapterKind: kind,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: false
        });
        plan.swaps = swaps;
    }

    /// @dev A signature over a PANCAKE_V2 plan must not authorize execution of the
    /// otherwise-identical plan with UNISWAP_V3 substituted in after signing -
    /// adapterKind is part of executionPlanHash, so the witness no longer matches and
    /// Permit2's own signature check rejects it before any swap runs.
    function test_signedAdapterKind_cannotBeSubstitutedAtExecution() public {
        SweepPlanLib.SweepPlan memory signedPlan = _swapPlan(SweepPlanLib.AdapterKind.PANCAKE_V2);
        bytes memory sig = _sign(signedPlan);

        SweepPlanLib.SweepPlan memory submittedPlan = _swapPlan(SweepPlanLib.AdapterKind.UNISWAP_V3);

        vm.prank(owner);
        vm.expectRevert();
        executor.executeSweep(submittedPlan, sig);
    }

    /// @dev Plan A's signature (recipient = `recipient`) must not authorize execution
    /// of Plan B (recipient = a different address) - the classic "signature
    /// substitution" attack a naive implementation binding only token/amount (and not
    /// the full plan) would be vulnerable to.
    function test_planASignature_cannotAuthorizePlanB_differentRecipient() public {
        SweepPlanLib.SweepPlan memory planA = _swapPlan(SweepPlanLib.AdapterKind.PANCAKE_V2);
        bytes memory sigA = _sign(planA);

        SweepPlanLib.SweepPlan memory planB = _swapPlan(SweepPlanLib.AdapterKind.PANCAKE_V2);
        planB.recipient = address(0x9999);

        vm.prank(owner);
        vm.expectRevert();
        executor.executeSweep(planB, sigA);
    }

    /// @dev Same substitution attack, but via `minAmountOut` - proves the witness
    /// binds the swap's minimum-output guarantee too, not just routing identity.
    function test_planASignature_cannotAuthorizePlanB_differentMinAmountOut() public {
        SweepPlanLib.SweepPlan memory planA = _swapPlan(SweepPlanLib.AdapterKind.PANCAKE_V2);
        bytes memory sigA = _sign(planA);

        SweepPlanLib.SweepPlan memory planB = _swapPlan(SweepPlanLib.AdapterKind.PANCAKE_V2);
        planB.swaps[0].minAmountOut = 999 ether;

        vm.prank(owner);
        vm.expectRevert();
        executor.executeSweep(planB, sigA);
    }

    // -----------------------------------------------------------------
    // Task 7.7: combined fuzz across AdapterKind, amounts, and allowFailure
    // -----------------------------------------------------------------

    /// @dev Fuzzes both AdapterKind values, a wide amountIn range, and both
    /// allowFailure settings against an adapter whose delivery ratio is also fuzzed,
    /// asserting the executor's core safety property regardless of the combination:
    /// either the swap fully conserves value end-to-end, or the whole plan reverts
    /// (required-and-failed), or the input is returned untouched (optional-and-failed)
    /// - actual output is never silently lost or under-credited to the recipient.
    function testFuzz_adapterKindAndAllowFailureCombinations_neverLoseOrMisattributeFunds(
        bool useUniswapKind,
        uint96 amountInRaw,
        bool allowFailure,
        bool underDeliver
    ) public {
        uint256 amountIn = bound(uint256(amountInRaw), 1, 1_000 ether);
        SweepPlanLib.AdapterKind kind =
            useUniswapKind ? SweepPlanLib.AdapterKind.UNISWAP_V3 : SweepPlanLib.AdapterKind.PANCAKE_V2;
        MockAdapter targetAdapter = useUniswapKind ? uniswapAdapter : adapter;

        if (underDeliver) {
            targetAdapter.setMode(MockAdapter.Mode.UNDER_DELIVER);
        }

        SweepPlanLib.SweepPlan memory plan = _emptyPlan(address(usdc));
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: amountIn,
            adapterKind: kind,
            minAmountOut: 1,
            routeData: hex"12",
            allowFailure: allowFailure
        });
        plan.swaps = swaps;

        uint256 ownerBalBefore = dust1.balanceOf(owner);
        bytes memory sig = _sign(plan);

        if (underDeliver) {
            // UNDER_DELIVER always violates the invariant (minAmountOut=1, ratio
            // produces 0) regardless of allowFailure - a "successful but low-output"
            // call is always fatal, never tolerated.
            vm.prank(owner);
            vm.expectRevert();
            executor.executeSweep(plan, sig);
            return;
        }

        vm.prank(owner);
        executor.executeSweep(plan, sig);

        assertEq(dust1.balanceOf(owner), ownerBalBefore - amountIn);
        assertEq(usdc.balanceOf(recipient), amountIn);
        assertEq(dust1.balanceOf(address(executor)), 0);
        assertEq(usdc.balanceOf(address(executor)), 0);
    }
}
