#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../..");
const mainnetJsonPath = path.join(repoRoot, "deployments", "mainnet.json");
const outPath = path.join(here, "..", "src", "lib", "deployment.generated.ts");

const mainnet = JSON.parse(readFileSync(mainnetJsonPath, "utf8"));
const { provider: _sourceVerificationProvider, ...sourceVerificationByContract } =
  mainnet.sourceVerification;

const banner = `// GENERATED FILE — do not hand-edit.
// Regenerate with \`pnpm --filter @tidyr/web generate:deployment\` after any
// change to deployments/mainnet.json. This is the single place a Monad
// mainnet contract address enters the frontend — components must import
// from here, never inline a literal 0x address.
`;

const body = `${banner}
export const MAINNET_CHAIN_ID = ${mainnet.chainId} as const;

export const MAINNET_DEPLOYMENT = ${JSON.stringify(
  {
    chainId: mainnet.chainId,
    addresses: mainnet.addresses,
    dependencies: mainnet.dependencies,
    outputTokensAllowed: mainnet.outputTokensAllowed,
    sourceVerification: sourceVerificationByContract,
  },
  null,
  2,
)} as const;
`;

writeFileSync(outPath, body);
console.log(`Wrote ${outPath}`);
