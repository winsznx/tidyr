// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

// Forces `forge build` to compile the vendored Permit2 contract (which is otherwise
// never directly imported by any 0.8.26 TIDYR source file — see foundry.toml's
// `auto_detect_solc` comment and test/Permit2Witness.t.sol) so its artifact exists for
// `deployCode("Permit2.sol:Permit2")` in tests, and so SweepExecutor (Phase 4) can
// interact with a real Permit2 deployment through the version-agnostic
// `ISignatureTransfer` interface rather than the concrete contract.
import {Permit2} from "permit2/Permit2.sol";
