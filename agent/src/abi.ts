/// Minimal ABI fragments the Sentinel needs. Full ABIs live in the frontend
/// (`src/abis/`) and the Foundry artifacts (`contracts/out/`).

export const policyManagerAbi = [
  {
    type: "event",
    name: "PolicyIssued",
    inputs: [
      { name: "policyId", type: "uint256", indexed: true },
      { name: "policyholder", type: "address", indexed: true },
      { name: "coveredContract", type: "address", indexed: true },
      { name: "riskTier", type: "uint8", indexed: false },
      { name: "coverageAmount", type: "uint256", indexed: false },
      { name: "premium", type: "uint256", indexed: false },
      { name: "endBlock", type: "uint64", indexed: false },
    ],
  },
] as const;

export const sentinelRegistryAbi = [
  {
    type: "function",
    name: "quoteWarningDeposit",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "submitWarning",
    stateMutability: "payable",
    inputs: [
      { name: "coveredContract", type: "address" },
      { name: "evidenceTx", type: "bytes32" },
      { name: "incidentBlock", type: "uint256" },
    ],
    outputs: [{ name: "warningId", type: "uint256" }],
  },
  {
    type: "function",
    name: "coveragePaused",
    stateMutability: "view",
    inputs: [{ type: "address" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "getScore",
    stateMutability: "view",
    inputs: [{ type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "warnings",
    stateMutability: "view",
    inputs: [{ type: "uint256" }],
    outputs: [
      { name: "sentinel", type: "address" },
      { name: "coveredContract", type: "address" },
      { name: "evidenceTx", type: "bytes32" },
      { name: "incidentBlock", type: "uint256" },
      { name: "deposit", type: "uint256" },
      { name: "platformRequestId", type: "uint256" },
      { name: "resolved", type: "bool" },
      { name: "confirmed", type: "bool" },
    ],
  },
  {
    type: "event",
    name: "WarningSubmitted",
    inputs: [
      { name: "warningId", type: "uint256", indexed: true },
      { name: "sentinel", type: "address", indexed: true },
      { name: "coveredContract", type: "address", indexed: true },
      { name: "evidenceTx", type: "bytes32", indexed: false },
    ],
  },
  {
    type: "event",
    name: "WarningResolved",
    inputs: [
      { name: "warningId", type: "uint256", indexed: true },
      { name: "classification", type: "uint8", indexed: false },
      { name: "confidence", type: "uint8", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CoveragePaused",
    inputs: [{ name: "coveredContract", type: "address", indexed: true }],
  },
] as const;
