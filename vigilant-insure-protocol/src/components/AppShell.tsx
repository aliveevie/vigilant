import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { ConnectWallet } from "./ConnectWallet";
import { useAccount, useBalance } from "wagmi";
import { somniaTestnet } from "@/lib/somnia";
import { VigilantLogo } from "./VigilantLogo";
import { NetworkGuard } from "./NetworkGuard";
import { fmtSTT } from "@/lib/format";
import { Activity } from "lucide-react";

const TABS = [
  { to: "/", label: "Underwrite" },
  { to: "/coverage", label: "Coverage" },
  { to: "/sentinel", label: "Sentinel" },
] as const;

function StatChip() {
  const { address, isConnected, chainId } = useAccount();
  const { data } = useBalance({
    address,
    chainId: somniaTestnet.id,
    query: { enabled: !!address, refetchInterval: 12000 },
  });
  if (!isConnected) return null;
  const onSomnia = chainId === somniaTestnet.id;
  return (
    <div className="hidden items-center gap-3 rounded-md border border-panel-border bg-panel px-3 py-1.5 text-xs md:flex">
      <div className="flex items-center gap-1.5">
        <span
          className={`h-1.5 w-1.5 rounded-full ${onSomnia ? "bg-success animate-pulse" : "bg-amber"}`}
        />
        <span className="mono uppercase tracking-wider text-muted-foreground">Somnia</span>
      </div>
      <div className="h-3 w-px bg-panel-border" />
      <div className="mono tabular font-semibold">
        {data ? fmtSTT(data.value, 4) : "0.0000"}{" "}
        <span className="text-muted-foreground">STT</span>
      </div>
    </div>
  );
}

export function AppShell() {
  const path = useRouterState({ select: (s) => s.location.pathname });
  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-40 border-b border-panel-border bg-background/85 backdrop-blur-md">
        <NetworkGuard />
        <div className="mx-auto flex h-16 max-w-[1400px] items-center justify-between gap-4 px-4 sm:px-6">
          <Link to="/" className="flex items-center gap-6">
            <VigilantLogo />
          </Link>
          <nav className="hidden items-center gap-1 rounded-lg border border-panel-border bg-panel/60 p-1 md:flex">
            {TABS.map((t) => {
              const active = path === t.to;
              return (
                <Link
                  key={t.to}
                  to={t.to}
                  className={`mono relative rounded-md px-4 py-1.5 text-xs uppercase tracking-[0.2em] transition ${
                    active
                      ? "bg-teal/15 text-teal"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  {t.label}
                  {active && (
                    <span className="absolute -bottom-px left-1/2 h-px w-8 -translate-x-1/2 bg-teal shadow-[0_0_8px_var(--teal)]" />
                  )}
                </Link>
              );
            })}
          </nav>
          <div className="flex items-center gap-3">
            <StatChip />
            <ConnectWallet />
          </div>
        </div>
        {/* Mobile tabs */}
        <nav className="mx-auto flex max-w-[1400px] gap-1 overflow-x-auto px-4 pb-2 md:hidden">
          {TABS.map((t) => {
            const active = path === t.to;
            return (
              <Link
                key={t.to}
                to={t.to}
                className={`mono rounded-md px-3 py-1.5 text-[11px] uppercase tracking-widest ${
                  active ? "bg-teal/15 text-teal" : "text-muted-foreground"
                }`}
              >
                {t.label}
              </Link>
            );
          })}
        </nav>
      </header>
      <main className="mx-auto max-w-[1400px] px-4 py-8 sm:px-6">
        <Outlet />
      </main>
      <footer className="border-t border-panel-border py-6">
        <div className="mx-auto flex max-w-[1400px] items-center justify-between gap-4 px-4 text-[11px] sm:px-6">
          <div className="mono flex items-center gap-2 text-muted-foreground">
            <Activity className="h-3 w-3 text-teal" />
            <span className="uppercase tracking-widest">Vigilant Protocol · Testnet</span>
          </div>
          <div className="mono text-muted-foreground">
            Verdicts by Somnia onchain LLM consensus
          </div>
        </div>
      </footer>
    </div>
  );
}
