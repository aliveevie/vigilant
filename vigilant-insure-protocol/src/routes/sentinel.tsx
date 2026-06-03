import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { isAddress, keccak256, toHex } from "viem";
import { useSentinelStats, useSentinelWrite, useWarningQuote } from "@/hooks/useSentinel";
import { fmtSTT } from "@/lib/format";
import { Hash } from "@/components/Mono";
import { txToast, errToast } from "@/lib/toast";
import { Eye, Trophy, ScrollText } from "lucide-react";

export const Route = createFileRoute("/sentinel")({
  head: () => ({ meta: [{ title: "Sentinel · Vigilant" }] }),
  component: SentinelTerminal,
});

function SentinelTerminal() {
  const { isConnected } = useAccount();
  const stats = useSentinelStats();
  const score = stats.data?.[0]?.result as bigint | undefined;
  const history = stats.data?.[1]?.result as
    | readonly { kind: number; blockNumber: bigint; scoreDelta: bigint }[]
    | undefined;

  return (
    <div className="space-y-8">
      <header>
        <div className="mono mb-1 text-[11px] uppercase tracking-[0.3em] text-muted-foreground">
          Watchtower
        </div>
        <h1 className="text-2xl font-semibold sm:text-3xl">Sentinel Terminal</h1>
        <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
          Be the first to flag a live exploit and earn a bounty. False or duplicate warnings
          forfeit your deposit. The AI base agent adjudicates every submission.
        </p>
      </header>

      <section className="grid gap-4 sm:grid-cols-3">
        <KpiCard
          icon={<Trophy className="h-4 w-4 text-amber" />}
          label="Reputation Score"
          value={score !== undefined ? score.toString() : "—"}
          accent="amber"
        />
        <KpiCard
          icon={<Eye className="h-4 w-4 text-teal" />}
          label="Warnings Logged"
          value={history ? history.length.toString() : "—"}
          accent="teal"
        />
        <KpiCard
          icon={<ScrollText className="h-4 w-4 text-teal" />}
          label="Status"
          value={isConnected ? "Active" : "Idle"}
          accent="teal"
        />
      </section>

      <div className="grid gap-6 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <SubmitWarningPanel />
        </div>
        <div className="lg:col-span-3">
          <HistoryPanel history={history} />
        </div>
      </div>
    </div>
  );
}

function KpiCard({
  icon,
  label,
  value,
  accent,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  accent: "teal" | "amber";
}) {
  const accentText = accent === "teal" ? "text-teal" : "text-amber";
  return (
    <div className="panel p-5">
      <div className="flex items-center justify-between">
        <span className="mono text-[10px] uppercase tracking-[0.25em] text-muted-foreground">
          {label}
        </span>
        {icon}
      </div>
      <div className={`mono mt-3 text-2xl font-semibold tabular ${accentText}`}>{value}</div>
    </div>
  );
}

