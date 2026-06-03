import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useAccount, useBlockNumber } from "wagmi";
import { isAddress, keccak256, parseEther, toHex, zeroAddress } from "viem";
import {
  useCoveredContractTier,
  usePolicies,
  usePoliciesOf,
  usePolicyWrite,
  useRiskScoreQuote,
  useUsedNonce,
  useClaimQuote,
  useClaim,
  useFileClaimWrite,
  POLICY_TYPES,
  POLICY_STATE,
  CLAIM_STATE,
  useSignPolicy,
} from "@/hooks/usePolicy";
import { CONTRACTS, TIERS } from "@/lib/contracts";
import { somniaTestnet } from "@/lib/somnia";
import { fmtSTT } from "@/lib/format";
import { Address, Hash } from "@/components/Mono";
import { txToast, errToast } from "@/lib/toast";
import { Brain, FileSignature, Loader2, Shield, AlertTriangle } from "lucide-react";

export const Route = createFileRoute("/coverage")({
  head: () => ({ meta: [{ title: "Coverage · Vigilant" }] }),
  component: CoverageConsole,
});

function CoverageConsole() {
  const { isConnected } = useAccount();
  return (
    <div className="space-y-8">
      <header>
        <div className="mono mb-1 text-[11px] uppercase tracking-[0.3em] text-muted-foreground">
          Policy Layer
        </div>
        <h1 className="text-2xl font-semibold sm:text-3xl">Policyholder Console</h1>
        <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
          Parametric exploit coverage for any onchain contract. Risk is tiered by Somnia's onchain
          LLM agent; verdicts on claims reach validator consensus, not a human adjuster.
        </p>
      </header>

      <div className="grid gap-6 lg:grid-cols-5">
        <div className="lg:col-span-3">
          <BuyCoveragePanel />
        </div>
        <div className="lg:col-span-2">
          <PoliciesPanel />
        </div>
      </div>

      {!isConnected && (
        <div className="panel p-4 text-center text-sm text-muted-foreground">
          Connect a wallet on Somnia Shannon Testnet to begin.
        </div>
      )}
    </div>
  );
}

