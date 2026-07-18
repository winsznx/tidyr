// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PancakeV2Adapter} from "../src/adapters/PancakeV2Adapter.sol";
import {UniswapV3Adapter} from "../src/adapters/UniswapV3Adapter.sol";
import {SweepExecutor} from "../src/SweepExecutor.sol";
import {DemoToken} from "../src/tokens/DemoToken.sol";
import {BurnableDemoToken} from "../src/tokens/BurnableDemoToken.sol";
import {DemoDistributor} from "../src/tokens/DemoDistributor.sol";

/// @title Deploy
/// @notice Phase 8 deployment tooling (PRD §19.19 steps 12-14, 18). Deploys
/// PancakeV2Adapter, UniswapV3Adapter, SweepExecutor, five demo tokens, and
/// DemoDistributor, transfers ownership toward `PROTOCOL_OWNER_ADDRESS`, and runs the
/// eight-point adapter-identity verification gate `docs/requirements-traceability.md`
/// Section 2 mandates (Codex re-audit follow-up, Task 7.14), recording every check in
/// `deployments/mainnet.json`.
/// @dev Phase 8 is explicitly "deployment tooling + preflight (no broadcast)" per
/// `docs/implementation-plan.md`'s phase table - a stop gate requiring explicit user
/// approval before Phase 9 (the actual mainnet broadcast). This script performs zero
/// broadcasts by itself: `forge script` only sends real transactions when invoked
/// with the `--broadcast` flag, which is a decision for whoever runs this command,
/// not something this file can force. Running this script without `--broadcast`
/// (the Phase 8 mode) simulates every step against live Monad mainnet state and
/// verifies it would succeed, without moving anything.
contract Deploy is Script {
    // MULTICALL3_ADDRESS is already declared by forge-std's Base.sol (which Script
    // inherits) at the same canonical value (docs/research/external-addresses.md).

    error PreflightFailed(string reason);
    error IdentityVerificationFailed(string reason);

    struct DeployedContracts {
        address pancakeV2Adapter;
        address uniswapV3Adapter;
        address sweepExecutor;
        address dust1;
        address dust2;
        address dust3;
        address dust4;
        address dust5;
        address demoDistributor;
    }

    function run() external {
        // ---------------------------------------------------------------
        // Preflight (read-only, no broadcast under way yet)
        // ---------------------------------------------------------------
        address permit2 = vm.envAddress("PERMIT2_ADDRESS");
        address wmon = vm.envAddress("WMON_ADDRESS");
        address pancakeFactory = vm.envAddress("PANCAKE_V2_FACTORY");
        address uniswapRouter02 = vm.envAddress("UNISWAP_V3_SWAP_ROUTER02");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        // Defaults to the deployer's own address if unset - ownership then simply
        // stays with the deployer (the `protocolOwner != deployer` guard below skips
        // the transferOwnership calls entirely), so leaving this unset is safe, not
        // an accidental zero-address transfer.
        address protocolOwner = vm.envOr("PROTOCOL_OWNER_ADDRESS", deployer);

        _preflight(permit2, wmon, pancakeFactory, uniswapRouter02, protocolOwner, deployer);

        console2.log("Preflight passed. Deployer:", deployer);
        console2.log("Intended protocol owner:", protocolOwner);

        // ---------------------------------------------------------------
        // Deployment
        // ---------------------------------------------------------------
        DeployedContracts memory deployed =
            _deploy(deployerKey, deployer, permit2, wmon, pancakeFactory, uniswapRouter02, protocolOwner);

        // ---------------------------------------------------------------
        // Post-deployment adapter-identity verification gate (read-only,
        // checks 1/2/4/5/6 of the eight-point gate - check 3, masked runtime-
        // bytecode comparison, is check-3-only performed by the companion
        // scripts/verify-deployment-bytecode.mjs, which needs artifact
        // immutableReferences metadata this Solidity script cannot read)
        // ---------------------------------------------------------------
        _verifyAdapterIdentity(
            SweepExecutor(payable(deployed.sweepExecutor)), deployed, pancakeFactory, uniswapRouter02, wmon
        );

        _writeDeploymentRecord(deployed, permit2, wmon, pancakeFactory, uniswapRouter02, protocolOwner, deployer);
    }

    function _deploy(
        uint256 deployerKey,
        address deployer,
        address permit2,
        address wmon,
        address pancakeFactory,
        address uniswapRouter02,
        address protocolOwner
    ) internal returns (DeployedContracts memory deployed) {
        vm.startBroadcast(deployerKey);

        PancakeV2Adapter pancakeAdapter = new PancakeV2Adapter(pancakeFactory, wmon, deployer);
        UniswapV3Adapter uniswapAdapter = new UniswapV3Adapter(uniswapRouter02, wmon, deployer);
        SweepExecutor executor =
            new SweepExecutor(permit2, wmon, address(pancakeAdapter), address(uniswapAdapter), deployer);

        deployed = _deployDemoAssets(deployer);
        deployed.pancakeV2Adapter = address(pancakeAdapter);
        deployed.uniswapV3Adapter = address(uniswapAdapter);
        deployed.sweepExecutor = address(executor);

        // Ownable2Step: this only starts the transfer. `protocolOwner` must call
        // `acceptOwnership()` itself as a separate transaction from its own key -
        // this script cannot and does not do that on the new owner's behalf.
        if (protocolOwner != deployer) {
            pancakeAdapter.transferOwnership(protocolOwner);
            uniswapAdapter.transferOwnership(protocolOwner);
            executor.transferOwnership(protocolOwner);
            Ownable2Step(deployed.demoDistributor).transferOwnership(protocolOwner);
        }

        vm.stopBroadcast();
    }

    function _deployDemoAssets(address deployer) internal returns (DeployedContracts memory deployed) {
        DemoToken dust1 = new DemoToken("TIDYR Dust 1", "DUST1");
        DemoToken dust2 = new DemoToken("TIDYR Dust 2", "DUST2");
        DemoToken dust3 = new DemoToken("TIDYR Dust 3", "DUST3");
        BurnableDemoToken dust4 = new BurnableDemoToken("TIDYR Dust 4", "DUST4");
        DemoToken dust5 = new DemoToken("TIDYR Dust 5", "DUST5");

        IERC20[5] memory distributorTokens = [
            IERC20(address(dust1)),
            IERC20(address(dust2)),
            IERC20(address(dust3)),
            IERC20(address(dust4)),
            IERC20(address(dust5))
        ];
        DemoDistributor distributor = new DemoDistributor(distributorTokens, deployer);

        // Demo inventory: sized for judge claims (200 ether per token per claim,
        // PRD §19.15) - a fixed, generous, non-production-value seed amount.
        uint256 distributorInventory = 400_000 ether;
        dust1.transfer(address(distributor), distributorInventory);
        dust2.transfer(address(distributor), distributorInventory);
        dust3.transfer(address(distributor), distributorInventory);
        dust4.transfer(address(distributor), distributorInventory);
        dust5.transfer(address(distributor), distributorInventory);

        deployed.dust1 = address(dust1);
        deployed.dust2 = address(dust2);
        deployed.dust3 = address(dust3);
        deployed.dust4 = address(dust4);
        deployed.dust5 = address(dust5);
        deployed.demoDistributor = address(distributor);
    }

    function _preflight(
        address permit2,
        address wmon,
        address pancakeFactory,
        address uniswapRouter02,
        address protocolOwner,
        address deployer
    ) internal view {
        if (block.chainid != 143) {
            revert PreflightFailed("chain ID is not Monad mainnet (143)");
        }
        if (permit2.code.length == 0) revert PreflightFailed("Permit2 has no code at the configured address");
        if (wmon.code.length == 0) revert PreflightFailed("WMON has no code at the configured address");
        if (pancakeFactory.code.length == 0) revert PreflightFailed("PancakeV2 factory has no code");
        if (uniswapRouter02.code.length == 0) revert PreflightFailed("Uniswap SwapRouter02 has no code");
        if (protocolOwner == address(0)) revert PreflightFailed("PROTOCOL_OWNER_ADDRESS is unset/zero");
        if (deployer.balance == 0) revert PreflightFailed("deployer account has zero native MON balance");
        if (permit2 == MULTICALL3_ADDRESS || wmon == MULTICALL3_ADDRESS) {
            revert PreflightFailed("a core dependency env var resolves to Multicall3's address - misconfiguration");
        }
    }

    /// @dev Checks 1, 2, 4, 5, 6 of the eight-point gate in
    /// `docs/requirements-traceability.md` Section 2. Check 3 (masked runtime-
    /// bytecode comparison) and checks 7/8 (recording all results, aborting on any
    /// mismatch) span both this function and `scripts/verify-deployment-bytecode.mjs`
    /// plus `_writeDeploymentRecord` below - together they implement the full gate.
    function _verifyAdapterIdentity(
        SweepExecutor executor,
        DeployedContracts memory deployed,
        address expectedPancakeFactory,
        address expectedUniswapRouter02,
        address expectedWmon
    ) internal view {
        // (1) Read back the executor's own immutable slots and assert they equal
        // the addresses just deployed in this exact script run.
        if (address(executor.PANCAKE_V2_ADAPTER()) != deployed.pancakeV2Adapter) {
            revert IdentityVerificationFailed("SweepExecutor.PANCAKE_V2_ADAPTER() does not match this run's deployment");
        }
        if (address(executor.UNISWAP_V3_ADAPTER()) != deployed.uniswapV3Adapter) {
            revert IdentityVerificationFailed("SweepExecutor.UNISWAP_V3_ADAPTER() does not match this run's deployment");
        }

        // (2) Independently assert nonzero code at both adapter addresses (not
        // merely trusting that SweepExecutor's own constructor didn't revert).
        if (deployed.pancakeV2Adapter.code.length == 0) {
            revert IdentityVerificationFailed("PancakeV2Adapter has no code post-deployment");
        }
        if (deployed.uniswapV3Adapter.code.length == 0) {
            revert IdentityVerificationFailed("UniswapV3Adapter has no code post-deployment");
        }

        // (4) Independently reconstruct and verify each adapter's own constructor
        // arguments by reading back their immutable dependencies (this doubles as
        // check 5's dependency read-back, verified against the caller-supplied
        // expected addresses, not merely against whatever the adapter reports).
        PancakeV2Adapter pancake = PancakeV2Adapter(deployed.pancakeV2Adapter);
        if (address(pancake.FACTORY()) != expectedPancakeFactory) {
            revert IdentityVerificationFailed("PancakeV2Adapter.FACTORY does not match the intended factory address");
        }
        if (pancake.WMON() != expectedWmon) {
            revert IdentityVerificationFailed("PancakeV2Adapter.WMON does not match the intended WMON address");
        }

        UniswapV3Adapter uniswap = UniswapV3Adapter(deployed.uniswapV3Adapter);
        if (address(uniswap.ROUTER()) != expectedUniswapRouter02) {
            revert IdentityVerificationFailed("UniswapV3Adapter.ROUTER does not match the intended SwapRouter02 address");
        }
        if (uniswap.WMON() != expectedWmon) {
            revert IdentityVerificationFailed("UniswapV3Adapter.WMON does not match the intended WMON address");
        }

        // (6) Reject a proxy pattern at either adapter address: an EIP-1167 minimal
        // proxy has a fixed, recognizable 45-byte runtime prefix/suffix; an
        // EIP-1967 proxy stores its implementation at a fixed, well-known storage
        // slot. Both adapters are plain, non-proxied contracts - detecting either
        // pattern here means the deployment produced something other than what was
        // compiled and must abort.
        _rejectProxyPattern(deployed.pancakeV2Adapter, "PancakeV2Adapter");
        _rejectProxyPattern(deployed.uniswapV3Adapter, "UniswapV3Adapter");

        console2.log("Adapter identity verification (checks 1/2/4/5/6): PASSED");
    }

    /// @dev EIP-1167 minimal proxies always begin with `0x363d3d373d3d3d363d73`
    /// (10 bytes) followed by the 20-byte implementation address, then
    /// `0x5af43d82803e903d91602b57fd5bf3`. EIP-1967 proxies store their
    /// implementation at the fixed slot
    /// `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc` - a
    /// plain, non-proxy contract's storage at that slot is always zero.
    function _rejectProxyPattern(address target, string memory label) internal view {
        bytes memory code = target.code;
        if (code.length >= 10) {
            bytes10 prefix;
            assembly {
                prefix := mload(add(code, 0x20))
            }
            if (prefix == bytes10(0x363d3d373d3d3d363d73)) {
                revert IdentityVerificationFailed(string.concat(
                        label, " runtime code matches the EIP-1167 minimal-proxy pattern"
                    ));
            }
        }
        bytes32 eip1967Slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        if (uint256(vm.load(target, eip1967Slot)) != 0) {
            revert IdentityVerificationFailed(string.concat(label, " has a nonzero EIP-1967 implementation slot"));
        }
    }

    function _writeDeploymentRecord(
        DeployedContracts memory deployed,
        address permit2,
        address wmon,
        address pancakeFactory,
        address uniswapRouter02,
        address protocolOwner,
        address deployer
    ) internal {
        string memory root = "deployment";
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "timestamp", block.timestamp);
        vm.serializeAddress(root, "deployer", deployer);
        vm.serializeAddress(root, "protocolOwnerPending", protocolOwner);

        string memory addresses = "addresses";
        vm.serializeAddress(addresses, "pancakeV2Adapter", deployed.pancakeV2Adapter);
        vm.serializeAddress(addresses, "uniswapV3Adapter", deployed.uniswapV3Adapter);
        vm.serializeAddress(addresses, "sweepExecutor", deployed.sweepExecutor);
        vm.serializeAddress(addresses, "dust1", deployed.dust1);
        vm.serializeAddress(addresses, "dust2", deployed.dust2);
        vm.serializeAddress(addresses, "dust3", deployed.dust3);
        vm.serializeAddress(addresses, "dust4", deployed.dust4);
        vm.serializeAddress(addresses, "dust5", deployed.dust5);
        string memory addressesJson = vm.serializeAddress(addresses, "demoDistributor", deployed.demoDistributor);

        string memory dependencies = "dependencies";
        vm.serializeAddress(dependencies, "permit2", permit2);
        vm.serializeAddress(dependencies, "wmon", wmon);
        vm.serializeAddress(dependencies, "pancakeV2Factory", pancakeFactory);
        string memory dependenciesJson = vm.serializeAddress(dependencies, "uniswapV3SwapRouter02", uniswapRouter02);

        string memory gate = "identityGate";
        vm.serializeBool(gate, "check1_executorSlotsMatchThisRun", true);
        vm.serializeBool(gate, "check2_nonzeroCode", true);
        vm.serializeString(
            gate,
            "check3_maskedRuntimeBytecodeComparison",
            "performed separately by scripts/verify-deployment-bytecode.mjs - see its own output"
        );
        vm.serializeBool(gate, "check4_constructorArgumentsVerified", true);
        vm.serializeBool(gate, "check5_dependencyAddressesVerified", true);
        vm.serializeBool(gate, "check6_noProxyPatternDetected", true);
        vm.serializeBool(gate, "check7_recordedInThisFile", true);
        string memory gateJson = vm.serializeBool(gate, "check8_abortsOnMismatch", true);

        vm.serializeString(root, "addresses", addressesJson);
        vm.serializeString(root, "dependencies", dependenciesJson);
        string memory finalJson = vm.serializeString(root, "identityGate", gateJson);

        vm.writeJson(finalJson, "../../deployments/mainnet.json");
        console2.log("Wrote deployments/mainnet.json");
    }
}
