import CoverageVaultAbi from "@/abis/CoverageVault.json";
import PolicyManagerAbi from "@/abis/PolicyManager.json";
import IncidentResolverAbi from "@/abis/IncidentResolver.json";
import SentinelRegistryAbi from "@/abis/SentinelRegistry.json";
import PremiumDistributorAbi from "@/abis/PremiumDistributor.json";
import GovernorAbi from "@/abis/Governor.json";
import VaultShareAbi from "@/abis/VaultShare.json";

export const CONTRACTS = {
  Governor: "0xF7B1ce04f92b39162Dfa528D3a29604d477ce6ec",
  CoverageVault: "0x6b0462e6af572Ed59c9B2e7dAd2a2C031C2b49FB",
  PolicyManager: "0x7819f4929D80b5F98448b16c775F7c7dA1eC7221",
  IncidentResolver: "0x790564795C471AD5FC20b1dac9fc837029eF9876",
  SentinelRegistry: "0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357",
  PremiumDistributor: "0xAb5597214489bf4F3BB69419AFdF3fB21649A492",
  VaultShareA: "0x9d2B2ff18f99D3bA2A06a904a572a42BE1c54BEe",
  VaultShareB: "0xbD218c55326967a54c58e823AED1d59a4E47A101",
  VaultShareC: "0x269794Bb84e22BDDd8B8cbef004996166D699598",
} as const;

export const ABIS = {
  CoverageVault: CoverageVaultAbi as any,
  PolicyManager: PolicyManagerAbi as any,
  IncidentResolver: IncidentResolverAbi as any,
  SentinelRegistry: SentinelRegistryAbi as any,
  PremiumDistributor: PremiumDistributorAbi as any,
  Governor: GovernorAbi as any,
  VaultShare: VaultShareAbi as any,
} as const;

export const TIERS = [
  { id: 0, name: "A", label: "Tranche A", subtitle: "Low risk · Low yield", accent: "teal" },
  { id: 1, name: "B", label: "Tranche B", subtitle: "Balanced", accent: "amber" },
  { id: 2, name: "C", label: "Tranche C", subtitle: "High risk · High yield", accent: "rose" },
] as const;

export const SHARE_TOKEN_BY_TIER: Record<number, `0x${string}`> = {
  0: CONTRACTS.VaultShareA,
  1: CONTRACTS.VaultShareB,
  2: CONTRACTS.VaultShareC,
};

export function useVigilantConfig() {
  return { CONTRACTS, ABIS, TIERS };
}
