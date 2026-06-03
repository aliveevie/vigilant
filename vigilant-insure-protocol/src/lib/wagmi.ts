import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { somniaTestnet } from "./somnia";

// MetaMask-only: a single injected connector targeting the MetaMask provider.
// No WalletConnect, so no project id is required.
export const wagmiConfig = createConfig({
  chains: [somniaTestnet],
  connectors: [injected({ target: "metaMask" })],
  transports: {
    [somniaTestnet.id]: http("https://api.infra.testnet.somnia.network/"),
  },
  ssr: true,
});
