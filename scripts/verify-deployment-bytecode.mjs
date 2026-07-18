#!/usr/bin/env node
// Phase 8 deployment tooling (Task 7.14 gate, check 3): compares each deployed
// adapter's live runtime bytecode against the compiled artifact's expected runtime
// bytecode, masking the immutable-argument byte ranges Solidity bakes into
// constructor-supplied values (factory/router/wmon/owner) so the comparison doesn't
// spuriously mismatch on legitimate per-deployment constructor arguments.
//
// Read-only: performs eth_getCode JSON-RPC calls only, never sends a transaction.
//
// Usage:
//   node scripts/verify-deployment-bytecode.mjs [path/to/deployments/mainnet.json]
//
// Requires: deployments/mainnet.json (written by packages/contracts/script/Deploy.s.sol)
// and the compiled artifacts in packages/contracts/out/ (run `forge build` first).

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const RPC_URL = process.env.MONAD_RPC_URL || "https://rpc.monad.xyz";

const ADAPTERS = [
  {
    label: "pancakeV2Adapter",
    artifactPath: "packages/contracts/out/PancakeV2Adapter.sol/PancakeV2Adapter.json",
  },
  {
    label: "uniswapV3Adapter",
    artifactPath: "packages/contracts/out/UniswapV3Adapter.sol/UniswapV3Adapter.json",
  },
];

function readJson(relativePath) {
  return JSON.parse(readFileSync(resolve(ROOT, relativePath), "utf8"));
}

async function ethGetCode(address) {
  const response = await fetch(RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "eth_getCode",
      params: [address, "latest"],
    }),
  });
  const { result, error } = await response.json();
  if (error) throw new Error(`eth_getCode failed for ${address}: ${JSON.stringify(error)}`);
  return result;
}

/// Builds a boolean mask (true = masked/ignored) over the runtime bytecode's byte
/// offsets, from the artifact's `deployedBytecode.immutableReferences` map (AST node
/// id -> array of {start, length} byte ranges).
function buildImmutableMask(immutableReferences, byteLength) {
  const mask = new Array(byteLength).fill(false);
  for (const ranges of Object.values(immutableReferences ?? {})) {
    for (const { start, length } of ranges) {
      for (let i = start; i < start + length && i < byteLength; i++) {
        mask[i] = true;
      }
    }
  }
  return mask;
}

function hexToBytes(hex) {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function compareMasked(expectedHex, actualHex, mask) {
  const expected = hexToBytes(expectedHex);
  const actual = hexToBytes(actualHex);
  if (expected.length !== actual.length) {
    return {
      match: false,
      reason: `length mismatch: expected ${expected.length} bytes, got ${actual.length} bytes`,
    };
  }
  const mismatches = [];
  for (let i = 0; i < expected.length; i++) {
    if (mask[i]) continue; // immutable-argument byte, intentionally ignored
    if (expected[i] !== actual[i]) mismatches.push(i);
  }
  if (mismatches.length > 0) {
    return {
      match: false,
      reason: `${mismatches.length} non-immutable byte(s) differ, first at offset ${mismatches[0]}`,
    };
  }
  return { match: true, reason: "runtime bytecode matches (immutable-argument bytes masked)" };
}

async function main() {
  const deploymentsPath = process.argv[2] || "deployments/mainnet.json";
  const deployments = readJson(deploymentsPath);

  const results = {};
  let allPassed = true;

  for (const adapter of ADAPTERS) {
    const address = deployments.addresses?.[adapter.label];
    if (!address) {
      throw new Error(`deployments/mainnet.json has no address recorded for ${adapter.label}`);
    }

    const artifact = readJson(adapter.artifactPath);
    const expectedHex = artifact.deployedBytecode.object;
    const immutableReferences = artifact.deployedBytecode.immutableReferences;

    const actualHex = await ethGetCode(address);
    if (actualHex === "0x") {
      results[adapter.label] = {
        address,
        match: false,
        reason: "no code at address (eth_getCode returned 0x)",
      };
      allPassed = false;
      continue;
    }

    const byteLength = (expectedHex.length - 2) / 2;
    const mask = buildImmutableMask(immutableReferences, byteLength);
    const comparison = compareMasked(expectedHex, actualHex, mask);

    results[adapter.label] = { address, ...comparison };
    if (!comparison.match) allPassed = false;

    console.log(
      `[${adapter.label}] ${address}: ${comparison.match ? "PASS" : "FAIL"} - ${comparison.reason}`,
    );
  }

  deployments.identityGate = deployments.identityGate ?? {};
  deployments.identityGate.check3_maskedRuntimeBytecodeComparison = results;
  writeFileSync(resolve(ROOT, deploymentsPath), JSON.stringify(deployments, null, 2) + "\n");
  console.log(`Wrote check3 results into ${deploymentsPath}`);

  if (!allPassed) {
    console.error(
      "FAIL: at least one adapter's runtime bytecode does not match the compiled artifact.",
    );
    process.exit(1);
  }
  console.log(
    "PASS: both adapters' runtime bytecode matches the compiled artifact (immutable bytes masked).",
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
