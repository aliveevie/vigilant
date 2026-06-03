import { useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { CONTRACTS, ABIS } from "@/lib/contracts";

export function useWarningQuote() {
  return useReadContract({
    address: CONTRACTS.SentinelRegistry,
    abi: ABIS.SentinelRegistry,
    functionName: "quoteWarningDeposit",
  });
}

export function useSentinelStats() {
  const { address } = useAccount();
  return useReadContracts({
    contracts: address
      ? ([
          { address: CONTRACTS.SentinelRegistry, abi: ABIS.SentinelRegistry, functionName: "getScore", args: [address] },
          { address: CONTRACTS.SentinelRegistry, abi: ABIS.SentinelRegistry, functionName: "getHistory", args: [address] },
        ] as any)
      : [],
    query: { enabled: !!address, refetchInterval: 8000 },
  });
}

export function useSentinelWrite() {
  const { writeContractAsync, data: hash, isPending, error, reset } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash });

  const submitWarning = (
    covered: `0x${string}`,
    evidenceTx: `0x${string}`,
    incidentBlock: bigint,
    deposit: bigint,
  ) =>
    writeContractAsync({
      address: CONTRACTS.SentinelRegistry,
      abi: ABIS.SentinelRegistry,
      functionName: "submitWarning",
      args: [covered, evidenceTx, incidentBlock],
      value: deposit,
    });

  return { submitWarning, hash, isPending, error, receipt, reset };
}
