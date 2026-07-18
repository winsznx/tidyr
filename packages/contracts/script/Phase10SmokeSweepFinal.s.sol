// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {SweepExecutor} from "../src/SweepExecutor.sol";
import {SweepPlanLib} from "../src/libraries/SweepPlanLib.sol";
import {TidyrWitness} from "../src/libraries/TidyrWitness.sol";

/// @notice Final pre-broadcast step for the real Phase 10 smoke sweep. Signs and
/// builds the exact executeSweep calldata against REAL, already-completed on-chain
/// state (pool created, liquidity minted, Permit2 approved - all done in Tx1-Tx7).
/// Run WITHOUT --broadcast: forge script then only simulates against current mainnet
/// state and never sends a real transaction. Only Tx8 broadcasts, and only after
/// this simulation's output is reviewed and approved separately.
contract Phase10SmokeSweepFinal is Script {
    address constant DEPLOYER = 0xbde0076F05B5eA898F9ca51f1b595D84598DE586;
    address constant SWEEP_EXECUTOR = 0x7a844005998e896967A8b2BdA13c7826F387E9c3;
    address constant DUST3 = 0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3;
    address constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint24 constant DUST3_WMON_FEE = 3000;
    uint24 constant WMON_USDC_FEE = 3000;

    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(vm.addr(deployerKey) == DEPLOYER, "key does not match expected deployer");

        SweepExecutor executor = SweepExecutor(payable(SWEEP_EXECUTOR));
        uint256 swapAmount = 200 ether;
        uint256 minAmountOut = 414; // floor(423 * 0.98), fresh live multihop quote this session
        uint256 planNonce = executor.nonces(DEPLOYER);
        uint256 deadline = block.timestamp + 900;

        bytes memory path = abi.encodePacked(DUST3, DUST3_WMON_FEE, WMON, WMON_USDC_FEE, USDC);

        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: DUST3,
            amountIn: swapAmount,
            adapterKind: SweepPlanLib.AdapterKind.UNISWAP_V3,
            minAmountOut: minAmountOut,
            routeData: path,
            allowFailure: false
        });

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: DEPLOYER,
            recipient: DEPLOYER,
            outputToken: USDC,
            deadline: deadline,
            nonce: planNonce,
            displayManifestHash: keccak256("phase10-real-mainnet-smoke"),
            swaps: swaps,
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });

        bytes memory sig = _sign(plan, deployerKey);
        bytes memory calldataBytes = abi.encodeCall(SweepExecutor.executeSweep, (plan, sig));

        console2.log("planNonce:", planNonce);
        console2.log("deadline:", deadline);
        console2.log("minAmountOut:", minAmountOut);
        console2.logBytes(calldataBytes);

        uint256 usdcBefore = IERC20(USDC).balanceOf(DEPLOYER);
        uint256 dust3Before = IERC20(DUST3).balanceOf(DEPLOYER);

        vm.startBroadcast(deployerKey);
        bytes32 executionPlanHash = executor.executeSweep(plan, sig);
        vm.stopBroadcast();

        uint256 usdcAfter = IERC20(USDC).balanceOf(DEPLOYER);
        uint256 dust3After = IERC20(DUST3).balanceOf(DEPLOYER);

        console2.log("=== Simulation result (real mainnet state, not broadcast) ===");
        console2.log("executionPlanHash:");
        console2.logBytes32(executionPlanHash);
        console2.log("DUST3 spent:", dust3Before - dust3After);
        console2.log("USDC received:", usdcAfter - usdcBefore);
        console2.log("SweepExecutor USDC balance after (must be 0):", IERC20(USDC).balanceOf(SWEEP_EXECUTOR));
        console2.log("SweepExecutor DUST3 balance after (must be 0):", IERC20(DUST3).balanceOf(SWEEP_EXECUTOR));
    }

    function _sign(SweepPlanLib.SweepPlan memory plan, uint256 signerKey) internal view returns (bytes memory) {
        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);
        bytes32[] memory tokenPermissionHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPermissionHashes[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, tokens[i], amounts[i]));
        }
        bytes32 executionPlanHash = SweepPlanLib.hashPlan(plan, block.chainid, SWEEP_EXECUTOR);
        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_STUB, TidyrWitness.WITNESS_TYPE_STRING));
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                SWEEP_EXECUTOR,
                plan.nonce,
                plan.deadline,
                witness
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", ISignatureTransfer(PERMIT2).DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return bytes.concat(r, s, bytes1(v));
    }
}
