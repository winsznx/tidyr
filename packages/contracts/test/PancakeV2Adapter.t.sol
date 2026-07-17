// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PancakeV2Adapter} from "../src/adapters/PancakeV2Adapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPancakeFactory} from "./mocks/MockPancakeFactory.sol";
import {MockPancakePair} from "./mocks/MockPancakePair.sol";

contract PancakeV2AdapterTest is Test {
    MockPancakeFactory internal factory;
    PancakeV2Adapter internal adapter;
    MockERC20 internal dust1;
    MockERC20 internal wmon;
    MockERC20 internal usdc;
    MockERC20 internal rogue;

    MockPancakePair internal pairDustWmon;
    MockPancakePair internal pairWmonUsdc;

    address internal owner = address(0xABCD);

    function setUp() public {
        factory = new MockPancakeFactory();
        dust1 = new MockERC20("Dust1", "DUST1");
        wmon = new MockERC20("WMON", "WMON");
        usdc = new MockERC20("USDC", "USDC");
        rogue = new MockERC20("Rogue", "ROGUE");

        adapter = new PancakeV2Adapter(address(factory), address(wmon), owner);

        pairDustWmon = new MockPancakePair(address(dust1), address(wmon));
        dust1.mint(address(pairDustWmon), 100_000 ether);
        wmon.mint(address(pairDustWmon), 500 ether);
        _seed(pairDustWmon, address(dust1), 100_000 ether, address(wmon), 500 ether);
        factory.setPair(address(dust1), address(wmon), address(pairDustWmon));

        pairWmonUsdc = new MockPancakePair(address(wmon), address(usdc));
        wmon.mint(address(pairWmonUsdc), 500 ether);
        usdc.mint(address(pairWmonUsdc), 250_000 ether);
        _seed(pairWmonUsdc, address(wmon), 500 ether, address(usdc), 250_000 ether);
        factory.setPair(address(wmon), address(usdc), address(pairWmonUsdc));

        dust1.mint(address(this), 10_000 ether);
    }

    /// @dev `seedReserves(reserve0, reserve1)` is positional by the pair's own
    /// `token0`/`token1` (sorted by address) - this resolves that order from
    /// (tokenA, amountA)/(tokenB, amountB) pairs so callers can think in token terms.
    function _seed(MockPancakePair pair, address tokenA, uint256 amountA, address tokenB, uint256 amountB) internal {
        assertTrue(pair.token0() == tokenA || pair.token1() == tokenA);
        if (pair.token0() == tokenA) {
            pair.seedReserves(uint112(amountA), uint112(amountB));
        } else {
            pair.seedReserves(uint112(amountB), uint112(amountA));
        }
    }

    function _amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function test_directPath_swapSucceeds() public {
        uint256 amountIn = 1_000 ether;
        address[] memory path = new address[](2);
        path[0] = address(dust1);
        path[1] = address(wmon);

        uint256 expectedOut = _amountOut(amountIn, 100_000 ether, 500 ether);

        dust1.approve(address(adapter), amountIn);
        uint256 out = adapter.swap(address(dust1), amountIn, address(wmon), 1, block.timestamp + 100, abi.encode(path));

        assertEq(out, expectedOut);
        assertEq(wmon.balanceOf(address(this)), expectedOut);
    }

    function test_multiHopPath_swapSucceeds() public {
        uint256 amountIn = 1_000 ether;
        address[] memory path = new address[](3);
        path[0] = address(dust1);
        path[1] = address(wmon);
        path[2] = address(usdc);

        uint256 hop1Out = _amountOut(amountIn, 100_000 ether, 500 ether);
        uint256 hop2Out = _amountOut(hop1Out, 500 ether, 250_000 ether);

        dust1.approve(address(adapter), amountIn);
        uint256 out = adapter.swap(address(dust1), amountIn, address(usdc), 1, block.timestamp + 100, abi.encode(path));

        assertEq(out, hop2Out);
        assertEq(usdc.balanceOf(address(this)), hop2Out);
        assertEq(wmon.balanceOf(address(this)), 0); // intermediate hop token never lands with the caller
    }

    function test_pathTokenInMismatch_reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(wmon); // does not match tokenIn=dust1 below
        path[1] = address(usdc);

        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(PancakeV2Adapter.PathTokenInMismatch.selector);
        adapter.swap(address(dust1), 1 ether, address(usdc), 1, block.timestamp + 100, abi.encode(path));
    }

    function test_pathTokenOutMismatch_reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(dust1);
        path[1] = address(wmon); // does not match tokenOut=usdc below

        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(PancakeV2Adapter.PathTokenOutMismatch.selector);
        adapter.swap(address(dust1), 1 ether, address(usdc), 1, block.timestamp + 100, abi.encode(path));
    }

    function test_unallowedIntermediateAsset_reverts() public {
        address[] memory path = new address[](3);
        path[0] = address(dust1);
        path[1] = address(rogue); // never allowlisted
        path[2] = address(usdc);

        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(PancakeV2Adapter.IntermediateAssetNotAllowed.selector, address(rogue)));
        adapter.swap(address(dust1), 1 ether, address(usdc), 1, block.timestamp + 100, abi.encode(path));
    }

    function test_insufficientOutput_reverts() public {
        uint256 amountIn = 1_000 ether;
        address[] memory path = new address[](2);
        path[0] = address(dust1);
        path[1] = address(wmon);

        uint256 expectedOut = _amountOut(amountIn, 100_000 ether, 500 ether);

        dust1.approve(address(adapter), amountIn);
        vm.expectRevert(
            abi.encodeWithSelector(PancakeV2Adapter.InsufficientOutputAmount.selector, expectedOut, expectedOut + 1)
        );
        adapter.swap(address(dust1), amountIn, address(wmon), expectedOut + 1, block.timestamp + 100, abi.encode(path));
    }

    function test_expiredDeadline_reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(dust1);
        path[1] = address(wmon);

        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(PancakeV2Adapter.RouteExpired.selector);
        adapter.swap(address(dust1), 1 ether, address(wmon), 1, block.timestamp - 1, abi.encode(path));
    }

    function test_zeroMinAmountOut_reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(dust1);
        path[1] = address(wmon);

        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(PancakeV2Adapter.ZeroMinAmountOut.selector);
        adapter.swap(address(dust1), 1 ether, address(wmon), 0, block.timestamp + 100, abi.encode(path));
    }

    function test_pairNotFound_reverts() public {
        MockERC20 unlisted = new MockERC20("Unlisted", "UNL");
        address[] memory path = new address[](2);
        path[0] = address(dust1);
        path[1] = address(unlisted);

        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(PancakeV2Adapter.PairNotFound.selector, address(dust1), address(unlisted))
        );
        adapter.swap(address(dust1), 1 ether, address(unlisted), 1, block.timestamp + 100, abi.encode(path));
    }

    function test_onlyOwner_canManageIntermediateAssets() public {
        vm.expectRevert();
        adapter.allowIntermediateAsset(address(rogue));

        vm.prank(owner);
        adapter.allowIntermediateAsset(address(rogue));
        assertTrue(adapter.allowedIntermediateAssets(address(rogue)));

        vm.prank(owner);
        adapter.disallowIntermediateAsset(address(rogue));
        assertFalse(adapter.allowedIntermediateAssets(address(rogue)));
    }

    function test_freezeConfiguration_blocksIntermediateAssetChanges() public {
        vm.prank(owner);
        adapter.freezeConfiguration();
        assertTrue(adapter.configurationFrozen());

        vm.prank(owner);
        vm.expectRevert(PancakeV2Adapter.ConfigurationIsFrozen.selector);
        adapter.allowIntermediateAsset(address(rogue));

        vm.prank(owner);
        vm.expectRevert(PancakeV2Adapter.ConfigurationIsFrozen.selector);
        adapter.disallowIntermediateAsset(address(wmon));
    }

    function test_freezeConfiguration_onlyOwner() public {
        vm.expectRevert();
        adapter.freezeConfiguration();
    }
}
