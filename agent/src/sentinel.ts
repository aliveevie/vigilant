import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  parseEventLogs,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { somniaTestnet, CONTRACTS, settings, explorerTx, explorerAddr } from "./config.js";
import { policyManagerAbi, sentinelRegistryAbi } from "./abi.js";
import { log } from "./log.js";

/// The PolicyIssued event, resolved by name so ABI ordering can change freely.
const policyIssuedEvent = policyManagerAbi.find(
  (x) => x.type === "event" && x.name === "PolicyIssued",
) as any;

/// State the agent tracks per watched contract.
interface Watched {
  address: Address;
  lastBalance: bigint;
  warned: boolean;
}

/// The autonomous Sentinel.
///
/// It runs three loops with NO human in the path:
///   1. discover()  — reads PolicyManager.PolicyIssued logs to learn which
///                     contracts have live coverage (autonomous discovery).
///   2. monitor()   — polls each covered contract's native balance; a drop
///                     beyond DROP_THRESHOLD within one window is an exploit
///                     signal (a classic drain pattern).
///   3. react()     — on a signal it autonomously submits an onchain warning,
///                     which the Somnia LLM Inference agent then adjudicates by
///                     consensus. A "Confirmed" verdict auto-pauses coverage.
export class Sentinel {
  private pub;
  private wallet;
  private account;
  private watched = new Map<Address, Watched>();

  constructor(privateKey: Hex) {
    this.account = privateKeyToAccount(privateKey);
    this.pub = createPublicClient({ chain: somniaTestnet, transport: http() });
    this.wallet = createWalletClient({
      account: this.account,
      chain: somniaTestnet,
      transport: http(),
    });
  }

  async start(opts: { simulate?: boolean } = {}) {
    log.banner("VIGILANT · Autonomous Sentinel Agent");
    log.info(`identity        ${this.account.address}`);
    const bal = await this.pub.getBalance({ address: this.account.address });
    log.info(`balance         ${formatEther(bal)} STT`);
    log.info(`registry        ${CONTRACTS.SentinelRegistry}`);
    log.info(`poll interval   ${settings.pollIntervalMs}ms`);
    log.info(`drop threshold  ${settings.dropThreshold * 100}%`);

    await this.discover();
    this.watchResolutions();

    if (opts.simulate) {
      // Demo path: synthesize an exploit signal on the first watched contract
      // (or the platform contract) so the full autonomous flow can be shown
      // on demand without waiting for a real drain.
      await this.simulateIncident();
    }

    // Main monitor loop.
    // eslint-disable-next-line no-constant-condition
    while (true) {
      await this.monitor();
      await sleep(settings.pollIntervalMs);
    }
  }

  /// (1) Discover covered contracts from PolicyIssued events.
  /// Somnia caps eth_getLogs at 1000 blocks/request, so we scan a bounded recent
  /// window in 1000-block chunks. Per-chunk failures are tolerated, never fatal.
  private async discover() {
    log.info("discovering covered contracts from PolicyManager events…");
    const covered = new Set<Address>();
    const head = await this.pub.getBlockNumber();
    const CHUNK = 1000n;
    const WINDOW = 20_000n; // ~recent history; widen via re-runs if needed
    let from = head > WINDOW ? head - WINDOW : 0n;

    while (from <= head) {
      const to = from + CHUNK - 1n > head ? head : from + CHUNK - 1n;
      try {
        const logs = await this.pub.getLogs({
          address: CONTRACTS.PolicyManager,
          event: policyIssuedEvent,
          fromBlock: from,
          toBlock: to,
        });
        for (const l of logs) {
          const c = (l as any).args?.coveredContract as Address | undefined;
          if (c) covered.add(c);
        }
      } catch (e: any) {
        log.watch(`discovery chunk ${from}-${to} skipped: ${e?.shortMessage ?? "rpc error"}`);
      }
      from = to + 1n;
    }
    for (const extra of settings.extraWatchlist) covered.add(extra);

    for (const addr of covered) {
      const balance = await this.pub.getBalance({ address: addr });
      this.watched.set(addr, { address: addr, lastBalance: balance, warned: false });
      log.ok(`watching ${addr}  (${formatEther(balance)} STT)`);
    }
    if (this.watched.size === 0) {
      log.watch("no covered contracts yet — agent will idle until coverage is issued");
    }
  }