function BuyCoveragePanel() {
  const { address, chainId } = useAccount();
  const [covered, setCovered] = useState("");
  const [coverage, setCoverage] = useState("");
  const [duration, setDuration] = useState("100000"); // blocks
  const { data: block } = useBlockNumber({ watch: true });

  const validCovered = isAddress(covered) ? (covered as `0x${string}`) : undefined;
  const tierRead = useCoveredContractTier(validCovered);
  const tierData = tierRead.data as
    | readonly [number, number, bigint, bigint, `0x${string}`]
    | undefined;
  const [tier, score, cachedAtBlock, expiresAtBlock, rationaleHash] = tierData ?? [
    0,
    0,
    0n,
    0n,
    "0x" as `0x${string}`,
  ];
  const isCached = tierData && cachedAtBlock > 0n;
  const isExpired = isCached && block && expiresAtBlock <= block;

  const quote = useRiskScoreQuote();
  const usedNonce = useUsedNonce();
  const { requestRiskScore, issue, isPending } = usePolicyWrite();
  const { signTypedDataAsync, isPending: signing } = useSignPolicy();

  const onRequest = async () => {
    if (!validCovered || !quote.data) return;
    try {
      txToast("Requesting AI risk score…");
      const hash = await requestRiskScore(validCovered, quote.data as bigint);
      txToast("Risk score requested · awaiting agent consensus", hash);
    } catch (e) {
      errToast("Request failed", e);
    }
  };

  const tierMeta = TIERS[tier as 0 | 1 | 2];
  const baseMultiplier = [50, 150, 400][tier] ?? 100; // bps fallback
  const coverageWei = (() => {
    try { return coverage ? parseEther(coverage as `${number}`) : 0n; } catch { return 0n; }
  })();
  // Premium estimate (UI-only, contract enforces real value): coverage * multiplierBps / 10000
  const estPremium = (coverageWei * BigInt(baseMultiplier)) / 10000n;

  const onBuy = async () => {
    if (!validCovered || !address || !block || !isCached || coverageWei === 0n) return;
    if (isExpired) {
      errToast("Tier expired", new Error("Re-request the AI risk score before issuing."));
      return;
    }
    try {
      const nonce = ((usedNonce.data as bigint | undefined) ?? 0n) + 1n;
      const startBlock = block + 1n;
      const endBlock = startBlock + BigInt(duration || "1");
      const policy = {
        policyholder: address,
        coveredContract: validCovered,
        coverageAmount: coverageWei,
        riskTier: tier,
        premium: estPremium,
        startBlock,
        endBlock,
        nonce,
      };
      txToast("Sign policy in your wallet…");
      const signature = await signTypedDataAsync({
        domain: {
          name: "Vigilant",
          version: "1",
          chainId: somniaTestnet.id,
          verifyingContract: CONTRACTS.PolicyManager,
        },
        types: POLICY_TYPES,
        primaryType: "RiskPolicy",
        message: policy as any,
      });
      txToast("Submitting policy on-chain…");
      const hash = await issue(policy, signature as `0x${string}`, estPremium);
      txToast("Policy issued", hash);
      setCoverage("");
    } catch (e) {
      errToast("Issue failed", e);
    }
  };

  return (
    <div className="panel">
      <div className="border-b border-panel-border p-5">
        <div className="mono text-[11px] uppercase tracking-[0.3em] text-teal">Step A</div>
        <h2 className="mt-1 flex items-center gap-2 text-lg font-semibold">
          <Brain className="h-4 w-4 text-teal" /> Request AI Risk Score
        </h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Submit any contract address — the Somnia base agent answers with a deterministic
          consensus tier (A/B/C) one round later.
        </p>
      </div>

      <div className="space-y-4 p-5">
        <div>
          <label className="mono mb-1 block text-[10px] uppercase tracking-widest text-muted-foreground">
            Covered contract address
          </label>
          <input
            value={covered}
            onChange={(e) => setCovered(e.target.value)}
            placeholder={zeroAddress}
            className="mono w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:border-teal focus:ring-1 focus:ring-teal"
          />
        </div>

        <div className="rounded-md border border-panel-border bg-background/40 p-3">
          {!validCovered ? (
            <div className="mono text-xs text-muted-foreground">
              Enter a valid 0x address to fetch its cached tier.
            </div>
          ) : tierRead.isFetching && !tierData ? (
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Loader2 className="h-3 w-3 animate-spin" /> Reading tier cache…
            </div>
          ) : !isCached ? (
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="mono text-[10px] uppercase tracking-widest text-amber">
                  No cached tier
                </div>
                <div className="mt-1 text-xs text-muted-foreground">
                  Deposit{" "}
                  <span className="mono">
                    {quote.data ? fmtSTT(quote.data as bigint) : "—"} STT
                  </span>{" "}
                  to ask the agent. Result appears here after consensus.
                </div>
              </div>
              <button
                onClick={onRequest}
                disabled={!quote.data || isPending}
                className="mono shrink-0 rounded-md border border-teal/40 bg-teal/15 px-3 py-1.5 text-xs uppercase tracking-widest text-teal hover:bg-teal/25 disabled:opacity-50"
              >
                {isPending ? "…" : "Request score"}
              </button>
            </div>
          ) : (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <div>
                  <div className="mono text-[10px] uppercase tracking-widest text-muted-foreground">
                    AI Verdict
                  </div>
                  <div className="mt-1 flex items-baseline gap-3">
                    <span className="mono text-2xl font-semibold text-teal">
                      Tier {tierMeta?.name}
                    </span>
                    <span className="mono text-xs text-muted-foreground">
                      score {score} / 100
                    </span>
                  </div>
                </div>
                {isExpired ? (
                  <span className="mono rounded border border-amber/40 bg-amber/10 px-2 py-0.5 text-[10px] uppercase tracking-widest text-amber">
                    Expired
                  </span>
                ) : (
                  <span className="mono rounded border border-success/40 bg-success/10 px-2 py-0.5 text-[10px] uppercase tracking-widest text-success">
                    Live
                  </span>
                )}
              </div>
              <div className="mono grid grid-cols-2 gap-2 text-[11px] text-muted-foreground">
                <div>
                  Cached @ block{" "}
                  <span className="text-foreground">{cachedAtBlock.toString()}</span>
                </div>
                <div>
                  Expires @ block{" "}
                  <span className="text-foreground">{expiresAtBlock.toString()}</span>
                </div>
                <div className="col-span-2">
                  Rationale hash <Hash value={rationaleHash} />
                </div>
              </div>
              {isExpired && (
                <button
                  onClick={onRequest}
                  className="mono rounded-md border border-amber/40 bg-amber/10 px-3 py-1 text-[10px] uppercase tracking-widest text-amber hover:bg-amber/20"
                >
                  Re-request
                </button>
              )}
            </div>
          )}
        </div>

        <div className="border-t border-panel-border pt-4">
          <div className="mono text-[11px] uppercase tracking-[0.3em] text-teal">Step B</div>
          <h3 className="mt-1 flex items-center gap-2 text-base font-semibold">
            <FileSignature className="h-4 w-4 text-teal" /> Issue Policy
          </h3>

          <div className="mt-3 grid gap-3 sm:grid-cols-2">
            <div>
              <label className="mono mb-1 block text-[10px] uppercase tracking-widest text-muted-foreground">
                Coverage amount (STT)
              </label>
              <input
                value={coverage}
                onChange={(e) => setCoverage(e.target.value.replace(/[^0-9.]/g, ""))}
                placeholder="0.0"
                className="mono w-full rounded-md border border-input bg-background px-3 py-2 text-sm tabular outline-none focus:border-teal focus:ring-1 focus:ring-teal"
              />
            </div>
            <div>
              <label className="mono mb-1 block text-[10px] uppercase tracking-widest text-muted-foreground">
                Duration (blocks)
              </label>
              <input
                value={duration}
                onChange={(e) => setDuration(e.target.value.replace(/[^0-9]/g, ""))}
                className="mono w-full rounded-md border border-input bg-background px-3 py-2 text-sm tabular outline-none focus:border-teal focus:ring-1 focus:ring-teal"
              />
            </div>
          </div>

          <div className="mono mt-3 flex items-center justify-between rounded-md border border-panel-border bg-background/40 px-3 py-2 text-xs">
            <span className="text-muted-foreground">Estimated premium</span>
            <span className="tabular font-semibold text-teal">{fmtSTT(estPremium)} STT</span>
          </div>

          <button
            onClick={onBuy}
            disabled={!isCached || isExpired || !coverageWei || isPending || signing || chainId !== somniaTestnet.id}
            className="mono mt-3 w-full rounded-md border border-teal/40 bg-teal/15 px-4 py-2 text-xs font-semibold uppercase tracking-widest text-teal hover:bg-teal/25 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {signing ? "Sign in wallet…" : isPending ? "Confirming…" : "Sign & issue policy"}
          </button>
        </div>
      </div>
    </div>
  );
}

