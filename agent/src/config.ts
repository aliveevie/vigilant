import { defineChain } from "viem";

/// Somnia Shannon testnet.
export const somniaTestnet = defineChain({
  id: 50312,
  name: "Somnia Shannon Testnet",
  nativeCurrency: { name: "Somnia Test Token", symbol: "STT", decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.RPC_URL ?? "https://api.infra.testnet.somnia.network/"] },
  },
  blockExplorers: {
    default: { name: "Shannon Explorer", url: "https://shannon-explorer.somnia.network" },
  },
  testnet: true,
});

/// Live, verified Vigilant deployment (chain 50312, deployed 2026-05-28).
export const CONTRACTS = {
  Governor: "0xF7B1ce04f92b39162Dfa528D3a29604d477ce6ec",
  CoverageVault: "0x6b0462e6af572Ed59c9B2e7dAd2a2C031C2b49FB",
  PolicyManager: "0x7819f4929D80b5F98448b16c775F7c7dA1eC7221",
  IncidentResolver: "0x790564795C471AD5FC20b1dac9fc837029eF9876",
  SentinelRegistry: "0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357",
  PremiumDistributor: "0xAb5597214489bf4F3BB69419AFdF3fB21649A492",
} as const;

/// The LLM Inference base agent the protocol invokes for verdicts.
export const LLM_INFERENCE_AGENT_ID = 12847293847561029384n;

export const explorerTx = (hash: string) =>
  `${somniaTestnet.blockExplorers.default.url}/tx/${hash}`;
export const explorerAddr = (addr: string) =>
  `${somniaTestnet.blockExplorers.default.url}/address/${addr}`;

export const settings = {
  pollIntervalMs: Number(process.env.POLL_INTERVAL_MS ?? 12000),
  dropThreshold: Number(process.env.DROP_THRESHOLD ?? 0.3),
  extraWatchlist: (process.env.EXTRA_WATCHLIST ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean) as `0x${string}`[],
  // Somnia charges extra gas per calldata byte; warnings carry a ~600B prompt.
  gasLimit: 5_000_000n,
};
