import { defineChain } from "viem";

export const somniaTestnet = defineChain({
  id: 50312,
  name: "Somnia Shannon Testnet",
  nativeCurrency: { name: "Somnia Test Token", symbol: "STT", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://api.infra.testnet.somnia.network/"] },
  },
  blockExplorers: {
    default: {
      name: "Shannon Explorer",
      url: "https://shannon-explorer.somnia.network",
    },
  },
  testnet: true,
});

export const explorerTx = (hash: string) =>
  `${somniaTestnet.blockExplorers.default.url}/tx/${hash}`;
export const explorerAddr = (addr: string) =>
  `${somniaTestnet.blockExplorers.default.url}/address/${addr}`;
