export const sweepExecutorAbi = [
  {
    type: "function",
    name: "allowedOutputTokens",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "nonces",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "owner",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "configurationFrozen",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
  /**
   * Copied verbatim (component order/types) from the forge build artifact
   * packages/contracts/out/SweepExecutor.sol/SweepExecutor.json — do not
   * hand-edit the tuple shape. Only used client-side for the F11 calldata
   * encode/decode round-trip compare (see lib/review/round-trip-compare.ts);
   * this app never broadcasts a call to this function.
   */
  {
    type: "function",
    name: "executeSweep",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "plan",
        type: "tuple",
        internalType: "struct SweepPlanLib.SweepPlan",
        components: [
          { name: "owner", type: "address", internalType: "address" },
          { name: "recipient", type: "address", internalType: "address" },
          { name: "outputToken", type: "address", internalType: "address" },
          { name: "deadline", type: "uint256", internalType: "uint256" },
          { name: "nonce", type: "uint256", internalType: "uint256" },
          { name: "displayManifestHash", type: "bytes32", internalType: "bytes32" },
          {
            name: "swaps",
            type: "tuple[]",
            internalType: "struct SweepPlanLib.SwapAction[]",
            components: [
              { name: "tokenIn", type: "address", internalType: "address" },
              { name: "amountIn", type: "uint256", internalType: "uint256" },
              { name: "adapterKind", type: "uint8", internalType: "enum SweepPlanLib.AdapterKind" },
              { name: "minAmountOut", type: "uint256", internalType: "uint256" },
              { name: "routeData", type: "bytes", internalType: "bytes" },
              { name: "allowFailure", type: "bool", internalType: "bool" },
            ],
          },
          {
            name: "transfers",
            type: "tuple[]",
            internalType: "struct SweepPlanLib.TransferAction[]",
            components: [
              { name: "token", type: "address", internalType: "address" },
              { name: "amount", type: "uint256", internalType: "uint256" },
              { name: "to", type: "address", internalType: "address" },
            ],
          },
          {
            name: "discards",
            type: "tuple[]",
            internalType: "struct SweepPlanLib.DiscardAction[]",
            components: [
              { name: "token", type: "address", internalType: "address" },
              { name: "amount", type: "uint256", internalType: "uint256" },
            ],
          },
          {
            name: "burns",
            type: "tuple[]",
            internalType: "struct SweepPlanLib.BurnAction[]",
            components: [
              { name: "token", type: "address", internalType: "address" },
              { name: "amount", type: "uint256", internalType: "uint256" },
            ],
          },
        ],
      },
      { name: "permit2Signature", type: "bytes", internalType: "bytes" },
    ],
    outputs: [{ name: "executionPlanHash", type: "bytes32", internalType: "bytes32" }],
  },
] as const;
