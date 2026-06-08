import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  parseEventLogs,
  zeroHash,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { somniaTestnet, CONTRACTS, settings, explorerTx } from "./config.js";
import { policyManagerAbi, sentinelRegistryAbi } from "./abi.js";
import { log } from "./log.js";

/// One-command, end-to-end demonstration of Vigilant's agent stack, driven
/// entirely from a single funded wallet — ideal for screen recording.
///
///   Act 1: request a real risk score → wait for the onchain LLM agent callback.
///   Act 2: autonomously file an exploit warning → wait for the LLM verdict.
///
/// No human files anything mid-run; the wallet is the autonomous agent's identity.
export async function runDemo(privateKey: Hex) {
  const account = privateKeyToAccount(privateKey);
  const pub = createPublicClient({ chain: somniaTestnet, transport: http() });
  const wallet = createWalletClient({ account, chain: somniaTestnet, transport: http() });

  // Target to analyse. Defaults to the Somnia Agents platform contract as a
  // representative onchain address; override with `--target 0x...`.
  const targetArg = process.argv.indexOf("--target");
  const target: Address =
    targetArg > -1 ? (process.argv[targetArg + 1] as Address) : (CONTRACTS.PolicyManager as Address);

  log.banner("VIGILANT · End-to-End Agent Demo");
  log.info(`agent identity   ${account.address}`);
  const bal = await pub.getBalance({ address: account.address });
  log.info(`balance          ${formatEther(bal)} STT`);
  log.info(`target contract  ${target}`);

  // ───────────────────────────────── Act 1 ─────────────────────────────────
  log.banner("ACT 1 · Onchain AI risk scoring");

  const riskDeposit = (await pub.readContract({
    address: CONTRACTS.PolicyManager,
    abi: policyManagerAbi,
    functionName: "quoteRiskScoreDeposit",
  })) as bigint;
  log.act(`requesting risk score (deposit ${formatEther(riskDeposit)} STT)…`);

  const reqHash = await wallet.writeContract({
    address: CONTRACTS.PolicyManager,
    abi: policyManagerAbi,
    functionName: "requestRiskScore",
    args: [target],
    value: riskDeposit,
    gas: settings.gasLimit,
  });
  log.act(`request tx: ${explorerTx(reqHash)}`);
  await pub.waitForTransactionReceipt({ hash: reqHash });
  log.ok("request accepted — Somnia LLM agent scoring by validator consensus");
  log.watch("awaiting handleResponse callback…");

  const score = await waitFor(async () => {
    const t = (await pub.readContract({
      address: CONTRACTS.PolicyManager,
      abi: policyManagerAbi,
      functionName: "coveredContractTier",
      args: [target],
    })) as readonly [number, number, bigint, bigint, Hex];
    const [tier, scoreVal, , expires] = t;
    return expires > 0n ? { tier, scoreVal } : null;
  });

  const tierName = ["A", "B", "C"][score.tier] ?? "?";
  log.ok(`AI VERDICT: risk score ${score.scoreVal}/100 → Tier ${tierName}`);

  // ───────────────────────────────── Act 2 ─────────────────────────────────
  log.banner("ACT 2 · Autonomous Sentinel warning");

  const warnDeposit = (await pub.readContract({
    address: CONTRACTS.SentinelRegistry,
    abi: sentinelRegistryAbi,
    functionName: "quoteWarningDeposit",
  })) as bigint;

  log.alert(`exploit signal detected on ${target}`);
  log.act(`autonomously filing onchain warning (deposit ${formatEther(warnDeposit)} STT)…`);

  const incidentBlock = await pub.getBlockNumber();
  const evidence: Hex = (`0x${"ee".repeat(32)}`) as Hex;

  const warnHash = await wallet.writeContract({
    address: CONTRACTS.SentinelRegistry,
    abi: sentinelRegistryAbi,
    functionName: "submitWarning",
    args: [target, evidence, incidentBlock],
    value: warnDeposit,
    gas: settings.gasLimit,
  });
  log.act(`warning tx: ${explorerTx(warnHash)}`);
  const warnReceipt = await pub.waitForTransactionReceipt({ hash: warnHash });
  const submitted = parseEventLogs({
    abi: sentinelRegistryAbi,
    logs: warnReceipt.logs,
    eventName: "WarningSubmitted",
  });
  const warningId = (submitted[0] as any)?.args?.warningId as bigint;
  log.ok(`warning #${warningId} accepted — Somnia LLM agent adjudicating`);
  log.watch("awaiting verdict callback…");

  const verdict = await waitFor(async () => {
    const w = (await pub.readContract({
      address: CONTRACTS.SentinelRegistry,
      abi: sentinelRegistryAbi,
      functionName: "warnings",
      args: [warningId],
    })) as readonly [Address, Address, Hex, bigint, bigint, bigint, boolean, boolean];
    const resolved = w[6];
    const confirmed = w[7];
    return resolved ? { confirmed } : null;
  });

  if (verdict.confirmed) {
    log.alert(
      `AI VERDICT: CONFIRMED — coverage auto-paused for ${target}, no human in the loop`,
    );
  } else {
    log.ok(
      `AI VERDICT: UNCONFIRMED — baseless alarm correctly rejected (the agent is a real ` +
        `decision-maker, not a rubber stamp)`,
    );
  }

  log.banner("DEMO COMPLETE · detect → request → AI consensus → act, fully autonomous");
}

/// Poll a producer until it returns non-null, or time out.
async function waitFor<T>(fn: () => Promise<T | null>, timeoutMs = 120_000): Promise<T> {
  const start = Date.now();
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const v = await fn();
    if (v != null) return v;
    if (Date.now() - start > timeoutMs) throw new Error("timed out waiting for agent callback");
    await new Promise((r) => setTimeout(r, 3000));
  }
}

// silence unused import warning when zeroHash isn't referenced
void zeroHash;
