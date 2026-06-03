import { useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { CONTRACTS, ABIS, SHARE_TOKEN_BY_TIER } from "@/lib/contracts";
import { erc20Abi, parseEther } from "viem";

export function useTrancheTotals(tier: number) {
  return useReadContract({
    address: CONTRACTS.CoverageVault,
    abi: ABIS.CoverageVault,
    functionName: "trancheTotals",
    args: [tier],
    query: { refetchInterval: 8000 },
  });
}

export function useVaultGlobals() {
  return useReadContracts({
    contracts: [
      { address: CONTRACTS.CoverageVault, abi: ABIS.CoverageVault, functionName: "totalCapital" },
      { address: CONTRACTS.CoverageVault, abi: ABIS.CoverageVault, functionName: "totalLocked" },
      { address: CONTRACTS.CoverageVault, abi: ABIS.CoverageVault, functionName: "reserve" },
    ],
    query: { refetchInterval: 8000 },
  });
}

export function useUserShareBalance(tier: number) {
  const { address } = useAccount();
  return useReadContract({
    address: SHARE_TOKEN_BY_TIER[tier],
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 8000 },
  });
}

export function usePreviewRedeem(tier: number, shares: bigint | undefined) {
  return useReadContract({
    address: CONTRACTS.CoverageVault,
    abi: ABIS.CoverageVault,
    functionName: "previewRedeem",
    args: shares !== undefined && shares > 0n ? [tier, shares] : undefined,
    query: { enabled: shares !== undefined && shares > 0n },
  });
}

export function usePreviewDeposit(tier: number, assetsEth: string) {
  let wei: bigint | undefined;
  try {
    wei = assetsEth ? parseEther(assetsEth as `${number}`) : undefined;
  } catch {
    wei = undefined;
  }
  return useReadContract({
    address: CONTRACTS.CoverageVault,
    abi: ABIS.CoverageVault,
    functionName: "previewDeposit",
    args: wei !== undefined && wei > 0n ? [tier, wei] : undefined,
    query: { enabled: wei !== undefined && wei > 0n },
  });
}

export function useVaultWrite() {
  const { writeContractAsync, data: hash, isPending, error, reset } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash });

  const deposit = (tier: number, amountEth: string) =>
    writeContractAsync({
      address: CONTRACTS.CoverageVault,
      abi: ABIS.CoverageVault,
      functionName: "deposit",
      args: [tier],
      value: parseEther(amountEth as `${number}`),
    });

  const withdraw = (tier: number, shares: bigint) =>
    writeContractAsync({
      address: CONTRACTS.CoverageVault,
      abi: ABIS.CoverageVault,
      functionName: "withdraw",
      args: [tier, shares],
    });

  return { deposit, withdraw, hash, isPending, error, receipt, reset };
}
