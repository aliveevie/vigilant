# Vigilant — Autonomous Sentinel Agent

An off-chain daemon that makes Vigilant **agent-driven**, not just agent-calling.
It runs with **no human in the loop**:

1. **Discovers** covered contracts by reading `PolicyManager.PolicyIssued` events.
2. **Monitors** each one's native balance for drain-style anomalies (a balance
   drop beyond `DROP_THRESHOLD` within one poll window).
3. **Reacts** autonomously: it calls `SentinelRegistry.submitWarning(...)` itself,
   paying the deposit from its own key.
4. The onchain **Somnia LLM Inference agent** then adjudicates the warning by
   validator consensus. A `Confirmed` verdict auto-pauses coverage for that
   contract; an `Unconfirmed` verdict forfeits the deposit.

So two autonomous agents compose: an off-chain watcher that *detects and reports*,
and an onchain AI committee that *adjudicates and acts*. No DAO vote, no human
adjuster, no off-chain attestation.

## Run

```bash
cd agent
npm install
cp .env.example .env        # set SENTINEL_PRIVATE_KEY to a funded hot wallet
npm start                   # live monitoring
npm run simulate            # inject a synthetic exploit signal to demo the full flow
```

The wallet needs ~0.3 STT per warning (deposit + gas). Get testnet STT from the
Somnia faucet.

## Proven live

See [`../deployments/AGENT_PROOF.md`](../deployments/AGENT_PROOF.md). A real run
autonomously filed warning #1 and the onchain LLM agent returned a consensus
verdict in ~4 seconds.

## Files

- `src/config.ts` — chain + live contract addresses + tunables
- `src/abi.ts` — minimal ABI fragments the agent calls
- `src/sentinel.ts` — discover / monitor / react loops
- `src/index.ts` — entrypoint

## Design notes

- Somnia caps `eth_getLogs` at 1000 blocks; discovery scans in 1000-block chunks.
- Somnia charges extra gas per calldata byte (warnings carry a ~600B prompt), so
  the agent sends a 5,000,000 gas limit.
- The balance-drop heuristic is intentionally simple and swappable — the point is
  the autonomous detect→report→adjudicate→act loop, which any detector can drive.
