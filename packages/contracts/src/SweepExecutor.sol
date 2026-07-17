// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {SweepPlanLib} from "./libraries/SweepPlanLib.sol";
import {TidyrWitness} from "./libraries/TidyrWitness.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {IBurnable} from "./interfaces/IBurnable.sol";
import {IWMON} from "./interfaces/IWMON.sol";

/// @dev Narrow read-only view onto a fixed adapter's own freeze flag. Used only
/// against `SweepExecutor.PANCAKE_V2_ADAPTER`/`UNISWAP_V3_ADAPTER` - two specific,
/// immutable-address, audited contracts fixed at construction - never an arbitrary or
/// attacker-influenceable address. See `SweepExecutor`'s contract-level note.
interface IFreezeCheck {
    function configurationFrozen() external view returns (bool);
}

/// @title SweepExecutor
/// @notice TIDYR's core execution contract. Pulls exactly the tokens a signed plan
/// authorizes (via a Permit2 witness bound to the plan's executionPlanHash), runs
/// swaps through exactly two immutable, audited adapters, performs
/// transfers/discards/burns, settles the plan's output to its recipient, and returns
/// any unconsumed input to the plan's owner.
/// @dev Immutable, non-upgradeable, no delegatecall, no arbitrary external targets.
/// Reflects PRD §19 corrections: no executor-side RevokeAction (§19.2), plan-fund
/// isolation from pre-existing balances (§19.10), and the corrected allowFailure
/// semantics where a low-output "success" is treated as an adapter invariant
/// violation, not a soft failure (§19.9).
///
/// V1 has no owner-managed adapter registry (Codex addendum re-audit finding RA-01,
/// superseding CA-01/CA-02's earlier registry-plus-freeze design). That design let the
/// owner register any contract and trusted that contract's self-reported
/// `configurationFrozen()` value - a malicious or upgradeable adapter could forge
/// `true` while remaining mutable, so a "frozen" executor never actually established an
/// immutable reviewed execution boundary. There is nothing left to forge: every
/// `SwapAction.adapterKind` resolves to one of exactly two addresses fixed at
/// construction and never changeable afterward. A new DEX integration requires a new
/// SweepExecutor deployment, not a registry change.
///
/// A follow-up narrow re-audit correctly noted two remaining gaps in that design:
/// (1) the constructor accepted any nonzero address for either adapter slot - an EOA,
/// a duplicate, or Multicall3's own address - with no validation beyond nonzero, and
/// (2) freezing this contract said nothing about whether the two fixed adapters'
/// *own* mutable configuration (their `allowedIntermediateAssets`) was also locked,
/// so a "frozen" executor could still route through an adapter whose intermediate-
/// asset allowlist an owner could keep changing. Both are addressed below: the
/// constructor now rejects EOAs (`extcodesize == 0`), a duplicate pair, and
/// Multicall3's real, verified address; and `freezeConfiguration` now requires both
/// fixed adapters to have already frozen themselves. This is not a reintroduction of
/// RA-01's forgeable-registry pattern - it reads `configurationFrozen()` from exactly
/// the two specific, immutable-address contracts fixed at construction (not an
/// attacker-influenceable, arbitrary-address registry). What it cannot do from inside
/// a constructor is prove the deployed bytecode at those addresses is genuinely the
/// audited `PancakeV2Adapter`/`UniswapV3Adapter` source - that is a deployment-script
/// and code-verification responsibility (Phase 9), the same trust boundary every
/// immutable dependency here (`PERMIT2`, `WMON`) already relies on.
contract SweepExecutor is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum ActionType {
        SWAP,
        TRANSFER,
        DISCARD,
        BURN
    }

    ISignatureTransfer public immutable PERMIT2;
    IWMON public immutable WMON;

    /// @dev The only two adapters SweepExecutor will ever call, resolved from each
    /// swap's `AdapterKind`. Fixed at construction, never changeable - see the
    /// contract-level note above.
    IAdapter public immutable PANCAKE_V2_ADAPTER;
    IAdapter public immutable UNISWAP_V3_ADAPTER;

    /// @dev Verified real Multicall3 deployment (docs/research/external-addresses.md).
    /// Explicitly rejected as either adapter slot at construction - see the
    /// contract-level note above.
    address public constant MULTICALL3_ADDRESS = 0xcA11bde05977b3631167028862bE2a173976CA11;

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @dev Matches packages/shared/src/actions.ts::MON_NATIVE_SENTINEL exactly.
    address public constant MON_NATIVE_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    mapping(address => uint256) public nonces;
    mapping(address => bool) public allowedOutputTokens;

    /// @dev Once true, the output-token registry can never change again. Mitigates a
    /// compromised- or coerced-owner adding an unreviewed output asset after users have
    /// started trusting this deployment. Adapters need no equivalent flag - they were
    /// never mutable at the executor level in the first place.
    bool public configurationFrozen;

    event OutputTokenAllowed(address indexed token);
    event OutputTokenDisallowed(address indexed token);
    event StrayTokensRecovered(address indexed token, uint256 amount, address indexed to);
    event ConfigurationFrozen();

    event ActionExecuted(
        bytes32 indexed executionPlanHash,
        uint256 indexed actionIndex,
        uint8 indexed actionType,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address destination
    );

    event ActionFailed(
        bytes32 indexed executionPlanHash,
        uint256 indexed actionIndex,
        uint8 indexed actionType,
        address token,
        bytes32 reasonHash
    );

    event SweepCompleted(
        bytes32 indexed executionPlanHash,
        bytes32 indexed displayManifestHash,
        address indexed owner,
        address recipient,
        address outputToken,
        uint256 outputAmount,
        uint256 successfulActions,
        uint256 failedActions
    );

    error NotPlanOwner();
    error ZeroRecipient();
    error OutputTokenNotAllowed(address token);
    error PlanExpired();
    error InvalidPlanNonce(uint256 expected, uint256 provided);
    error AmbiguousSwapToken(address token);
    error UnexpectedPulledAmount(address token, uint256 expected, uint256 actual);
    error AdapterInvariantViolation(address adapter, uint256 actualOut, uint256 minRequired);
    error NativeTransferFailed();
    error ZeroAddress();
    error ConfigurationIsFrozen();
    error AdapterHasNoCode(address adapter);
    error DuplicateAdapterAddress(address adapter);
    error AdapterIsMulticall3();
    error AdapterNotYetFrozen(address adapter);

    constructor(
        address permit2_,
        address wmon_,
        address pancakeV2Adapter_,
        address uniswapV3Adapter_,
        address initialOwner_
    ) Ownable(initialOwner_) {
        if (
            permit2_ == address(0) || wmon_ == address(0) || pancakeV2Adapter_ == address(0)
                || uniswapV3Adapter_ == address(0) || initialOwner_ == address(0)
        ) revert ZeroAddress();
        if (pancakeV2Adapter_ == MULTICALL3_ADDRESS || uniswapV3Adapter_ == MULTICALL3_ADDRESS) {
            revert AdapterIsMulticall3();
        }
        if (pancakeV2Adapter_ == uniswapV3Adapter_) revert DuplicateAdapterAddress(pancakeV2Adapter_);
        if (pancakeV2Adapter_.code.length == 0) revert AdapterHasNoCode(pancakeV2Adapter_);
        if (uniswapV3Adapter_.code.length == 0) revert AdapterHasNoCode(uniswapV3Adapter_);

        PERMIT2 = ISignatureTransfer(permit2_);
        WMON = IWMON(wmon_);
        PANCAKE_V2_ADAPTER = IAdapter(pancakeV2Adapter_);
        UNISWAP_V3_ADAPTER = IAdapter(uniswapV3Adapter_);
        allowedOutputTokens[MON_NATIVE_SENTINEL] = true;
        emit OutputTokenAllowed(MON_NATIVE_SENTINEL);
    }

    /// @notice Resolves a swap's closed adapter identifier to its fixed, immutable
    /// address. There is no other way to reach any adapter address from a plan.
    function _adapterFor(SweepPlanLib.AdapterKind kind) private view returns (IAdapter) {
        if (kind == SweepPlanLib.AdapterKind.PANCAKE_V2) return PANCAKE_V2_ADAPTER;
        return UNISWAP_V3_ADAPTER;
    }

    receive() external payable {}

    modifier whenNotFrozen() {
        if (configurationFrozen) revert ConfigurationIsFrozen();
        _;
    }

    // ---------------------------------------------------------------------
    // Owner administration
    // ---------------------------------------------------------------------

    function registerOutputToken(address token) external onlyOwner whenNotFrozen {
        if (token == address(0)) revert ZeroAddress();
        allowedOutputTokens[token] = true;
        emit OutputTokenAllowed(token);
    }

    function removeOutputToken(address token) external onlyOwner whenNotFrozen {
        allowedOutputTokens[token] = false;
        emit OutputTokenDisallowed(token);
    }

    /// @notice Permanently freezes the output-token registry. Irreversible by design -
    /// there is no `unfreeze`. Recovery of stray balances remains available afterward
    /// since it is unrelated to the execution security boundary. Adapter *addresses*
    /// need no readiness check here - they were fixed, immutable constructor arguments
    /// from the moment this contract was deployed. Each adapter's own *mutable*
    /// configuration (its intermediate-asset allowlist) is a separate, owner-controlled
    /// surface on that adapter contract, though - so this still requires both fixed
    /// adapters to have already frozen themselves first, otherwise a "frozen" executor
    /// could keep routing through an adapter whose own routing surface an owner could
    /// still change. See the contract-level note above for why reading these two
    /// specific contracts' own flag is not a reintroduction of RA-01's forgeable
    /// arbitrary-registry pattern.
    function freezeConfiguration() external onlyOwner {
        if (!IFreezeCheck(address(PANCAKE_V2_ADAPTER)).configurationFrozen()) {
            revert AdapterNotYetFrozen(address(PANCAKE_V2_ADAPTER));
        }
        if (!IFreezeCheck(address(UNISWAP_V3_ADAPTER)).configurationFrozen()) {
            revert AdapterNotYetFrozen(address(UNISWAP_V3_ADAPTER));
        }
        configurationFrozen = true;
        emit ConfigurationFrozen();
    }

    /// @notice Recovers balances unrelated to any in-flight plan (e.g. tokens forcibly
    /// or accidentally sent to this contract). `nonReentrant` shares executeSweep's lock,
    /// so this can never run mid-execution (PRD §19.10).
    function recoverStrayTokens(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit StrayTokensRecovered(token, amount, to);
    }

    // ---------------------------------------------------------------------
    // Core execution
    // ---------------------------------------------------------------------

    function executeSweep(SweepPlanLib.SweepPlan calldata plan, bytes calldata permit2Signature)
        external
        nonReentrant
        returns (bytes32 executionPlanHash)
    {
        if (plan.owner != msg.sender) revert NotPlanOwner();
        if (plan.recipient == address(0)) revert ZeroRecipient();
        if (!allowedOutputTokens[plan.outputToken]) revert OutputTokenNotAllowed(plan.outputToken);
        if (block.timestamp > plan.deadline) revert PlanExpired();
        if (nonces[plan.owner] != plan.nonce) revert InvalidPlanNonce(nonces[plan.owner], plan.nonce);
        nonces[plan.owner] = plan.nonce + 1;

        SweepPlanLib.validatePlanShape(plan);

        executionPlanHash = SweepPlanLib.hashPlan(plan, block.chainid, address(this));

        address settlementToken = plan.outputToken == MON_NATIVE_SENTINEL ? address(WMON) : plan.outputToken;

        for (uint256 i = 0; i < plan.swaps.length; i++) {
            if (plan.swaps[i].tokenIn == settlementToken) revert AmbiguousSwapToken(settlementToken);
        }

        (address[] memory tokens, uint256[] memory amounts) = SweepPlanLib.aggregateTokenAmounts(plan);
        uint256[] memory baselines = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            baselines[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        uint256 settlementBaseline = IERC20(settlementToken).balanceOf(address(this));
        uint256 nativeBaseline = address(this).balance;

        _pullViaPermit2(plan, executionPlanHash, tokens, amounts, permit2Signature);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 received = IERC20(tokens[i]).balanceOf(address(this)) - baselines[i];
            if (received != amounts[i]) revert UnexpectedPulledAmount(tokens[i], amounts[i], received);
        }

        (uint256 successCount, uint256 failCount) = _executeActions(plan, executionPlanHash, settlementToken);

        uint256 outputAmount = _settleOutput(plan, settlementToken, settlementBaseline, nativeBaseline);
        _returnRemainders(plan.owner, tokens, baselines);

        emit SweepCompleted(
            executionPlanHash,
            plan.displayManifestHash,
            plan.owner,
            plan.recipient,
            plan.outputToken,
            outputAmount,
            successCount,
            failCount
        );
    }

    function _pullViaPermit2(
        SweepPlanLib.SweepPlan calldata plan,
        bytes32 executionPlanHash,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes calldata signature
    ) private {
        ISignatureTransfer.TokenPermissions[] memory permitted =
            new ISignatureTransfer.TokenPermissions[](tokens.length);
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            permitted[i] = ISignatureTransfer.TokenPermissions({token: tokens[i], amount: amounts[i]});
            details[i] = ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: amounts[i]});
        }

        ISignatureTransfer.PermitBatchTransferFrom memory permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permitted, nonce: plan.nonce, deadline: plan.deadline
        });

        bytes32 witness = TidyrWitness.hashWitness(executionPlanHash);
        PERMIT2.permitWitnessTransferFrom(
            permit, details, plan.owner, witness, TidyrWitness.WITNESS_TYPE_STRING, signature
        );
    }

    function _executeActions(SweepPlanLib.SweepPlan calldata plan, bytes32 executionPlanHash, address settlementToken)
        private
        returns (uint256 successCount, uint256 failCount)
    {
        uint256 actionIndex;

        for (uint256 i = 0; i < plan.swaps.length; i++) {
            bool ok = _executeSwap(plan.swaps[i], settlementToken, plan.deadline, executionPlanHash, actionIndex);
            if (ok) successCount++;
            else failCount++;
            actionIndex++;
        }

        for (uint256 i = 0; i < plan.transfers.length; i++) {
            SweepPlanLib.TransferAction calldata action = plan.transfers[i];
            IERC20(action.token).safeTransfer(action.to, action.amount);
            emit ActionExecuted(
                executionPlanHash,
                actionIndex,
                uint8(ActionType.TRANSFER),
                action.token,
                action.token,
                action.amount,
                action.amount,
                action.to
            );
            successCount++;
            actionIndex++;
        }

        for (uint256 i = 0; i < plan.discards.length; i++) {
            SweepPlanLib.DiscardAction calldata action = plan.discards[i];
            IERC20(action.token).safeTransfer(DEAD, action.amount);
            emit ActionExecuted(
                executionPlanHash,
                actionIndex,
                uint8(ActionType.DISCARD),
                action.token,
                action.token,
                action.amount,
                action.amount,
                DEAD
            );
            successCount++;
            actionIndex++;
        }

        for (uint256 i = 0; i < plan.burns.length; i++) {
            SweepPlanLib.BurnAction calldata action = plan.burns[i];
            IBurnable(action.token).burn(action.amount);
            emit ActionExecuted(
                executionPlanHash,
                actionIndex,
                uint8(ActionType.BURN),
                action.token,
                action.token,
                action.amount,
                action.amount,
                address(0)
            );
            successCount++;
            actionIndex++;
        }
    }

    /// @dev Correct allowFailure semantics (§19.9): the adapter's own DEX call enforces
    /// minAmountOut atomically. If it reverts, nothing happened - the input token is
    /// still with the executor, and `allowFailure` decides whether that's fatal to the
    /// whole plan. A "successful" call that nonetheless under-delivered is not a soft
    /// failure to tolerate - it means the adapter lied, which is always fatal.
    function _executeSwap(
        SweepPlanLib.SwapAction calldata action,
        address settlementToken,
        uint256 deadline,
        bytes32 executionPlanHash,
        uint256 actionIndex
    ) private returns (bool success) {
        IAdapter adapter = _adapterFor(action.adapterKind);
        address adapterAddress = address(adapter);

        IERC20(action.tokenIn).forceApprove(adapterAddress, action.amountIn);
        uint256 before = IERC20(settlementToken).balanceOf(address(this));

        try adapter.swap(
            action.tokenIn, action.amountIn, settlementToken, action.minAmountOut, deadline, action.routeData
        ) returns (
            uint256
        ) {
            uint256 actualOut = IERC20(settlementToken).balanceOf(address(this)) - before;
            IERC20(action.tokenIn).forceApprove(adapterAddress, 0);
            if (actualOut < action.minAmountOut) {
                revert AdapterInvariantViolation(adapterAddress, actualOut, action.minAmountOut);
            }
            emit ActionExecuted(
                executionPlanHash,
                actionIndex,
                uint8(ActionType.SWAP),
                action.tokenIn,
                settlementToken,
                action.amountIn,
                actualOut,
                address(this)
            );
            return true;
        } catch (bytes memory reason) {
            IERC20(action.tokenIn).forceApprove(adapterAddress, 0);
            if (!action.allowFailure) {
                assembly {
                    revert(add(reason, 32), mload(reason))
                }
            }
            emit ActionFailed(executionPlanHash, actionIndex, uint8(ActionType.SWAP), action.tokenIn, keccak256(reason));
            return false;
        }
    }

    function _settleOutput(
        SweepPlanLib.SweepPlan calldata plan,
        address settlementToken,
        uint256 settlementBaseline,
        uint256 nativeBaseline
    ) private returns (uint256 outputAmount) {
        if (plan.outputToken == MON_NATIVE_SENTINEL) {
            uint256 wmonDelta =
                IERC20(settlementToken).balanceOf(address(this)) - settlementBaseline;
            if (wmonDelta > 0) {
                WMON.withdraw(wmonDelta);
            }
            outputAmount = address(this).balance - nativeBaseline;
            if (outputAmount > 0) {
                (bool ok,) = plan.recipient.call{value: outputAmount}("");
                if (!ok) revert NativeTransferFailed();
            }
        } else {
            outputAmount = IERC20(settlementToken).balanceOf(address(this)) - settlementBaseline;
            if (outputAmount > 0) {
                IERC20(settlementToken).safeTransfer(plan.recipient, outputAmount);
            }
        }
    }

    /// @dev Returns whatever remains above each token's pre-pull baseline to the plan
    /// owner - unconsumed input (partial swap failure via allowFailure) or excess never
    /// belongs to the contract once execution completes (PRD §5.11, §19.10).
    function _returnRemainders(address owner, address[] memory tokens, uint256[] memory baselines) private {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 remainder = IERC20(tokens[i]).balanceOf(address(this)) - baselines[i];
            if (remainder > 0) {
                IERC20(tokens[i]).safeTransfer(owner, remainder);
            }
        }
    }
}
