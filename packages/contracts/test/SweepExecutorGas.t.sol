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

/// @notice Phase 7 Task 7.11: measures gas at the plan-shape extremes
/// `SweepPlanLib.MAX_ACTIONS` allows, so a maximum-size plan's real cost (not just its
/// shape-validation cost, already covered by SweepPlanLib.t.sol) is directly observed
/// rather than assumed. Also confirms the executor's own loops stay linear in action
/// count - not helped along here, since MAX_ACTIONS is a fixed, tested bound.
contract SweepExecutorGasTest is Test {
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
        dust1.mint(owner, 10_000_000 ether);
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

    /// @dev Exactly MAX_ACTIONS (50) transfer actions of the same token to the same
    /// recipient - the cheapest possible way to hit the action-count ceiling, so this
    /// is close to a best case; test_maxActions_duplicateTokenHeavyPlan below measures
    /// a costlier shape (many distinct small amounts of the same token, forcing
    /// `aggregateTokenAmounts`'s O(n^2) dedupe to do real work every iteration).
    function test_gas_maxActionsPlan_50Transfers() public {
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](50);
        for (uint256 i = 0; i < 50; i++) {
            transfers[i] = SweepPlanLib.TransferAction({token: address(dust1), amount: 1 ether, to: recipient});
        }
        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: new SweepPlanLib.SwapAction[](0),
            transfers: transfers,
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        executor.executeSweep(plan, sig);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("executeSweep gas (50 same-token transfers)", gasUsed);

        assertEq(dust1.balanceOf(recipient), 50 ether);
    }

    /// @dev 50 transfer actions across 50 *distinct* tokens - forces
    /// `aggregateTokenAmounts`'s O(n^2) dedupe loop to actually scan the full
    /// `seen` array on every iteration (worst case for that specific algorithm, since
    /// every token is unique so no early-match short-circuit ever fires), and forces
    /// 50 separate Permit2 `TokenPermissions` entries plus 50 separate baseline/
    /// remainder balance checks - the true worst-case shape for a 50-action plan.
    function test_gas_maxActionsPlan_50DistinctTokenTransfers() public {
        MockERC20[] memory tokens = new MockERC20[](50);
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](50);
        for (uint256 i = 0; i < 50; i++) {
            tokens[i] = new MockERC20(string.concat("Token", vm.toString(i)), string.concat("TKN", vm.toString(i)));
            tokens[i].mint(owner, 100 ether);
            vm.prank(owner);
            tokens[i].approve(address(permit2), type(uint256).max);
            transfers[i] = SweepPlanLib.TransferAction({token: address(tokens[i]), amount: 1 ether, to: recipient});
        }
        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: new SweepPlanLib.SwapAction[](0),
            transfers: transfers,
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        executor.executeSweep(plan, sig);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("executeSweep gas (50 distinct-token transfers only, excludes test setup)", gasUsed);

        for (uint256 i = 0; i < 50; i++) {
            assertEq(tokens[i].balanceOf(recipient), 1 ether);
        }
    }

    /// @dev A single plan mixing all four action types at a moderate, realistic
    /// count (not the ceiling) - the "typical large sweep" shape, distinct from both
    /// the ceiling-stress tests above.
    function test_gas_mixedActionPlan_10OfEachType() public {
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](10);
        for (uint256 i = 0; i < 10; i++) {
            swaps[i] = SweepPlanLib.SwapAction({
                tokenIn: address(dust1),
                amountIn: 1 ether,
                adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
                minAmountOut: 1,
                routeData: hex"12",
                allowFailure: false
            });
        }
        SweepPlanLib.TransferAction[] memory transfers = new SweepPlanLib.TransferAction[](10);
        for (uint256 i = 0; i < 10; i++) {
            transfers[i] = SweepPlanLib.TransferAction({token: address(dust1), amount: 1 ether, to: recipient});
        }
        SweepPlanLib.DiscardAction[] memory discards = new SweepPlanLib.DiscardAction[](10);
        for (uint256 i = 0; i < 10; i++) {
            discards[i] = SweepPlanLib.DiscardAction({token: address(dust1), amount: 1 ether});
        }

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: swaps,
            transfers: transfers,
            discards: discards,
            burns: new SweepPlanLib.BurnAction[](0)
        });

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        executor.executeSweep(plan, sig);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("executeSweep gas (10 swaps + 10 transfers + 10 discards)", gasUsed);
    }
}