function SubmitWarningPanel() {
  const [covered, setCovered] = useState("");
  const [evidence, setEvidence] = useState("");
  const [incidentBlock, setIncidentBlock] = useState("");
  const quote = useWarningQuote();
  const { submitWarning, isPending } = useSentinelWrite();
  const { isConnected } = useAccount();

  const evidenceHash = useMemo(() => {
    if (!evidence) return undefined;
    if (/^0x[0-9a-fA-F]{64}$/.test(evidence)) return evidence as `0x${string}`;
    return keccak256(toHex(evidence)) as `0x${string}`;
  }, [evidence]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isAddress(covered) || !evidenceHash || !incidentBlock || !quote.data) return;
    try {
      txToast("Submitting warning…");
      const hash = await submitWarning(
        covered as `0x${string}`,
        evidenceHash,
        BigInt(incidentBlock),
        quote.data as bigint,
      );
      txToast("Warning submitted · awaiting agent verdict", hash);
      setEvidence("");
      setIncidentBlock("");
    } catch (err) {
      errToast("Submit failed", err);
    }
  };

  return (
    <form onSubmit={submit} className="panel">
      <div className="border-b border-panel-border p-5">
        <div className="mono text-[11px] uppercase tracking-[0.3em] text-teal">Flag Exploit</div>
        <h2 className="mt-1 text-lg font-semibold">Submit Warning</h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Stake{" "}
          <span className="mono text-foreground">
            {quote.data ? fmtSTT(quote.data as bigint) : "—"} STT
          </span>{" "}
          deposit. Confirmed warnings unlock a bounty and pause coverage.
        </p>
      </div>
      <div className="space-y-3 p-5">
        <Field label="Covered contract">
          <input
            value={covered}
            onChange={(e) => setCovered(e.target.value)}
            placeholder="0x…"
            className="mono w-full rounded border border-input bg-background px-3 py-2 text-sm outline-none focus:border-teal focus:ring-1 focus:ring-teal"
          />
        </Field>
        <Field label="Evidence (tx hash or any string → keccak256)">
          <input
            value={evidence}
            onChange={(e) => setEvidence(e.target.value)}
            placeholder="0x…"
            className="mono w-full rounded border border-input bg-background px-3 py-2 text-sm outline-none focus:border-teal focus:ring-1 focus:ring-teal"
          />
          {evidenceHash && (
            <div className="mono mt-1 text-[10px] text-muted-foreground">
              hash: <Hash value={evidenceHash} />
            </div>
          )}
        </Field>
        <Field label="Incident block">
          <input
            value={incidentBlock}
            onChange={(e) => setIncidentBlock(e.target.value.replace(/[^0-9]/g, ""))}
            placeholder="123456"
            className="mono w-full rounded border border-input bg-background px-3 py-2 text-sm tabular outline-none focus:border-teal focus:ring-1 focus:ring-teal"
          />
        </Field>
        <button
          type="submit"
          disabled={
            !isConnected ||
            !isAddress(covered) ||
            !evidenceHash ||
            !incidentBlock ||
            !quote.data ||
            isPending
          }
          className="mono w-full rounded-md border border-amber/40 bg-amber/15 px-4 py-2 text-xs font-semibold uppercase tracking-widest text-amber transition hover:bg-amber/25 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {!isConnected ? "Connect wallet" : isPending ? "Confirming…" : "Submit warning"}
        </button>
      </div>
    </form>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="mono mb-1 text-[10px] uppercase tracking-widest text-muted-foreground">
        {label}
      </div>
      {children}
    </div>
  );
}

const KIND_LABEL: Record<number, { label: string; color: string }> = {
  0: { label: "Submitted", color: "text-muted-foreground border-panel-border bg-panel" },
  1: { label: "Confirmed", color: "text-success border-success/40 bg-success/10" },
  2: { label: "Unconfirmed", color: "text-rose border-rose/40 bg-rose/10" },
  3: { label: "Bounty Paid", color: "text-amber border-amber/40 bg-amber/10" },
};

function HistoryPanel({
  history,
}: {
  history?: readonly { kind: number; blockNumber: bigint; scoreDelta: bigint }[];
}) {
  return (
    <div className="panel">
      <div className="border-b border-panel-border p-5">
        <div className="mono text-[11px] uppercase tracking-[0.3em] text-muted-foreground">
          Activity Log
        </div>
        <h2 className="mt-1 text-lg font-semibold">Sentinel History</h2>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-left">
          <thead className="border-b border-panel-border bg-panel/50">
            <tr className="mono text-[10px] uppercase tracking-widest text-muted-foreground">
              <th className="px-4 py-2">Event</th>
              <th className="px-4 py-2">Block</th>
              <th className="px-4 py-2 text-right">Score Δ</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-panel-border">
            {!history || history.length === 0 ? (
              <tr>
                <td colSpan={3} className="p-5 text-center text-xs text-muted-foreground">
                  No history yet. Submit your first warning to start building reputation.
                </td>
              </tr>
            ) : (
              [...history].reverse().map((h, i) => {
                const k = KIND_LABEL[h.kind] ?? KIND_LABEL[0];
                const delta = Number(h.scoreDelta);
                return (
                  <tr key={i} className="text-sm transition hover:bg-panel/40">
                    <td className="px-4 py-2">
                      <span
                        className={`mono rounded border px-2 py-0.5 text-[10px] uppercase tracking-widest ${k.color}`}
                      >
                        {k.label}
                      </span>
                    </td>
                    <td className="mono px-4 py-2 tabular text-muted-foreground">
                      {h.blockNumber.toString()}
                    </td>
                    <td
                      className={`mono px-4 py-2 text-right tabular font-semibold ${
                        delta > 0 ? "text-success" : delta < 0 ? "text-rose" : "text-muted-foreground"
                      }`}
                    >
                      {delta > 0 ? "+" : ""}
                      {delta}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
