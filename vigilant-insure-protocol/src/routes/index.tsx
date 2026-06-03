import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useAccount } from "wagmi";
import { formatEther } from "viem";
import {
  useTrancheTotals,
  useVaultGlobals,
  useUserShareBalance,
  usePreviewDeposit,
  usePreviewRedeem,
  useVaultWrite,
} from "@/hooks/useVault";
import { TIERS, SHARE_TOKEN_BY_TIER } from "@/lib/contracts";
import { fmtSTT, fmtBps } from "@/lib/format";
import { Address } from "@/components/Mono";
import { txToast, errToast } from "@/lib/toast";
import { ArrowDownToLine, ArrowUpFromLine, Layers, Lock, Coins } from "lucide-react";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [{ title: "Underwrite · Vigilant" }],
  }),
  component: UnderwriterDashboard,
});

function UnderwriterDashboard() {
  const globals = useVaultGlobals();
  const totalCapital = globals.data?.[0]?.result as bigint | undefined;
  const totalLocked = globals.data?.[1]?.result as bigint | undefined;
  const reserve = globals.data?.[2]?.result as bigint | undefined;

  const utilization =
    totalCapital && totalLocked && totalCapital > 0n
      ? Number((totalLocked * 10000n) / totalCapital) / 100
      : 0;

  return (
    <div className="space-y-8">
      <section>
        <div className="mono mb-1 text-[11px] uppercase tracking-[0.3em] text-muted-foreground">
          Capital Layer
        </div>
        <h1 className="text-2xl font-semibold sm:text-3xl">Underwriter Dashboard</h1>
        <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
          Deposit STT into one of three risk-tranched vaults to underwrite exploit coverage and
          earn premiums proportional to your tranche's risk multiplier.
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-3">
        <KpiCard
          icon={<Coins className="h-4 w-4 text-teal" />}
          label="Total Capital"
          value={`${fmtSTT(totalCapital)} STT`}
        />
        <KpiCard
          icon={<Lock className="h-4 w-4 text-amber" />}
          label="Locked"
          value={`${fmtSTT(totalLocked)} STT`}
          sub={`${utilization.toFixed(2)}% utilization`}
        />
        <KpiCard
          icon={<Layers className="h-4 w-4 text-teal" />}
          label="Protocol Reserve"
          value={`${fmtSTT(reserve)} STT`}
        />
      </section>

      <section className="grid gap-4 xl:grid-cols-3">
        {TIERS.map((t) => (
          <TrancheCard key={t.id} tier={t.id} />
        ))}
      </section>
    </div>
  );
}

function KpiCard({
  icon,
  label,
  value,
  sub,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="panel p-5">
      <div className="flex items-center justify-between">
        <span className="mono text-[10px] uppercase tracking-[0.25em] text-muted-foreground">
          {label}
        </span>
        {icon}
      </div>
      <div className="mono mt-3 text-2xl font-semibold tabular">{value}</div>
      {sub && <div className="mono mt-1 text-xs text-muted-foreground">{sub}</div>}
    </div>
  );
}

function TrancheCard({ tier }: { tier: number }) {
  const meta = TIERS[tier];
  const totals = useTrancheTotals(tier);
  const shareBal = useUserShareBalance(tier);
  const { isConnected } = useAccount();

  const data = totals.data as readonly [bigint, bigint, bigint, number] | undefined;
  const [totalAssets, lockedAssets, totalShares, multiplierBps] = data ?? [0n, 0n, 0n, 0];

  const available = totalAssets > lockedAssets ? totalAssets - lockedAssets : 0n;
  const utilization =
    totalAssets > 0n ? Number((lockedAssets * 10000n) / totalAssets) / 100 : 0;
  const sharePrice =
    totalShares > 0n ? Number((totalAssets * 10n ** 18n) / totalShares) / 1e18 : 1;

  const userShares = (shareBal.data as bigint | undefined) ?? 0n;
  const userRedeem = usePreviewRedeem(tier, userShares > 0n ? userShares : undefined);

  const accentClass =
    meta.accent === "teal"
      ? "border-teal/30 bg-teal/5"
      : meta.accent === "amber"
        ? "border-amber/30 bg-amber/5"
        : "border-rose/30 bg-rose/5";

  const accentText =
    meta.accent === "teal" ? "text-teal" : meta.accent === "amber" ? "text-amber" : "text-rose";

  return (
    <div className={`panel relative overflow-hidden ${accentClass}`}>
      <div className="border-b border-panel-border p-5">
        <div className="flex items-baseline justify-between">
          <div>
            <div className={`mono text-[10px] uppercase tracking-[0.3em] ${accentText}`}>
              Tier {meta.name}
            </div>
            <div className="mt-1 text-lg font-semibold">{meta.label}</div>
            <div className="text-xs text-muted-foreground">{meta.subtitle}</div>
          </div>
          <div className="text-right">
            <div className="mono text-[10px] uppercase tracking-widest text-muted-foreground">
              Multiplier
            </div>
            <div className={`mono text-xl font-semibold tabular ${accentText}`}>
              {fmtBps(multiplierBps)}
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-px bg-panel-border">
        <Stat label="Total Assets" value={`${fmtSTT(totalAssets)} STT`} />
        <Stat label="Locked" value={`${fmtSTT(lockedAssets)} STT`} />
        <Stat label="Available" value={`${fmtSTT(available)} STT`} />
        <Stat label="Utilization" value={`${utilization.toFixed(2)}%`} />
        <Stat label="Share Price" value={`${sharePrice.toFixed(6)} STT`} />
        <Stat
          label="Share Token"
          value={<Address value={SHARE_TOKEN_BY_TIER[tier]} className="text-xs" />}
          raw
        />
      </div>

      {isConnected && (
        <div className="border-t border-panel-border bg-background/40 p-5">
          <div className="mono mb-2 text-[10px] uppercase tracking-[0.25em] text-muted-foreground">
            Your Position
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <div className="mono text-[10px] text-muted-foreground">vVIG-{meta.name} shares</div>
              <div className="mono text-sm font-semibold tabular">{fmtSTT(userShares, 6)}</div>
            </div>
            <div>
              <div className="mono text-[10px] text-muted-foreground">Redeemable</div>
              <div className="mono text-sm font-semibold tabular">
                {fmtSTT(userRedeem.data as bigint | undefined)} STT
              </div>
            </div>
          </div>
        </div>
      )}

      <DepositWithdrawForm tier={tier} userShares={userShares} />
    </div>
  );
}

