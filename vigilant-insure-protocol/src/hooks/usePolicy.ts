import { useAccount, useReadContract, useReadContracts, useSignTypedData, useWriteContract, useWaitForTransactionReceipt, useBlockNumber } from "wagmi";
import { CONTRACTS, ABIS } from "@/lib/contracts";
import { parseEther } from "viem";

export function useRiskScoreQuote() {
  return useReadContract({
    address: CONTRACTS.PolicyManager,
    abi: ABIS.PolicyManager,
    functionName: "quoteRiskScoreDeposit",
  });
}

export function useCoveredContractTier(coveredContract?: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.PolicyManager,
    abi: ABIS.PolicyManager,
    functionName: "coveredContractTier",
    args: coveredContract ? [coveredContract] : undefined,
    query: {
      enabled: !!coveredContract,
      refetchInterval: 4000,
    },
  });
}

export function useUsedNonce() {
  const { address } = useAccount();
  return useReadContract({
    address: CONTRACTS.PolicyManager,
    abi: ABIS.PolicyManager,
    functionName: "usedNonces",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });
}

export function usePoliciesOf() {
  const { address } = useAccount();
  return useReadContract({
    address: CONTRACTS.PolicyManager,
    abi: ABIS.PolicyManager,
    functionName: "policiesOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 8000 },
  });
}

export function usePolicies(ids: readonly bigint[] | undefined) {
  return useReadContracts({
    contracts: (ids ?? []).map((id) => ({
      address: CONTRACTS.PolicyManager,
      abi: ABIS.PolicyManager,
      functionName: "policies",
      args: [id],
    })) as any,
    query: { enabled: !!ids && ids.length > 0, refetchInterval: 8000 },
  });
}

export function useClaimQuote() {
  return useReadContracts({
    contracts: [
      { address: CONTRACTS.IncidentResolver, abi: ABIS.IncidentResolver, functionName: "quoteClaimDeposit" },
      { address: CONTRACTS.IncidentResolver, abi: ABIS.IncidentResolver, functionName: "quoteEscalationDeposit" },
    ],
  });
}

export function useClaim(claimId?: bigint) {
  return useReadContract({
    address: CONTRACTS.IncidentResolver,
    abi: ABIS.IncidentResolver,
    functionName: "claims",
    args: claimId !== undefined ? [claimId] : undefined,
    query: { enabled: claimId !== undefined, refetchInterval: 5000 },
  });
}

export function useBlock() {
  return useBlockNumber({ watch: true });
}

export function usePolicyWrite() {
  const { writeContractAsync, data: hash, isPending, error, reset } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash });

  const requestRiskScore = (covered: `0x${string}`, deposit: bigint) =>
    writeContractAsync({
      address: CONTRACTS.PolicyManager,
      abi: ABIS.PolicyManager,
      functionName: "requestRiskScore",
      args: [covered],
      value: deposit,
    });

  const issue = (policy: any, signature: `0x${string}`, premium: bigint) =>
    writeContractAsync({
      address: CONTRACTS.PolicyManager,
      abi: ABIS.PolicyManager,
      functionName: "issue",
      args: [policy, signature],
      value: premium,
    });

  return { requestRiskScore, issue, hash, isPending, error, receipt, reset };
}

export function useFileClaimWrite() {
  const { writeContractAsync, data: hash, isPending, error, reset } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash });

  const fileClaim = (policyId: bigint, exploitTx: `0x${string}`, incidentBlock: bigint, deposit: bigint) =>
    writeContractAsync({
      address: CONTRACTS.IncidentResolver,
      abi: ABIS.IncidentResolver,
      functionName: "fileClaim",
      args: [policyId, exploitTx, incidentBlock],
      value: deposit,
    });

  const escalate = (claimId: bigint, deposit: bigint) =>
    writeContractAsync({
      address: CONTRACTS.IncidentResolver,
      abi: ABIS.IncidentResolver,
      functionName: "escalate",
      args: [claimId],
      value: deposit,
    });

  return { fileClaim, escalate, hash, isPending, error, receipt, reset };
}

export const POLICY_TYPES = {
  RiskPolicy: [
    { name: "policyholder", type: "address" },
    { name: "coveredContract", type: "address" },
    { name: "coverageAmount", type: "uint256" },
    { name: "riskTier", type: "uint8" },
    { name: "premium", type: "uint256" },
    { name: "startBlock", type: "uint64" },
    { name: "endBlock", type: "uint64" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

export function useSignPolicy() {
  return useSignTypedData();
}

export const POLICY_STATE = ["Pending", "Active", "Expired", "PaidOut", "Cancelled"] as const;
export const CLAIM_STATE = ["Pending", "Confirmed", "Rejected", "Escalated"] as const;

export function parseEthOrZero(s: string): bigint {
  try { return s ? parseEther(s as `${number}`) : 0n; } catch { return 0n; }
}
