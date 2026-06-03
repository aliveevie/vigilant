import { useAccount, useSwitchChain } from "wagmi";
import { somniaTestnet } from "@/lib/somnia";
import { AlertTriangle } from "lucide-react";

export function NetworkGuard() {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  if (!isConnected || chainId === somniaTestnet.id) return null;

  return (
    <div className="border-b border-amber/40 bg-amber/10 text-amber">
      <div className="mx-auto flex max-w-[1400px] items-center justify-between gap-4 px-4 py-2 text-sm sm:px-6">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          <span>
            Wrong network detected. Vigilant runs on{" "}
            <span className="mono font-semibold">Somnia Shannon Testnet</span> (chain {somniaTestnet.id}).
          </span>
        </div>
        <button
          onClick={() => switchChain({ chainId: somniaTestnet.id })}
          disabled={isPending}
          className="mono rounded-md border border-amber/60 bg-amber/20 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-amber transition hover:bg-amber/30 disabled:opacity-60"
        >
          {isPending ? "Switching…" : "Switch network"}
        </button>
      </div>
    </div>
  );
}
