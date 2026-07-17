// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PancakeV2Adapter} from "../src/adapters/PancakeV2Adapter.sol";
import {IPancakePair} from "../src/interfaces/IPancakePair.sol";
import {IWMON} from "../src/interfaces/IWMON.sol";

/// @notice Fork test against the REAL, live PancakeSwap V2 factory and a REAL,
/// currently-liquid WMON/USDC pair on Monad mainnet (see docs/research/external-addresses.md
/// for verification of these addresses). Requires network access; run explicitly with
/// `forge test --match-contract PancakeV2AdapterForkTest` (excluded from the default
/// offline suite by CI's fork-test filtering, matching the PRD's "mainnet-fork quote and
/// swap tests where RPC capability permits" acceptance criterion).
contract PancakeV2AdapterForkTest is Test {
    address internal constant FACTORY = 0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E;
    address internal constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;

    PancakeV2Adapter internal adapter;
    address internal owner = address(0xABCD);
    address internal trader = address(0xF00D);

    function setUp() public {
        vm.createSelectFork("https://rpc.monad.xyz");
        adapter = new PancakeV2Adapter(FACTORY, WMON, owner);
    }

    function test_realFactory_hasLiveWmonUsdcPair() public view {
        address pair = IPancakeFactoryView(FACTORY).getPair(WMON, USDC);
        assertTrue(pair != address(0), "expected a live WMON/USDC pair on Monad mainnet");
        (uint112 r0, uint112 r1,) = IPancakePair(pair).getReserves();
        assertTrue(r0 > 0 && r1 > 0, "expected non-zero reserves on the live pair");
    }

    function test_realSwap_wmonToUsdc_succeeds() public {
        address pair = IPancakeFactoryView(FACTORY).getPair(WMON, USDC);
        (uint112 reserve0, uint112 reserve1,) = IPancakePair(pair).getReserves();
        (uint256 reserveWmon, uint256 reserveUsdc) =
            IPancakePair(pair).token0() == WMON ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));

        // Small relative to real (thin) live liquidity, to keep slippage realistic.
        uint256 amountIn = reserveWmon / 100;
        vm.assume(amountIn > 0);

        vm.deal(trader, amountIn);
        vm.prank(trader);
        IWMON(WMON).deposit{value: amountIn}();

        uint256 amountInWithFee = amountIn * 997;
        uint256 expectedOut = (amountInWithFee * reserveUsdc) / (reserveWmon * 1000 + amountInWithFee);
        vm.assume(expectedOut > 0);

        address[] memory path = new address[](2);
        path[0] = WMON;
        path[1] = USDC;

        vm.prank(trader);
        IERC20(WMON).approve(address(adapter), amountIn);

        vm.prank(trader);
        uint256 amountOut = adapter.swap(WMON, amountIn, USDC, 1, block.timestamp + 300, abi.encode(path));

        assertEq(amountOut, expectedOut);
        assertEq(IERC20(USDC).balanceOf(trader), expectedOut);
    }
}

interface IPancakeFactoryView {
    function getPair(address tokenA, address tokenB) external view returns (address);
}