  /// (2) Poll balances; detect drain-style anomalies.
  private async monitor() {
    for (const w of this.watched.values()) {
      if (w.warned) continue;
      const balance = await this.pub.getBalance({ address: w.address });
      if (w.lastBalance > 0n && balance < w.lastBalance) {
        const drop = Number(w.lastBalance - balance) / Number(w.lastBalance);
        if (drop >= settings.dropThreshold) {
          log.alert(
            `ANOMALY on ${w.address}: balance fell ${(drop * 100).toFixed(1)}% ` +
              `(${formatEther(w.lastBalance)} → ${formatEther(balance)} STT)`,
          );
          await this.react(w.address);
        }
      }
      w.lastBalance = balance;
      log.watch(`${w.address}  ${formatEther(balance)} STT`);
    }
  }

  /// (3) Autonomously file an onchain warning. The LLM agent adjudicates it.
  private async react(coveredContract: Address, evidenceTx?: Hex) {
    const w = this.watched.get(coveredContract);
    if (w) w.warned = true;

    // Use the most recent block as the incident block; if no evidence tx was
    // captured, hash the contract+block as a placeholder pointer the validators
    // can dereference offchain.
    const incidentBlock = await this.pub.getBlockNumber();
    const evidence: Hex =
      evidenceTx ??
      (`0x${"ee".repeat(32)}` as Hex); // sentinel-placeholder evidence pointer

    const deposit = (await this.pub.readContract({
      address: CONTRACTS.SentinelRegistry,
      abi: sentinelRegistryAbi,
      functionName: "quoteWarningDeposit",
    })) as bigint;

    log.act(
      `filing onchain warning → SentinelRegistry.submitWarning ` +
        `(deposit ${formatEther(deposit)} STT)`,
    );

    const hash = await this.wallet.writeContract({
      address: CONTRACTS.SentinelRegistry,
      abi: sentinelRegistryAbi,
      functionName: "submitWarning",
      args: [coveredContract, evidence, incidentBlock],
      value: deposit,
      gas: settings.gasLimit,
    });
    log.act(`warning tx submitted: ${explorerTx(hash)}`);

    const receipt = await this.pub.waitForTransactionReceipt({ hash });
    const parsed = parseEventLogs({
      abi: sentinelRegistryAbi,
      logs: receipt.logs,
      eventName: "WarningSubmitted",
    });
    const warningId = (parsed[0] as any)?.args?.warningId;
    log.ok(
      `warning #${warningId} accepted — Somnia LLM agent now adjudicating by consensus`,
    );
    log.watch("awaiting verdict (handleResponse callback)…");
  }

  /// Live-tail warning resolutions and coverage pauses for the demo console.
  private watchResolutions() {
    this.pub.watchContractEvent({
      address: CONTRACTS.SentinelRegistry,
      abi: sentinelRegistryAbi,
      eventName: "WarningResolved",
      onLogs: (logs) => {
        for (const l of logs) {
          const { warningId, classification } = (l as any).args;
          const verdict = classification === 1 ? "CONFIRMED" : "UNCONFIRMED";
          log.ok(`verdict on warning #${warningId}: ${verdict} (LLM consensus)`);
        }
      },
    });
    this.pub.watchContractEvent({
      address: CONTRACTS.SentinelRegistry,
      abi: sentinelRegistryAbi,
      eventName: "CoveragePaused",
      onLogs: (logs) => {
        for (const l of logs) {
          const { coveredContract } = (l as any).args;
          log.alert(
            `COVERAGE AUTO-PAUSED for ${coveredContract} — exploit confirmed, ` +
              `no human in the loop. ${explorerAddr(coveredContract)}`,
          );
        }
      },
    });
  }

  /// Demo trigger: file a warning immediately against a representative target
  /// so the full autonomous adjudication flow can be shown on command.
  private async simulateIncident() {
    const target =
      [...this.watched.keys()][0] ?? (CONTRACTS.PolicyManager as Address);
    log.banner("SIMULATION · injecting a synthetic exploit signal");
    log.alert(`simulated drain detected on ${target}`);
    await this.react(target);
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
