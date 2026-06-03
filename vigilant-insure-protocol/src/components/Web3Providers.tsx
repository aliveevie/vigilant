import { useEffect, useState, type ReactNode } from "react";
import { WagmiProvider } from "wagmi";
import { wagmiConfig } from "@/lib/wagmi";

export function Web3Providers({ children }: { children: ReactNode }) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  return (
    <WagmiProvider config={wagmiConfig}>
      {/* Defer wallet-dependent UI until mount to avoid SSR hydration mismatch */}
      <div style={{ visibility: mounted ? "visible" : "hidden" }}>{children}</div>
    </WagmiProvider>
  );
}
