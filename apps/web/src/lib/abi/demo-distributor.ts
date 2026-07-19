/**
 * Copied verbatim from the forge build artifact
 * packages/contracts/out/DemoDistributor.sol/DemoDistributor.json — only the
 * three entries this app actually uses (one-claim-per-address bundle claim,
 * live claimed-status read, and the paused flag).
 */
export const demoDistributorAbi = [
  {
    type: "function",
    name: "claimDemoBundle",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    type: "function",
    name: "claimed",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "paused",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;
