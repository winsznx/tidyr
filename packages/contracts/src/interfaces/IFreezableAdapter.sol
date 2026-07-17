// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Implemented by every TIDYR adapter that itself has an owner-mutable
/// configuration (e.g. an intermediate-asset allowlist). SweepExecutor's own
/// `freezeConfiguration` requires every currently-registered adapter to already report
/// `configurationFrozen() == true` before SweepExecutor can freeze itself - otherwise a
/// "frozen" SweepExecutor could still route through an adapter whose own routing
/// surface remains owner-mutable (Codex addendum audit finding CA-01/CA-02).
interface IFreezableAdapter {
    function configurationFrozen() external view returns (bool);
}
