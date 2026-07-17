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

/// @notice Repeatedly drives valid, independently-signed sweeps from the same owner
/// (nonce strictly incrementing each call) with pseudo-random action shapes, then
/// checks the invariants below after every call.
contract SweepExecutorHandler is Test {
    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    ISignatureTransfer public immutable PERMIT2;
    SweepExecutor public immutable EXECUTOR;
    MockERC20 public immutable DUST;
    MockERC20 public immutable USDC;
    MockAdapter public immutable ADAPTER;

    uint256 public immutable OWNER_KEY;
    address public immutable OWNER;
    address public constant RECIPIENT = address(0xBEEF);

    uint256 public callCount;

    constructor(
        ISignatureTransfer permit2_,
        SweepExecutor executor_,
        MockERC20 dust_,
        MockERC20 usdc_,
        MockAdapter adapter_,
        uint256 ownerKey_
    ) {
        PERMIT2 = permit2_;
        EXECUTOR = executor_;
        DUST = dust_;
        USDC = usdc_;
        ADAPTER = adapter_;
        OWNER_KEY = ownerKey_;
        OWNER = vm.addr(ownerKey_);
    }

    function runSweep(uint96 amountRaw, bool asTransfer) external {
        uint256 ownerBalance = DUST.balanceOf(OWNER);
        if (ownerBalance == 0) return;
        uint256 amount = bound(uint256(amountRaw), 1, ownerBalance);

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: OWNER,
            recipient: RECIPIENT,
            outputToken: address(USDC),
            deadline: block.timestamp + 600,
            nonce: EXECUTOR.nonces(OWNER),
            displayManifestHash: keccak256(abi.encode("display", callCount)),
            swaps: new SweepPlanLib.SwapAction[](0),
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });

        if (asTransfer) {
            SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](1);
            transfers[0] = SweepPlanLib.TransferAction({token: address(DUST), amount: amount, to: RECIPIENT});
            plan.transfers = transfers;
        } else {
            SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
            swaps[0] = SweepPlanLib.SwapAction({
                tokenIn: address(DUST),
                amountIn: amount,
                adapter: address(ADAPTER),
                minAmountOut: 1,
                routeData: hex"12",
                allowFailure: false
            });
            plan.swaps = swaps;
        }

        bytes memory sig = _sign(plan);
        vm.prank(OWNER);
        EXECUTOR.executeSweep(plan, sig);
        callCount++;
    }

    function _sign(SweepPlanLib.SweepPlan memory plan) internal view returns (bytes memory signature) {
        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);
        bytes32[] memory tokenPermissionHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPermissionHashes[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, tokens[i], amounts[i]));
        }

        bytes32 executionPlanHash = SweepPlanLib.hashPlan(plan, block.chainid, address(EXECUTOR));
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_STUB, TidyrWitness.WITNESS_TYPE_STRING));

        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                address(EXECUTOR),
                plan.nonce,
                plan.deadline,
                witness
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", PERMIT2.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, digest);
        signature = bytes.concat(r, s, bytes1(v));
    }
}

contract SweepExecutorInvariantsTest is Test {
    ISignatureTransfer internal permit2;
    SweepExecutor internal executor;
    MockWMON internal wmon;
    MockERC20 internal dust1;
    MockERC20 internal usdc;
    MockAdapter internal adapter;
    SweepExecutorHandler internal handler;

    function setUp() public {
        permit2 = ISignatureTransfer(deployCode("Permit2.sol:Permit2"));
        wmon = new MockWMON();
        executor = new SweepExecutor(address(permit2), address(wmon), address(this));

        dust1 = new MockERC20("Dust1", "DUST1");
        usdc = new MockERC20("USD Coin", "USDC");
        adapter = new MockAdapter();

        executor.registerAdapter(address(adapter));
        executor.registerOutputToken(address(usdc));

        handler = new SweepExecutorHandler(permit2, executor, dust1, usdc, adapter, 0xA11CE);
        dust1.mint(handler.OWNER(), 1_000_000 ether);
        vm.prank(handler.OWNER());
        dust1.approve(address(permit2), type(uint256).max);

        targetContract(address(handler));
    }

    /// @dev PRD §5.11 / §19.10: successful execution must leave zero active-plan
    /// balance in the executor for every token this handler ever touches.
    function invariant_executorRetainsNoTouchedTokenBalance() public view {
        assertEq(dust1.balanceOf(address(executor)), 0);
        assertEq(usdc.balanceOf(address(executor)), 0);
    }

    /// @dev The executor's own nonce counter must equal exactly the number of
    /// successfully executed sweeps for this owner - it can never be skipped or reused.
    function invariant_nonceMatchesCallCount() public view {
        assertEq(executor.nonces(handler.OWNER()), handler.callCount());
    }
}