function PoliciesPanel() {
  const policyIds = usePoliciesOf();
  const ids = policyIds.data as readonly bigint[] | undefined;
  const policies = usePolicies(ids);

  return (
    <div className="panel">
      <div className="border-b border-panel-border p-5">
        <div className="mono text-[11px] uppercase tracking-[0.3em] text-muted-foreground">
          Active Coverage
        </div>
        <h2 className="mt-1 flex items-center gap-2 text-lg font-semibold">
          <Shield className="h-4 w-4 text-teal" /> Your Policies
        </h2>
      </div>
      <div className="divide-y divide-panel-border">
        {!ids || ids.length === 0 ? (
          <div className="p-5 text-center text-xs text-muted-foreground">
            No policies yet. Issue your first coverage above.
          </div>
        ) : (
          ids.map((id, i) => {
            const p = policies.data?.[i]?.result as any;
            return <PolicyRow key={id.toString()} id={id} p={p} />;
          })
        )}
      </div>
    </div>
  );
}

function PolicyRow({ id, p }: { id: bigint; p: any }) {
  const [claimOpen, setClaimOpen] = useState(false);
  if (!p) {
    return (
      <div className="flex items-center gap-2 p-4 text-xs text-muted-foreground">
        <Loader2 className="h-3 w-3 animate-spin" /> Loading policy #{id.toString()}
      </div>
    );
  }
  const [, state, paidOut, , coveredContract, coverageAmount, riskTier, startBlock, endBlock] = p as readonly [
    `0x${string}`,
    number,
    bigint,
    `0x${string}`,
    `0x${string}`,
    bigint,
    number,
    bigint,
    bigint,
  ];
  const stateLabel = POLICY_STATE[state] ?? `#${state}`;
  const stateColor =
    stateLabel === "Active"
      ? "text-success border-success/40 bg-success/10"
      : stateLabel === "PaidOut"
        ? "text-teal border-teal/40 bg-teal/10"
        : "text-muted-foreground border-panel-border bg-panel";

  return (
    <div className="p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="mono text-[10px] uppercase tracking-widest text-muted-foreground">
            Policy #{id.toString()} · Tier {TIERS[riskTier as 0 | 1 | 2]?.name}
          </div>
          <div className="mt-1 text-sm">
            <Address value={coveredContract} />
          </div>
        </div>
        <span
          className={`mono shrink-0 rounded border px-2 py-0.5 text-[10px] uppercase tracking-widest ${stateColor}`}
        >
          {stateLabel}
        </span>
      </div>
      <div className="mono mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-[11px] text-muted-foreground tabular">
        <div>
          Coverage <span className="text-foreground">{fmtSTT(coverageAmount)} STT</span>
        </div>
        <div>
          Paid out <span className="text-foreground">{fmtSTT(paidOut)} STT</span>
        </div>
        <div>
          Start <span className="text-foreground">{startBlock.toString()}</span>
        </div>
        <div>
          End <span className="text-foreground">{endBlock.toString()}</span>
        </div>
      </div>
      <button
        onClick={() => setClaimOpen((o) => !o)}
        className="mono mt-3 inline-flex items-center gap-1 rounded border border-amber/40 bg-amber/10 px-2 py-1 text-[10px] uppercase tracking-widest text-amber hover:bg-amber/20"
      >
        <AlertTriangle className="h-3 w-3" /> File claim
      </button>
      {claimOpen && <FileClaimForm policyId={id} onClose={() => setClaimOpen(false)} />}
    </div>
  );
}

