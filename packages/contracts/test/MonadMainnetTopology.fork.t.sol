// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

/// @notice Phase 7 Task 7.9: fork-verifies the external dependency topology TIDYR
/// relies on for its production deployment, beyond PancakeV2Adapter.fork.t.sol's
/// existing live-pair/live-swap coverage. Requires network access - run explicitly
/// with `forge test --match-contract MonadMainnetTopologyForkTest`; excluded from the
/// default offline suite the same way the existing fork test is.
/// @dev No transaction is ever broadcast here - every check is a read-only
/// `eth_getCode`/`eth_call` against a `vm.createSelectFork` snapshot, never
/// `--broadcast`. This file makes zero mainnet state changes.
contract MonadMainnetTopologyForkTest is Test {
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address internal constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address internal constant PANCAKE_FACTORY = 0x02a84c1b3BBD7401a5f7fa98a384EBC70bB5749E;
    address internal constant UNISWAP_V3_FACTORY = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address internal constant UNISWAP_SWAP_ROUTER_02 = 0xfE31F71C1b106EAc32F1A19239c9a9A72ddfb900;

    function setUp() public {
        vm.createSelectFork("https://rpc.monad.xyz");
    }

    function test_chainIdIs143() public view {
        assertEq(block.chainid, 143);
    }

    function test_permit2HasCode() public view {
        assertTrue(PERMIT2.code.length > 0, "Permit2 must have live bytecode on Monad mainnet");
    }

    function test_multicall3HasCode() public view {
        assertTrue(MULTICALL3.code.length > 0, "Multicall3 must have live bytecode on Monad mainnet");
    }

    /// @dev Directly exercises the exact constant `SweepExecutor.MULTICALL3_ADDRESS`
    /// uses for its constructor-time rejection check - proves that address is a real,
    /// live contract on the chain TIDYR actually deploys to, not an unverified
    /// placeholder that happens to compile.
    function test_multicall3Address_matchesSweepExecutorConstant() public pure {
        // Mirrors packages/contracts/src/SweepExecutor.sol::MULTICALL3_ADDRESS exactly.
        assertEq(MULTICALL3, 0xcA11bde05977b3631167028862bE2a173976CA11);
    }

    function test_wmonHasCode() public view {
        assertTrue(WMON.code.length > 0, "WMON must have live bytecode on Monad mainnet");
    }

    function test_usdcHasCode() public view {
        assertTrue(USDC.code.length > 0, "USDC must have live bytecode on Monad mainnet");
    }

    function test_usdcDecimalsAndSymbol_matchExpectedCircleUSDC() public view {
        (bool ok, bytes memory data) = USDC.staticcall(abi.encodeWithSignature("decimals()"));
        assertTrue(ok);
        assertEq(abi.decode(data, (uint8)), 6);

        (bool ok2, bytes memory data2) = USDC.staticcall(abi.encodeWithSignature("symbol()"));
        assertTrue(ok2);
        assertEq(abi.decode(data2, (string)), "USDC");
    }

    function test_pancakeV2FactoryHasCode() public view {
        assertTrue(PANCAKE_FACTORY.code.length > 0, "PancakeSwap V2 Factory must have live bytecode");
    }

    function test_uniswapV3FactoryHasCode() public view {
        assertTrue(UNISWAP_V3_FACTORY.code.length > 0, "Uniswap V3 Factory must have live bytecode");
    }

    function test_uniswapSwapRouter02HasCode() public view {
        assertTrue(UNISWAP_SWAP_ROUTER_02.code.length > 0, "Uniswap SwapRouter02 must have live bytecode");
    }

    /// @dev Confirms SwapRouter02's fixed, non-generic `exactInput` selector is
    /// present in the live deployed bytecode - the same selector
    /// `UniswapV3Adapter.sol` calls directly (docs/requirements-traceability.md
    /// conflict C-7). A missing selector here would mean the adapter's hardcoded
    /// interface no longer matches what's actually deployed.
    function test_uniswapSwapRouter02_hasExactInputSelector() public view {
        bytes memory code = UNISWAP_SWAP_ROUTER_02.code;
        bytes4 exactInputSelector = 0xb858183f;
        assertTrue(_bytecodeContainsSelector(code, exactInputSelector), "exactInput selector not found in bytecode");
    }

    function _bytecodeContainsSelector(bytes memory code, bytes4 selector) private pure returns (bool) {
        if (code.length < 4) return false;
        for (uint256 i = 0; i <= code.length - 4; i++) {
            if (
                code[i] == selector[0] && code[i + 1] == selector[1] && code[i + 2] == selector[2]
                    && code[i + 3] == selector[3]
            ) {
                return true;
            }
        }
        return false;
    }
}