function Stat({
  label,
  value,
  raw,
}: {
  label: string;
  value: React.ReactNode;
  raw?: boolean;
}) {
  return (
    <div className="bg-panel p-3">
      <div className="mono text-[10px] uppercase tracking-widest text-muted-foreground">
        {label}
      </div>
      <div className={`mt-1 text-sm font-semibold ${raw ? "" : "mono tabular"}`}>{value}</div>
    </div>
  );
}

function DepositWithdrawForm({ tier, userShares }: { tier: number; userShares: bigint }) {
  const [mode, setMode] = useState<"deposit" | "withdraw">("deposit");
  const [amount, setAmount] = useState("");
  const { isConnected } = useAccount();
  const { deposit, withdraw, isPending } = useVaultWrite();

  const previewShares = usePreviewDeposit(tier, mode === "deposit" ? amount : "");
  const withdrawShares = parseSharesSafe(amount);
  const previewAssets = usePreviewRedeem(
    tier,
    mode === "withdraw" && withdrawShares > 0n ? withdrawShares : undefined,
  );

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      if (mode === "deposit") {
        txToast(`Depositing ${amount} STT into Tier ${TIERS[tier].name}`);
        const hash = await deposit(tier, amount);
        txToast(`Deposit confirmed`, hash);
      } else {
        txToast(`Withdrawing from Tier ${TIERS[tier].name}`);
        const hash = await withdraw(tier, withdrawShares);
        txToast(`Withdraw confirmed`, hash);
      }
      setAmount("");
    } catch (err) {
      errToast("Transaction failed", err);
    }
  };

  return (
    <form onSubmit={onSubmit} className="border-t border-panel-border p-5">
      <div className="mb-3 flex gap-1 rounded-md border border-panel-border bg-panel p-1">
        {(["deposit", "withdraw"] as const).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => {
              setMode(m);
              setAmount("");
            }}
            className={`mono flex-1 rounded px-3 py-1.5 text-xs uppercase tracking-widest transition ${
              mode === m ? "bg-teal/15 text-teal" : "text-muted-foreground hover:text-foreground"
            }`}
          >
            {m === "deposit" ? (
              <ArrowDownToLine className="mr-1 inline h-3 w-3" />
            ) : (
              <ArrowUpFromLine className="mr-1 inline h-3 w-3" />
            )}
            {m}
          </button>
        ))}
      </div>

      <label className="mono mb-1 block text-[10px] uppercase tracking-widest text-muted-foreground">
        {mode === "deposit" ? "Amount (STT)" : `Shares (vVIG-${TIERS[tier].name})`}
      </label>
      <div className="relative">
        <input
          type="text"
          inputMode="decimal"
          placeholder="0.0"
          value={amount}
          onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
          className="mono w-full rounded-md border border-input bg-background px-3 py-2 text-sm tabular outline-none transition focus:border-teal focus:ring-1 focus:ring-teal"
        />
        {mode === "withdraw" && userShares > 0n && (
          <button
            type="button"
            onClick={() => setAmount(formatEther(userShares))}
            className="mono absolute right-2 top-1/2 -translate-y-1/2 rounded border border-teal/40 px-1.5 py-0.5 text-[9px] uppercase tracking-widest text-teal hover:bg-teal/10"
          >
            Max
          </button>
        )}
      </div>

      <div className="mono mt-2 min-h-[18px] text-[11px] text-muted-foreground tabular">
        {mode === "deposit" && previewShares.data !== undefined && (
          <>You receive ≈ {fmtSTT(previewShares.data as bigint, 6)} vVIG-{TIERS[tier].name}</>
        )}
        {mode === "withdraw" && previewAssets.data !== undefined && (
          <>You receive ≈ {fmtSTT(previewAssets.data as bigint)} STT</>
        )}
      </div>

      <button
        type="submit"
        disabled={!isConnected || isPending || !amount}
        className="mono mt-3 w-full rounded-md border border-teal/40 bg-teal/15 px-4 py-2 text-xs font-semibold uppercase tracking-widest text-teal transition hover:bg-teal/25 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {!isConnected
          ? "Connect wallet"
          : isPending
            ? "Confirming…"
            : mode === "deposit"
              ? "Deposit"
              : "Withdraw"}
      </button>
    </form>
  );
}

function parseSharesSafe(s: string): bigint {
  try {
    if (!s) return 0n;
    const [i, d = ""] = s.split(".");
    const padded = (d + "0".repeat(18)).slice(0, 18);
    return BigInt(i || "0") * 10n ** 18n + BigInt(padded || "0");
  } catch {
    return 0n;
  }
}
