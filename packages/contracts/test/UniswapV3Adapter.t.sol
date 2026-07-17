// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Adapter} from "../src/adapters/UniswapV3Adapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSwapRouter02} from "./mocks/MockSwapRouter02.sol";

contract UniswapV3AdapterTest is Test {
    MockSwapRouter02 internal router;
    UniswapV3Adapter internal adapter;
    MockERC20 internal dust1;
    MockERC20 internal wmon;
    MockERC20 internal usdc;
    MockERC20 internal rogue;

    address internal owner = address(0xABCD);
    uint24 internal constant FEE = 3000;

    function setUp() public {
        router = new MockSwapRouter02();
        dust1 = new MockERC20("Dust1", "DUST1");
        wmon = new MockERC20("WMON", "WMON");
        usdc = new MockERC20("USDC", "USDC");
        rogue = new MockERC20("Rogue", "ROGUE");

        adapter = new UniswapV3Adapter(address(router), address(wmon), owner);
        router.setRatio(1, 1);

        dust1.mint(address(this), 10_000 ether);
    }

    function _path(address a, address b) internal pure returns (bytes memory) {
        return abi.encodePacked(a, FEE, b);
    }

    function _path3(address a, address b, address c) internal pure returns (bytes memory) {
        return abi.encodePacked(a, FEE, b, FEE, c);
    }

    function test_directPath_swapSucceeds() public {
        uint256 amountIn = 100 ether;
        dust1.approve(address(adapter), amountIn);
        uint256 out = adapter.swap(
            address(dust1), amountIn, address(usdc), 1, block.timestamp + 100, _path(address(dust1), address(usdc))
        );
        assertEq(out, amountIn);
        assertEq(usdc.balanceOf(address(this)), amountIn);
    }

    function test_multiHopPath_swapSucceeds() public {
        uint256 amountIn = 50 ether;
        dust1.approve(address(adapter), amountIn);
        uint256 out = adapter.swap(
            address(dust1),
            amountIn,
            address(usdc),
            1,
            block.timestamp + 100,
            _path3(address(dust1), address(wmon), address(usdc))
        );
        assertEq(out, amountIn);
        assertEq(usdc.balanceOf(address(this)), amountIn);
    }

    function test_pathTokenInMismatch_reverts() public {
        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(UniswapV3Adapter.PathTokenInMismatch.selector);
        adapter.swap(
            address(dust1), 1 ether, address(usdc), 1, block.timestamp + 100, _path(address(wmon), address(usdc))
        );
    }

    function test_pathTokenOutMismatch_reverts() public {
        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(UniswapV3Adapter.PathTokenOutMismatch.selector);
        adapter.swap(
            address(dust1), 1 ether, address(usdc), 1, block.timestamp + 100, _path(address(dust1), address(wmon))
        );
    }

    function test_unallowedIntermediateAsset_reverts() public {
        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(UniswapV3Adapter.IntermediateAssetNotAllowed.selector, address(rogue)));
        adapter.swap(
            address(dust1),
            1 ether,
            address(usdc),
            1,
            block.timestamp + 100,
            _path3(address(dust1), address(rogue), address(usdc))
        );
    }

    function test_expiredDeadline_reverts() public {
        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(UniswapV3Adapter.RouteExpired.selector);
        adapter.swap(
            address(dust1), 1 ether, address(usdc), 1, block.timestamp - 1, _path(address(dust1), address(usdc))
        );
    }

    function test_zeroMinAmountOut_reverts() public {
        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(UniswapV3Adapter.ZeroMinAmountOut.selector);
        adapter.swap(
            address(dust1), 1 ether, address(usdc), 0, block.timestamp + 100, _path(address(dust1), address(usdc))
        );
    }

    function test_routerReverts_bubblesRevert() public {
        router.setMode(MockSwapRouter02.Mode.REVERT);
        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert("MockSwapRouter02: forced revert");
        adapter.swap(
            address(dust1), 1 ether, address(usdc), 1, block.timestamp + 100, _path(address(dust1), address(usdc))
        );
    }

    function test_malformedPath_reverts() public {
        dust1.approve(address(adapter), 1 ether);
        vm.expectRevert(); // UniswapV3Path.MalformedPath
        adapter.swap(address(dust1), 1 ether, address(usdc), 1, block.timestamp + 100, hex"1234");
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
        vm.expectRevert(UniswapV3Adapter.ConfigurationIsFrozen.selector);
        adapter.allowIntermediateAsset(address(rogue));

        vm.prank(owner);
        vm.expectRevert(UniswapV3Adapter.ConfigurationIsFrozen.selector);
        adapter.disallowIntermediateAsset(address(wmon));
    }

    function test_freezeConfiguration_onlyOwner() public {
        vm.expectRevert();
        adapter.freezeConfiguration();
    }

    /// @dev Approval must reset to 0 after the call regardless of outcome (PRD §5.5) -
    /// verified here since the router mock doesn't consume the full allowance itself.
    function test_approvalResetAfterSwap() public {
        uint256 amountIn = 10 ether;
        dust1.approve(address(adapter), amountIn);
        adapter.swap(
            address(dust1), amountIn, address(usdc), 1, block.timestamp + 100, _path(address(dust1), address(usdc))
        );
        assertEq(dust1.allowance(address(adapter), address(router)), 0);
    }
}
