// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {SweepExecutor} from "../src/SweepExecutor.sol";
import {SweepPlanLib} from "../src/libraries/SweepPlanLib.sol";
import {TidyrWitness} from "../src/libraries/TidyrWitness.sol";
import {IWMON} from "../src/interfaces/IWMON.sol";

interface IUniswapV3FactoryMinimal {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3PoolMinimal {
    function initialize(uint160 sqrtPriceX96) external;
}

interface INonfungiblePositionManagerMinimal {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @notice NOT part of Phase 8/9 deployment tooling. A one-off, fork-only validation
/// script for Phase 10: creates a small DUST3/WMON Uniswap V3 pool and simulates a
/// full multihop DUST3->WMON->USDC sweep through the REAL, already-deployed
/// SweepExecutor/UniswapV3Adapter (via a live Monad-mainnet fork), never touching
/// real mainnet. Confirms the whole pipeline works against genuinely deep liquidity
/// (the existing WMON/USDC Uniswap V3 pool) before any real capital is committed.
contract Phase10RouteSimulation is Script {
    address constant DEPLOYER = 0xbde0076F05B5eA898F9ca51f1b595D84598DE586;
    address constant SWEEP_EXECUTOR = 0x7a844005998e896967A8b2BdA13c7826F387E9c3;
    address constant DUST3 = 0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3;
    address constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant V3_FACTORY = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address constant NFPM = 0x7197E214c0b767cFB76Fb734ab638E2c192F4E53;
    uint24 constant DUST3_WMON_FEE = 3000;
    uint24 constant WMON_USDC_FEE = 3000;

    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(vm.addr(deployerKey) == DEPLOYER, "key does not match expected deployer");

        vm.startBroadcast(deployerKey);

        // --- Wrap a small amount of real MON into WMON for the demo pool ---
        // Sized per artifacts/phase-10/liquidity-sizing.md's recommendation: 5 MON
        // sustains ~24 sequential 200-DUST3 demo sweeps before 5% cumulative price
        // drift, at negligible (~0.2%) single-swap impact, while retaining ~88% of
        // the deployer's MON balance.
        uint256 wmonForPool = 5 ether;
        IWMON(WMON).deposit{value: wmonForPool}();

        // --- Create + initialize the DUST3/WMON pool (token0/token1 sorted) ---
        (address token0, address token1) = DUST3 < WMON ? (DUST3, WMON) : (WMON, DUST3);
        address pool = IUniswapV3FactoryMinimal(V3_FACTORY).getPool(DUST3, WMON, DUST3_WMON_FEE);
        if (pool == address(0)) {
            pool = IUniswapV3FactoryMinimal(V3_FACTORY).createPool(DUST3, WMON, DUST3_WMON_FEE);
            // price: 1 DUST3 = 0.0001 WMON (token0=DUST3, token1=WMON, both 18 decimals)
            IUniswapV3PoolMinimal(pool).initialize(792281625142643392428113920);
            console2.log("Created and initialized DUST3/WMON pool:", pool);
        } else {
            console2.log("DUST3/WMON pool already exists:", pool);
        }

        // --- Mint a wide-range liquidity position ---
        uint256 dust3ForPool = 50_000 ether; // matches the 0.0001 WMON/DUST3 price at 5 WMON depth
        IERC20(DUST3).approve(NFPM, dust3ForPool);
        IERC20(WMON).approve(NFPM, wmonForPool);

        (uint256 amount0Desired, uint256 amount1Desired) =
            token0 == DUST3 ? (dust3ForPool, wmonForPool) : (wmonForPool, dust3ForPool);

        INonfungiblePositionManagerMinimal.MintParams memory mintParams = INonfungiblePositionManagerMinimal.MintParams({
            token0: token0,
            token1: token1,
            fee: DUST3_WMON_FEE,
            tickLower: -98160,
            tickUpper: -86160,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: DEPLOYER,
            deadline: block.timestamp + 7200
        });

        (, uint128 liquidity, uint256 amount0Used, uint256 amount1Used) =
            INonfungiblePositionManagerMinimal(NFPM).mint(mintParams);
        console2.log("Minted DUST3/WMON position, liquidity:", liquidity);
        console2.log("amount0Used:", amount0Used);
        console2.log("amount1Used:", amount1Used);

        vm.stopBroadcast();

        // --- Simulate the multihop DUST3 -> WMON -> USDC sweep through the real,
        // already-deployed SweepExecutor + UniswapV3Adapter ---
        _simulateSweep(deployerKey);
    }

    function _simulateSweep(uint256 deployerKey) internal {
        SweepExecutor executor = SweepExecutor(payable(SWEEP_EXECUTOR));
        // One full DemoDistributor claim (DemoDistributor.CLAIM_AMOUNT) - the
        // smallest amount that still represents a realistic demo user's sweep,
        // per artifacts/phase-10/smoke-plan.json's candidate comparison.
        uint256 swapAmount = 200 ether;

        vm.startBroadcast(deployerKey);
        // Exact amount only - never an unlimited approval, even though Permit2's
        // own signed-amount model would make a max approval equally safe.
        IERC20(DUST3).approve(PERMIT2, swapAmount);
        vm.stopBroadcast();

        bytes memory path = abi.encodePacked(DUST3, DUST3_WMON_FEE, WMON, WMON_USDC_FEE, USDC);

        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: DUST3,
            amountIn: swapAmount,
            adapterKind: SweepPlanLib.AdapterKind.UNISWAP_V3,
            // 426 raw USDC units expected (modeled first leg + fresh live-quoted
            // second leg, see artifacts/phase-10/revised-smoke-plan.json) less a
            // tightened 2% slippage tolerance (Phase 10.1 economics review -
            // measured total degradation was 0.721%, and the first leg is fully
            // deterministic since we mint the pool ourselves in the same review
            // cycle; 2% comfortably covers real WMON/USDC market drift between
            // quote and broadcast without the excess 10% slack of the original
            // packet).
            minAmountOut: 417,
            routeData: path,
            allowFailure: false
        });

        SweepPlanLib.SweepPlan memory plan = SweepPlanLib.SweepPlan({
            owner: DEPLOYER,
            recipient: DEPLOYER,
            outputToken: USDC,
            deadline: block.timestamp + 7200,
            nonce: executor.nonces(DEPLOYER),
            displayManifestHash: keccak256("phase10-route-simulation"),
            swaps: swaps,
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });

        bytes memory sig = _sign(plan, deployerKey);

        uint256 usdcBefore = IERC20(USDC).balanceOf(DEPLOYER);
        uint256 dust3Before = IERC20(DUST3).balanceOf(DEPLOYER);

        vm.startBroadcast(deployerKey);
        bytes32 executionPlanHash = executor.executeSweep(plan, sig);
        vm.stopBroadcast();

        uint256 usdcAfter = IERC20(USDC).balanceOf(DEPLOYER);
        uint256 dust3After = IERC20(DUST3).balanceOf(DEPLOYER);

        console2.log("=== Simulation result ===");
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
