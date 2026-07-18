// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PancakeV2Adapter} from "../src/adapters/PancakeV2Adapter.sol";
import {UniswapV3Adapter} from "../src/adapters/UniswapV3Adapter.sol";
import {MockPancakeFactory} from "./mocks/MockPancakeFactory.sol";
import {MockPancakePair} from "./mocks/MockPancakePair.sol";
import {MockSwapRouter02} from "./mocks/MockSwapRouter02.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWMON} from "./mocks/MockWMON.sol";

/// @notice Phase 7 Task 7.12: closes constructor/input-validation branches `forge
/// coverage` identified as untested on both adapters - none of these were previously
/// exercised with an actual zero-address constructor argument or a too-short path.
contract AdapterCompletenessTest is Test {
    MockPancakeFactory internal pancakeFactory;
    MockSwapRouter02 internal v3Router;
    MockWMON internal wmon;
    address internal owner = address(0xABCD);

    function setUp() public {
        pancakeFactory = new MockPancakeFactory();
        v3Router = new MockSwapRouter02();
        wmon = new MockWMON();
    }

    function test_pancakeV2Adapter_constructor_rejectsZeroFactory() public {
        vm.expectRevert(PancakeV2Adapter.ZeroAddress.selector);
        new PancakeV2Adapter(address(0), address(wmon), owner);
    }

    function test_pancakeV2Adapter_constructor_rejectsZeroWmon() public {
        vm.expectRevert(PancakeV2Adapter.ZeroAddress.selector);
        new PancakeV2Adapter(address(pancakeFactory), address(0), owner);
    }

    /// @dev OZ's own `Ownable(initialOwner_)` constructor runs before this contract's
    /// body, so a zero owner reverts with OZ's `OwnableInvalidOwner`, not this
    /// contract's own `ZeroAddress` - the `initialOwner_ == address(0)` clause in
    /// `PancakeV2Adapter`'s own check is consequently unreachable for this specific
    /// field (belt-and-suspenders validation order, not a bug: the address is
    /// rejected either way, just by a different error).
    function test_pancakeV2Adapter_constructor_rejectsZeroOwner() public {
        vm.expectRevert();
        new PancakeV2Adapter(address(pancakeFactory), address(wmon), address(0));
    }

    function test_uniswapV3Adapter_constructor_rejectsZeroRouter() public {
        vm.expectRevert(UniswapV3Adapter.ZeroAddress.selector);
        new UniswapV3Adapter(address(0), address(wmon), owner);
    }

    function test_uniswapV3Adapter_constructor_rejectsZeroWmon() public {
        vm.expectRevert(UniswapV3Adapter.ZeroAddress.selector);
        new UniswapV3Adapter(address(v3Router), address(0), owner);
    }

    /// @dev Same unreachable-clause note as
    /// `test_pancakeV2Adapter_constructor_rejectsZeroOwner` above.
    function test_uniswapV3Adapter_constructor_rejectsZeroOwner() public {
        vm.expectRevert();
        new UniswapV3Adapter(address(v3Router), address(wmon), address(0));
    }

    function test_pancakeV2Adapter_allowIntermediateAsset_rejectsZeroAddress() public {
        PancakeV2Adapter adapter = new PancakeV2Adapter(address(pancakeFactory), address(wmon), owner);
        vm.prank(owner);
        vm.expectRevert(PancakeV2Adapter.ZeroAddress.selector);
        adapter.allowIntermediateAsset(address(0));
    }

    function test_uniswapV3Adapter_allowIntermediateAsset_rejectsZeroAddress() public {
        UniswapV3Adapter adapter = new UniswapV3Adapter(address(v3Router), address(wmon), owner);
        vm.prank(owner);
        vm.expectRevert(UniswapV3Adapter.ZeroAddress.selector);
        adapter.allowIntermediateAsset(address(0));
    }

    /// @dev `swap` with `amountIn == 0` must revert `InsufficientInputAmount` from the
    /// adapter's own constant-product math, not silently succeed with zero output.
    function test_pancakeV2Adapter_zeroAmountIn_reverts() public {
        MockERC20 dust = new MockERC20("Dust", "DUST");
        MockERC20 usdc = new MockERC20("USDC", "USDC");
        MockPancakePair pair = new MockPancakePair(address(dust), address(usdc));
        dust.mint(address(pair), 1_000 ether);
        usdc.mint(address(pair), 1_000 ether);
        pair.seedReserves(1_000 ether, 1_000 ether);
        pancakeFactory.setPair(address(dust), address(usdc), address(pair));

        PancakeV2Adapter adapter = new PancakeV2Adapter(address(pancakeFactory), address(wmon), owner);
        address[] memory path = new address[](2);
        path[0] = address(dust);
        path[1] = address(usdc);

        vm.expectRevert(PancakeV2Adapter.InsufficientInputAmount.selector);
        adapter.swap(address(dust), 0, address(usdc), 1, block.timestamp + 300, abi.encode(path));
    }

    /// @dev A single-token "path" (length 1) must revert `InvalidPath` - a path needs
    /// at least an input and an output token.
    function test_pancakeV2Adapter_tooShortPath_reverts() public {
        MockERC20 dust = new MockERC20("Dust", "DUST");
        PancakeV2Adapter adapter = new PancakeV2Adapter(address(pancakeFactory), address(wmon), owner);

        address[] memory path = new address[](1);
        path[0] = address(dust);

        vm.expectRevert(PancakeV2Adapter.InvalidPath.selector);
        adapter.swap(address(dust), 100 ether, address(dust), 1, block.timestamp + 300, abi.encode(path));
    }
}
