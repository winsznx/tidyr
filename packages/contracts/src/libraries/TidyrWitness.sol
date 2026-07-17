// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Binds a Permit2 SignatureTransfer witness to a TIDYR `executionPlanHash`
/// (PRD §19.3), so a signature authorizing one plan can never be replayed against a
/// different plan. The witness type string is derived directly from Permit2's own
/// `PermitHash._PERMIT_BATCH_WITNESS_TRANSFER_FROM_TYPEHASH_STUB` and its own test
/// suite's documented pattern (`test/SignatureTransfer.t.sol::WITNESS_TYPE_STRING`),
/// not invented — see docs/research for the primary-source derivation.
library TidyrWitness {
    /// @dev EIP-712 type definition for the witness struct itself.
    string internal constant WITNESS_TYPE = "TidyrWitness(bytes32 executionPlanHash)";

    bytes32 internal constant WITNESS_TYPEHASH = keccak256(bytes(WITNESS_TYPE));

    /// @dev Passed as `witnessTypeString` to `ISignatureTransfer.permitWitnessTransferFrom`.
    /// Must exactly complete Permit2's `_PERMIT_BATCH_WITNESS_TRANSFER_FROM_TYPEHASH_STUB`,
    /// which already ends in "...uint256 deadline,": this string supplies the witness
    /// field declaration, then the witness type's own definition, then (per EIP-712
    /// alphabetical nested-type ordering, matching Permit2's own tests) the
    /// `TokenPermissions` type definition.
    string internal constant WITNESS_TYPE_STRING =
        "TidyrWitness witness)TidyrWitness(bytes32 executionPlanHash)TokenPermissions(address token,uint256 amount)";

    function hashWitness(bytes32 executionPlanHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(WITNESS_TYPEHASH, executionPlanHash));
    }
}
