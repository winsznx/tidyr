// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
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

/// @notice Phase 10 pre-broadcast smoke test: forks live Monad mainnet, seeds a small
/// real DUST3/WMON Uniswap V3 pool with the deployer's own (already-owned, fixed-supply)
/// DUST3 balance, and drives the full DUST3 -> WMON -> USDC multihop route through the
/// REAL, already-deployed SweepExecutor + UniswapV3Adapter and the REAL, deep WMON/USDC
/// Uniswap V3 pool. No transaction here ever broadcasts to real mainnet - every state
/// change happens on an isolated `vm.createSelectFork` snapshot. Run explicitly:
/// `forge test --match-contract Phase10RouteSmokeForkTest -vv` (requires network access,
/// excluded from the default offline suite the same way the other `.fork.t.sol` tests are).
contract Phase10RouteSmokeForkTest is Test {
    address internal constant DEPLOYER = 0xbde0076F05B5eA898F9ca51f1b595D84598DE586;
    address internal constant SWEEP_EXECUTOR = 0x7a844005998e896967A8b2BdA13c7826F387E9c3;
    address internal constant DUST3 = 0x1B7EB110BDc1D0b7F85046EC812Be77958E8b3c3;
    address internal constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant V3_FACTORY = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address internal constant NFPM = 0x7197E214c0b767cFB76Fb734ab638E2c192F4E53;
    uint24 internal constant DUST3_WMON_FEE = 3000;
    uint24 internal constant WMON_USDC_FEE = 3000;

    string internal constant PERMIT_BATCH_WITNESS_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    uint256 internal deployerKey;
    SweepExecutor internal executor;
    bytes internal path;

    function setUp() public {
        vm.createSelectFork("https://rpc.monad.xyz");
        executor = SweepExecutor(payable(SWEEP_EXECUTOR));
        path = abi.encodePacked(DUST3, DUST3_WMON_FEE, WMON, WMON_USDC_FEE, USDC);

        // Pool setup impersonates the real deployer via vm.prank (its private key is
        // never available to this test). executeSweep itself needs a real Permit2
        // signature, so a throwaway test key signs as owner/recipient of the plan,
        // funded via a real DUST3 transfer from the deployer below.
        deployerKey = 0xA11CE;
    }

    function _seedPoolAndPosition(address dust3Holder) internal returns (uint256 dust3Available) {
        vm.deal(dust3Holder, 30 ether);
        vm.prank(dust3Holder);
        IWMON(WMON).deposit{value: 20 ether}();

        (address token0, address token1) = DUST3 < WMON ? (DUST3, WMON) : (WMON, DUST3);
        address pool = IUniswapV3FactoryMinimal(V3_FACTORY).getPool(DUST3, WMON, DUST3_WMON_FEE);
        if (pool == address(0)) {
            vm.prank(dust3Holder);
            pool = IUniswapV3FactoryMinimal(V3_FACTORY).createPool(DUST3, WMON, DUST3_WMON_FEE);
            vm.prank(dust3Holder);
            IUniswapV3PoolMinimal(pool).initialize(792281625142643392428113920);
        }

        dust3Available = IERC20(DUST3).balanceOf(dust3Holder);
        uint256 dust3ForPool = 200_000 ether;
        require(dust3Available >= dust3ForPool, "deployer holds insufficient real DUST3 for this fork test");

        vm.startPrank(dust3Holder);
        IERC20(DUST3).approve(NFPM, dust3ForPool);
        IERC20(WMON).approve(NFPM, 20 ether);

        (uint256 amount0Desired, uint256 amount1Desired) =
            token0 == DUST3 ? (dust3ForPool, uint256(20 ether)) : (uint256(20 ether), dust3ForPool);

        INonfungiblePositionManagerMinimal(NFPM)
            .mint(
                INonfungiblePositionManagerMinimal.MintParams({
                token0: token0,
                token1: token1,
                fee: DUST3_WMON_FEE,
                tickLower: -98160,
                tickUpper: -86160,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: dust3Holder,
                deadline: block.timestamp + 7200
            })
            );
        vm.stopPrank();

        // Fund a fresh test signer with real DUST3 (transferred, not minted -
        // DemoToken has a fixed supply and no mint function) so the executeSweep
        // signer is independent of the real deployer's mainnet private key.
        address signer = vm.addr(deployerKey);
        uint256 swapAmount = 10_000 ether;
        vm.prank(dust3Holder);
        IERC20(DUST3).transfer(signer, swapAmount);
    }

    function _buildPlan(uint256 amountIn, uint256 minAmountOut, uint256 deadline, uint256 nonce)
        internal
        view
        returns (SweepPlanLib.SweepPlan memory plan)
    {
        SweepPlanLib.SwapAction[] memory swaps = new SweepPlanLib.SwapAction[](1);
        swaps[0] = SweepPlanLib.SwapAction({
            tokenIn: DUST3,
            amountIn: amountIn,
            adapterKind: SweepPlanLib.AdapterKind.UNISWAP_V3,
            minAmountOut: minAmountOut,
            routeData: path,
            allowFailure: false
        });

        address signer = vm.addr(deployerKey);
        plan = SweepPlanLib.SweepPlan({
            owner: signer,
            recipient: signer,
            outputToken: USDC,
            deadline: deadline,
            nonce: nonce,
            displayManifestHash: keccak256("phase10-route-smoke"),
            swaps: swaps,
            transfers: new SweepPlanLib.TransferAction[](0),
            discards: new SweepPlanLib.DiscardAction[](0),
            burns: new SweepPlanLib.BurnAction[](0)
        });
    }

    function _sign(SweepPlanLib.SweepPlan memory plan) internal view returns (bytes memory signature) {
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digest);
        signature = bytes.concat(r, s, bytes1(v));
    }

    /// @notice Full route works end-to-end: correct adapter selected, correct router
    /// called (proven transitively - UniswapV3Adapter is the only adapter that accepts
    /// a >20-byte multihop `routeData` path), SweepExecutor never retains funds, final
    /// recipient receives USDC, and the plan's nonce is consumed exactly once.
    function test_dust3ToUsdcMultihopRouteSucceeds() public {
        _seedPoolAndPosition(DEPLOYER);
        address signer = vm.addr(deployerKey);

        vm.prank(signer);
        IERC20(DUST3).approve(PERMIT2, type(uint256).max);

        uint256 nonceBefore = executor.nonces(signer);
        SweepPlanLib.SweepPlan memory plan = _buildPlan(10_000 ether, 1, block.timestamp + 7200, nonceBefore);
        bytes memory sig = _sign(plan);

        uint256 usdcBefore = IERC20(USDC).balanceOf(signer);

        vm.prank(signer);
        executor.executeSweep(plan, sig);

        assertGt(IERC20(USDC).balanceOf(signer), usdcBefore, "signer must receive USDC output");
        assertEq(IERC20(USDC).balanceOf(SWEEP_EXECUTOR), 0, "executor must not retain USDC");
        assertEq(IERC20(DUST3).balanceOf(SWEEP_EXECUTOR), 0, "executor must not retain DUST3");
        assertEq(executor.nonces(signer), nonceBefore + 1, "nonce must be consumed exactly once");
    }

    /// @notice Required smoke test: an unreasonably high minAmountOut must cause the
    /// whole sweep to revert (proves minAmountOut is actually enforced against the
    /// real Uniswap V3 router output, not silently ignored).
    function test_excessiveMinAmountOutReverts() public {
        _seedPoolAndPosition(DEPLOYER);
        address signer = vm.addr(deployerKey);

        vm.prank(signer);
        IERC20(DUST3).approve(PERMIT2, type(uint256).max);

        uint256 nonceBefore = executor.nonces(signer);
        SweepPlanLib.SweepPlan memory plan =
            _buildPlan(10_000 ether, type(uint256).max, block.timestamp + 7200, nonceBefore);
        bytes memory sig = _sign(plan);

        vm.prank(signer);
        vm.expectRevert();
        executor.executeSweep(plan, sig);

        assertEq(executor.nonces(signer), nonceBefore, "failed sweep must not consume the nonce");
    }

    /// @notice Required smoke test: a plan whose deadline has already passed must
    /// revert rather than execute against stale pricing.
    function test_expiredDeadlineReverts() public {
        _seedPoolAndPosition(DEPLOYER);
        address signer = vm.addr(deployerKey);

        vm.prank(signer);
        IERC20(DUST3).approve(PERMIT2, type(uint256).max);

        uint256 nonceBefore = executor.nonces(signer);
        // Build with a future deadline so signing (which reads block.timestamp only
        // indirectly via the plan) is unaffected, then warp past it before executing.
        SweepPlanLib.SweepPlan memory plan = _buildPlan(10_000 ether, 1, block.timestamp + 60, nonceBefore);
        bytes memory sig = _sign(plan);

        vm.warp(block.timestamp + 3600);

        vm.prank(signer);
        vm.expectRevert();
        executor.executeSweep(plan, sig);

        assertEq(executor.nonces(signer), nonceBefore, "expired sweep must not consume the nonce");
    }
}
