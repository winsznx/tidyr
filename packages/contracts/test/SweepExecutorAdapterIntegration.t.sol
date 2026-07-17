// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {SweepExecutor} from "../src/SweepExecutor.sol";
import {SweepPlanLib} from "../src/libraries/SweepPlanLib.sol";
import {TidyrWitness} from "../src/libraries/TidyrWitness.sol";
import {PancakeV2Adapter} from "../src/adapters/PancakeV2Adapter.sol";
import {UniswapV3Adapter} from "../src/adapters/UniswapV3Adapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWMON} from "./mocks/MockWMON.sol";
import {MockPancakeFactory} from "./mocks/MockPancakeFactory.sol";
import {MockPancakePair} from "./mocks/MockPancakePair.sol";
import {MockSwapRouter02} from "./mocks/MockSwapRouter02.sol";

/// @notice End-to-end proof that SweepExecutor and the real (non-mock) adapter
/// contracts work together correctly - Phase 4's tests only exercised SweepExecutor
/// against a controllable MockAdapter; this exercises the real PancakeV2Adapter and
/// UniswapV3Adapter contracts through a full signed-plan execution.
contract SweepExecutorAdapterIntegrationTest is Test {
    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    ISignatureTransfer internal permit2;
    SweepExecutor internal executor;
    MockWMON internal wmon;
    MockERC20 internal dust1;
    MockERC20 internal usdc;

    PancakeV2Adapter internal pancakeAdapter;
    MockPancakeFactory internal pancakeFactory;
    MockPancakePair internal pairDustWmon;

    UniswapV3Adapter internal v3Adapter;
    MockSwapRouter02 internal v3Router;

    uint256 internal ownerKey = 0xA11CE;
    address internal owner;
    address internal recipient = address(0xBEEF);
    address internal executorOwner = address(0xE0E0);

    function setUp() public {
        permit2 = ISignatureTransfer(deployCode("Permit2.sol:Permit2"));
        wmon = new MockWMON();

        dust1 = new MockERC20("Dust1", "DUST1");
        usdc = new MockERC20("USDC", "USDC");

        pancakeFactory = new MockPancakeFactory();
        pancakeAdapter = new PancakeV2Adapter(address(pancakeFactory), address(wmon), executorOwner);
        pairDustWmon = new MockPancakePair(address(dust1), address(usdc));
        dust1.mint(address(pairDustWmon), 100_000 ether);
        usdc.mint(address(pairDustWmon), 50_000 ether);
        if (pairDustWmon.token0() == address(dust1)) {
            pairDustWmon.seedReserves(100_000 ether, 50_000 ether);
        } else {
            pairDustWmon.seedReserves(50_000 ether, 100_000 ether);
        }
        pancakeFactory.setPair(address(dust1), address(usdc), address(pairDustWmon));

        v3Router = new MockSwapRouter02();
        v3Router.setRatio(1, 2); // 2 DUST1 -> 1 USDC
        v3Adapter = new UniswapV3Adapter(address(v3Router), address(wmon), executorOwner);

        // Both real adapters are now fixed, immutable constructor arguments (Codex
        // addendum re-audit finding RA-01) - there is no registerAdapter step anymore.
        executor = new SweepExecutor(
            address(permit2), address(wmon), address(pancakeAdapter), address(v3Adapter), executorOwner
        );

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

    function test_realPancakeV2Adapter_endToEnd() public {
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        address[] memory path = new address[](2);
        path[0] = address(dust1);
        path[1] = address(usdc);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 1_000 ether,
            adapterKind: SweepPlanLib.AdapterKind.PANCAKE_V2,
            minAmountOut: 1,
            routeData: abi.encode(path),
            allowFailure: false
        });

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: swaps,
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        executor.executeSweep(plan, sig);

        assertGt(usdc.balanceOf(recipient), 0);
        assertEq(dust1.balanceOf(address(executor)), 0);
        assertEq(usdc.balanceOf(address(executor)), 0);
        assertEq(dust1.balanceOf(owner), 0);
    }

    function test_realUniswapV3Adapter_endToEnd() public {
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: address(dust1),
            amountIn: 1_000 ether,
            adapterKind: SweepPlanLib.AdapterKind.UNISWAP_V3,
            minAmountOut: 1,
            routeData: abi.encodePacked(address(dust1), uint24(3000), address(usdc)),
            allowFailure: false
        });

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: owner,
            recipient: recipient,
            outputToken: address(usdc),
            deadline: block.timestamp + 600,
            nonce: 0,
            displayManifestHash: keccak256("display"),
            swaps: swaps,
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });

        bytes memory sig = _sign(plan);
        vm.prank(owner);
        executor.executeSweep(plan, sig);

        assertEq(usdc.balanceOf(recipient), 500 ether); // 1000 DUST1 / 2
        assertEq(dust1.balanceOf(address(executor)), 0);
        assertEq(usdc.balanceOf(address(executor)), 0);
    }
}
