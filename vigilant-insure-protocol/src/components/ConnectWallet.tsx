import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { somniaTestnet } from "@/lib/somnia";
import { truncate } from "@/lib/format";

/// MetaMask-only connect control. Uses the single injected connector configured
/// in wagmi.ts — no WalletConnect modal, no project id.
export function ConnectWallet() {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const connector = connectors[0];
  const hasMetaMask =
    typeof window !== "undefined" && Boolean((window as any).ethereum);

  if (!isConnected) {
    if (!hasMetaMask) {
      return (
        <a
          href="https://metamask.io/download/"
          target="_blank"
          rel="noopener noreferrer"
          className="mono rounded-md border border-amber/40 bg-amber/10 px-4 py-1.5 text-xs uppercase tracking-widest text-amber transition hover:bg-amber/20"
        >
          Install MetaMask
        </a>
      );
    }
    return (
      <button
        onClick={() => connect({ connector })}
        disabled={isPending}
        className="mono rounded-md border border-teal/40 bg-teal/10 px-4 py-1.5 text-xs uppercase tracking-widest text-teal transition hover:bg-teal/20 disabled:opacity-50"
      >
        {isPending ? "Connecting…" : "Connect MetaMask"}
      </button>
    );
  }

  const wrongNetwork = chainId !== somniaTestnet.id;
  if (wrongNetwork) {
    return (
      <button
        onClick={() => switchChain({ chainId: somniaTestnet.id })}
        className="mono rounded-md border border-amber/40 bg-amber/10 px-4 py-1.5 text-xs uppercase tracking-widest text-amber transition hover:bg-amber/20"
      >
        Switch to Somnia
      </button>
    );
  }

  return (
    <button
      onClick={() => disconnect()}
      title="Disconnect"
      className="mono rounded-md border border-panel-border bg-panel px-4 py-1.5 text-xs uppercase tracking-widest text-foreground transition hover:border-teal/40 hover:text-teal"
    >
      {truncate(address!)}
    </button>
  );
}
