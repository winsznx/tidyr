// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapter} from "../interfaces/IAdapter.sol";
import {IPancakeFactory} from "../interfaces/IPancakeFactory.sol";
import {IPancakePair} from "../interfaces/IPancakePair.sol";

/// @title PancakeV2Adapter
/// @notice Routes a token -> ... -> tokenOut path through PancakeSwap V2 pairs, reading
/// pairs directly from the verified Monad factory and computing swap amounts itself via
/// the standard constant-product formula (0.3% fee) - the same math a Router02 would
/// use, but without depending on one, because PancakeSwap has not deployed a classic
/// Router on Monad (see docs/research/external-addresses.md, conflict C-1). Logic
/// mirrors UniswapV2Router02's well-known `_swap`/`getAmountsOut` implementation.
/// @dev Never holds funds between calls. Output always lands at the caller
/// (SweepExecutor), which enforces `minAmountOut` itself via balance deltas.
contract PancakeV2Adapter is IAdapter, Ownable2Step {
    using SafeERC20 for IERC20;

    IPancakeFactory public immutable FACTORY;
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
    error InvalidPath();
    error PathTokenInMismatch();
    error PathTokenOutMismatch();
    error IntermediateAssetNotAllowed(address token);
    error PairNotFound(address tokenA, address tokenB);
    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount(uint256 amountOut, uint256 minAmountOut);
    error ZeroAddress();
    error ConfigurationIsFrozen();

    modifier whenNotFrozen() {
        if (configurationFrozen) revert ConfigurationIsFrozen();
        _;
    }

    constructor(address factory_, address wmon_, address initialOwner_) Ownable(initialOwner_) {
        if (factory_ == address(0) || wmon_ == address(0) || initialOwner_ == address(0)) revert ZeroAddress();
        FACTORY = IPancakeFactory(factory_);
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

    /// @param routeData ABI-encoded `address[] path`, e.g. [DUST1, WMON] or [DUST1, WMON, USDC]
    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 deadline,
        bytes calldata routeData
    ) external returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert RouteExpired();
        if (minAmountOut == 0) revert ZeroMinAmountOut();

        address[] memory path = abi.decode(routeData, (address[]));
        _validatePath(path, tokenIn, tokenOut);

        uint256[] memory amounts = _getAmountsOut(amountIn, path);
        amountOut = amounts[amounts.length - 1];
        if (amountOut < minAmountOut) revert InsufficientOutputAmount(amountOut, minAmountOut);

        IERC20(tokenIn).safeTransferFrom(msg.sender, _pairFor(path[0], path[1]), amountIn);
        _swap(amounts, path, msg.sender);
    }

    function _validatePath(address[] memory path, address tokenIn, address tokenOut) internal view {
        if (path.length < 2) revert InvalidPath();
        if (path[0] != tokenIn) revert PathTokenInMismatch();
        if (path[path.length - 1] != tokenOut) revert PathTokenOutMismatch();
        for (uint256 i = 1; i < path.length - 1; i++) {
            if (!allowedIntermediateAssets[path[i]]) revert IntermediateAssetNotAllowed(path[i]);
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address to) private {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address recipient = i < path.length - 2 ? _pairFor(output, path[i + 2]) : to;
            IPancakePair(_pairFor(input, output)).swap(amount0Out, amount1Out, recipient, new bytes(0));
        }
    }

    function _getAmountsOut(uint256 amountIn, address[] memory path) private view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i], path[i + 1]);
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        private
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getReserves(address tokenA, address tokenB) private view returns (uint256 reserveA, uint256 reserveB) {
        address pair = _pairFor(tokenA, tokenB);
        (address token0,) = _sortTokens(tokenA, tokenB);
        (uint112 reserve0, uint112 reserve1,) = IPancakePair(pair).getReserves();
        (reserveA, reserveB) =
            tokenA == token0 ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
    }

    function _pairFor(address tokenA, address tokenB) private view returns (address pair) {
        pair = FACTORY.getPair(tokenA, tokenB);
        if (pair == address(0)) revert PairNotFound(tokenA, tokenB);
    }

    function _sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