function FileClaimForm({ policyId, onClose }: { policyId: bigint; onClose: () => void }) {
  const [exploitTx, setExploitTx] = useState("");
  const [incidentBlock, setIncidentBlock] = useState("");
  const [claimIdHint, setClaimIdHint] = useState<bigint | undefined>(undefined);
  const quotes = useClaimQuote();
  const claimDeposit = quotes.data?.[0]?.result as bigint | undefined;
  const escalationDeposit = quotes.data?.[1]?.result as bigint | undefined;
  const { fileClaim, escalate, isPending } = useFileClaimWrite();
  const claim = useClaim(claimIdHint);
  const claimState = claim.data ? (claim.data as any)[0] : undefined;

  const hash32 = useMemo(() => {
    if (!exploitTx) return undefined;
    if (/^0x[0-9a-fA-F]{64}$/.test(exploitTx)) return exploitTx as `0x${string}`;
    return keccak256(toHex(exploitTx)) as `0x${string}`;
  }, [exploitTx]);

  const submit = async () => {
    if (!hash32 || !claimDeposit || !incidentBlock) return;
    try {
      txToast("Filing claim…");
      const hash = await fileClaim(policyId, hash32, BigInt(incidentBlock), claimDeposit);
      txToast("Claim filed", hash);
    } catch (e) {
      errToast("File claim failed", e);
    }
  };

  return (
    <div className="mt-3 rounded-md border border-panel-border bg-background/40 p-3">
      <div className="grid gap-2">
        <input
          value={exploitTx}
          onChange={(e) => setExploitTx(e.target.value)}
          placeholder="Exploit tx hash (0x… 32 bytes)"
          className="mono w-full rounded border border-input bg-background px-2 py-1.5 text-xs outline-none focus:border-amber"
        />
        <input
          value={incidentBlock}
          onChange={(e) => setIncidentBlock(e.target.value.replace(/[^0-9]/g, ""))}
          placeholder="Incident block number"
          className="mono w-full rounded border border-input bg-background px-2 py-1.5 text-xs tabular outline-none focus:border-amber"
        />
        <input
          value={claimIdHint?.toString() ?? ""}
          onChange={(e) => {
            const v = e.target.value.replace(/[^0-9]/g, "");
            setClaimIdHint(v ? BigInt(v) : undefined);
          }}
          placeholder="Track existing claim id (optional)"
          className="mono w-full rounded border border-input bg-background px-2 py-1.5 text-xs tabular outline-none focus:border-amber"
        />
      </div>
      <div className="mono mt-2 flex justify-between text-[10px] text-muted-foreground">
        <span>Required deposit</span>
        <span className="tabular text-foreground">{fmtSTT(claimDeposit)} STT</span>
      </div>
      {claimState !== undefined && (
        <div className="mono mt-2 flex justify-between text-[10px]">
          <span className="text-muted-foreground">Tracked claim status</span>
          <span className="text-teal">{CLAIM_STATE[claimState as number] ?? "?"}</span>
        </div>
      )}
      <div className="mt-2 flex gap-2">
        <button
          onClick={submit}
          disabled={!hash32 || !claimDeposit || !incidentBlock || isPending}
          className="mono flex-1 rounded border border-amber/40 bg-amber/15 px-3 py-1.5 text-[10px] uppercase tracking-widest text-amber hover:bg-amber/25 disabled:opacity-50"
        >
          {isPending ? "…" : "Submit claim"}
        </button>
        <button
          onClick={async () => {
            if (!claimIdHint || !escalationDeposit) return;
            try {
              txToast("Escalating claim…");
              const h = await escalate(claimIdHint, escalationDeposit);
              txToast("Escalation submitted", h);
            } catch (e) {
              errToast("Escalate failed", e);
            }
          }}
          disabled={!claimIdHint || !escalationDeposit || isPending}
          className="mono flex-1 rounded border border-rose/40 bg-rose/15 px-3 py-1.5 text-[10px] uppercase tracking-widest text-rose hover:bg-rose/25 disabled:opacity-50"
        >
          Escalate
        </button>
        <button
          onClick={onClose}
          className="mono rounded border border-panel-border px-2 py-1.5 text-[10px] uppercase tracking-widest text-muted-foreground hover:bg-panel"
        >
          Close
        </button>
      </div>
    </div>
  );
}
