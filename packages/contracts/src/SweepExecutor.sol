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
import {IFreezableAdapter} from "./interfaces/IFreezableAdapter.sol";

/// @title SweepExecutor
/// @notice TIDYR's core execution contract. Pulls exactly the tokens a signed plan
/// authorizes (via a Permit2 witness bound to the plan's executionPlanHash), runs
/// allowlisted adapter swaps, performs transfers/discards/burns, settles the plan's
/// output to its recipient, and returns any unconsumed input to the plan's owner.
/// @dev Immutable, non-upgradeable, no delegatecall, no arbitrary external targets.
/// Reflects PRD §19 corrections: no executor-side RevokeAction (§19.2), plan-fund
/// isolation from pre-existing balances (§19.10), and the corrected allowFailure
/// semantics where a low-output "success" is treated as an adapter invariant
/// violation, not a soft failure (§19.9).
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
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @dev Matches packages/shared/src/actions.ts::MON_NATIVE_SENTINEL exactly.
    address public constant MON_NATIVE_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Verified live on Monad mainnet (docs/research/external-addresses.md). A
    /// read-only batched-call helper that accepts arbitrary target/calldata - explicitly
    /// and permanently barred from ever being registered as an adapter, regardless of
    /// owner action, per Codex addendum audit finding CA-01.
    address public constant MULTICALL3_ADDRESS = 0xcA11bde05977b3631167028862bE2a173976CA11;

    mapping(address => uint256) public nonces;
    mapping(address => bool) public allowedAdapters;
    mapping(address => bool) public allowedOutputTokens;

    /// @dev Enumerable registry of every address ever registered via `registerAdapter`,
    /// so `freezeConfiguration` can require each currently-allowed adapter to itself be
    /// frozen (CA-01/CA-02) - `allowedAdapters` alone cannot be iterated.
    address[] private _registeredAdapterList;
    mapping(address => bool) private _everRegisteredAsAdapter;

    /// @dev Security-addendum hardening (pre-Phase-7 review): once true, the adapter
    /// and output-token registries can never change again. Mitigates a compromised- or
    /// coerced-owner registering a malicious adapter after users have started trusting
    /// this deployment. A new DEX integration after freezing requires a new
    /// SweepExecutor deployment, not a silent change to this one's security boundary.
    bool public configurationFrozen;

    event AdapterRegistered(address indexed adapter);
    event AdapterRemoved(address indexed adapter);
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
    error AdapterNotAllowed(address adapter);
    error AmbiguousSwapToken(address token);
    error UnexpectedPulledAmount(address token, uint256 expected, uint256 actual);
    error AdapterInvariantViolation(address adapter, uint256 actualOut, uint256 minRequired);
    error NativeTransferFailed();
    error ZeroAddress();
    error ConfigurationIsFrozen();
    error AdapterIsMulticall3();
    error RegisteredAdapterNotFrozen(address adapter);

    constructor(address permit2_, address wmon_, address initialOwner_) Ownable(initialOwner_) {
        if (permit2_ == address(0) || wmon_ == address(0) || initialOwner_ == address(0)) revert ZeroAddress();
        PERMIT2 = ISignatureTransfer(permit2_);
        WMON = IWMON(wmon_);
        allowedOutputTokens[MON_NATIVE_SENTINEL] = true;
        emit OutputTokenAllowed(MON_NATIVE_SENTINEL);
    }

    receive() external payable {}

    modifier whenNotFrozen() {
        if (configurationFrozen) revert ConfigurationIsFrozen();
        _;
    }

    // ---------------------------------------------------------------------
    // Owner administration
    // ---------------------------------------------------------------------

    function registerAdapter(address adapter) external onlyOwner whenNotFrozen {
        if (adapter == address(0)) revert ZeroAddress();
        if (adapter == MULTICALL3_ADDRESS) revert AdapterIsMulticall3();
        allowedAdapters[adapter] = true;
        if (!_everRegisteredAsAdapter[adapter]) {
            _everRegisteredAsAdapter[adapter] = true;
            _registeredAdapterList.push(adapter);
        }
        emit AdapterRegistered(adapter);
    }

    function removeAdapter(address adapter) external onlyOwner whenNotFrozen {
        allowedAdapters[adapter] = false;
        emit AdapterRemoved(adapter);
    }

    function registerOutputToken(address token) external onlyOwner whenNotFrozen {
        if (token == address(0)) revert ZeroAddress();
        allowedOutputTokens[token] = true;
        emit OutputTokenAllowed(token);
    }

    function removeOutputToken(address token) external onlyOwner whenNotFrozen {
        allowedOutputTokens[token] = false;
        emit OutputTokenDisallowed(token);
    }

    /// @notice Permanently freezes the adapter and output-token registries. Irreversible
    /// by design - there is no `unfreeze`. Recovery of stray balances remains available
    /// afterward since it is unrelated to the execution security boundary.
    /// @dev Requires every currently-allowed adapter to itself already report
    /// `configurationFrozen() == true` (CA-01/CA-02): a "frozen" SweepExecutor whose
    /// registered adapters can still have their own routing surface (e.g. intermediate
    /// asset allowlist) changed by their own owner would not actually establish the
    /// security boundary the freeze is meant to guarantee. Adapters that were registered
    /// and later removed (`allowedAdapters[a] == false`) are skipped - they are no
    /// longer reachable, so their own configuration state is no longer relevant.
    function freezeConfiguration() external onlyOwner {
        uint256 len = _registeredAdapterList.length;
        for (uint256 i = 0; i < len; i++) {
            address adapter = _registeredAdapterList[i];
            if (!allowedAdapters[adapter]) continue;
            if (!IFreezableAdapter(adapter).configurationFrozen()) {
                revert RegisteredAdapterNotFrozen(adapter);
            }
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
            if (!allowedAdapters[plan.swaps[i].adapter]) revert AdapterNotAllowed(plan.swaps[i].adapter);
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
        IERC20(action.tokenIn).forceApprove(action.adapter, action.amountIn);
        uint256 before = IERC20(settlementToken).balanceOf(address(this));

        try IAdapter(action.adapter)
            .swap(
                action.tokenIn, action.amountIn, settlementToken, action.minAmountOut, deadline, action.routeData
            ) returns (
            uint256
        ) {
            uint256 actualOut = IERC20(settlementToken).balanceOf(address(this)) - before;
            IERC20(action.tokenIn).forceApprove(action.adapter, 0);
            if (actualOut < action.minAmountOut) {
                revert AdapterInvariantViolation(action.adapter, actualOut, action.minAmountOut);
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
            IERC20(action.tokenIn).forceApprove(action.adapter, 0);
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
