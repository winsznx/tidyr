// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapter} from "../interfaces/IAdapter.sol";
import {ISwapRouter02} from "../interfaces/ISwapRouter02.sol";
import {UniswapV3Path} from "../libraries/UniswapV3Path.sol";

/// @title UniswapV3Adapter
/// @notice Routes a token -> ... -> tokenOut path through Uniswap V3 pools via
/// SwapRouter02's `exactInput`. Per conflict C-7 (docs/requirements-traceability.md),
/// this calls SwapRouter02 directly rather than wrapping Universal Router's generic
/// command-byte interface: SwapRouter02 is verified deployed on Monad mainnet with a
/// fixed, non-generic function signature, which is a strictly smaller attack surface
/// than allowlisting Universal Router command bytes for the same capability.
/// @dev Never holds funds between calls. Output always lands at the caller
/// (SweepExecutor), which enforces `minAmountOut` itself via balance deltas.
contract UniswapV3Adapter is IAdapter, Ownable2Step {
    using SafeERC20 for IERC20;
    using UniswapV3Path for bytes;

    ISwapRouter02 public immutable ROUTER;
    address public immutable WMON;

    mapping(address => bool) public allowedIntermediateAssets;

    /// @dev Security-addendum hardening (pre-Phase-7 review): see SweepExecutor's
    /// `configurationFrozen` for rationale - same irreversible-lock pattern here.
    bool public configurationFrozen;

    event IntermediateAssetAllowed(address indexed token);
    event IntermediateAssetDisallowed(address indexed token);
    event ConfigurationFrozen();

    error RouteExpired();
    error ZeroMinAmountOut();
    error PathTokenInMismatch();
    error PathTokenOutMismatch();
    error IntermediateAssetNotAllowed(address token);
    error ZeroAddress();
    error ConfigurationIsFrozen();

    modifier whenNotFrozen() {
        if (configurationFrozen) revert ConfigurationIsFrozen();
        _;
    }

    constructor(address router_, address wmon_, address initialOwner_) Ownable(initialOwner_) {
        if (router_ == address(0) || wmon_ == address(0) || initialOwner_ == address(0)) revert ZeroAddress();
        ROUTER = ISwapRouter02(router_);
        WMON = wmon_;
        allowedIntermediateAssets[wmon_] = true;
        emit IntermediateAssetAllowed(wmon_);
    }

    function allowIntermediateAsset(address token) external onlyOwner whenNotFrozen {
        if (token == address(0)) revert ZeroAddress();
        allowedIntermediateAssets[token] = true;
        emit IntermediateAssetAllowed(token);
    }

    function disallowIntermediateAsset(address token) external onlyOwner whenNotFrozen {
        allowedIntermediateAssets[token] = false;
        emit IntermediateAssetDisallowed(token);
    }

    function freezeConfiguration() external onlyOwner {
        configurationFrozen = true;
        emit ConfigurationFrozen();
    }

    /// @param routeData the raw Uniswap V3 packed path bytes (token|fee|token|fee|token...)
    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minAmountOut, uint256 deadline, bytes calldata routeData)
        external
        returns (uint256 amountOut)
    {
        if (block.timestamp > deadline) revert RouteExpired();
        if (minAmountOut == 0) revert ZeroMinAmountOut();

        bytes memory path = routeData;
        _validatePath(path, tokenIn, tokenOut);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);

        amountOut = ROUTER.exactInput(
            ISwapRouter02.ExactInputParams({
                path: path,
                recipient: msg.sender,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut
            })
        );

        IERC20(tokenIn).forceApprove(address(ROUTER), 0);
    }

    function _validatePath(bytes memory path, address tokenIn, address tokenOut) private view {
        uint256 hops = path.numHops();
        if (path.tokenAt(0) != tokenIn) revert PathTokenInMismatch();
        if (path.tokenAt(hops) != tokenOut) revert PathTokenOutMismatch();
        for (uint256 i = 1; i < hops; i++) {
            address intermediate = path.tokenAt(i);
            if (!allowedIntermediateAssets[intermediate]) revert IntermediateAssetNotAllowed(intermediate);
        }
    }
}
