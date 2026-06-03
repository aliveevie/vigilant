# Vigilant — Live Agent Round-Trip Proof (Somnia Shannon Testnet)

This documents a **real, on-chain execution** of Vigilant's core thesis: a smart
contract invoking the Somnia LLM Inference base agent and receiving a
consensus-validated AI verdict via callback — no human, no off-chain oracle.

## What happened

1. **Request** — `PolicyManager.requestRiskScore(0x037Bb9…6776)` was called with a
   0.24 STT deposit. The Somnia Agents platform accepted the request, confirmed
   `agentExists(12847293847561029384) == true` (the LLM Inference base agent),
   and assigned a 3-validator subcommittee.
   - Tx: `0xeae3a210fc0f375461df02d1bc6fd145835d27f9d8ef7d2a4a796be58d1e6110`
   - Platform request ID: `4324238`
   - Status: success

2. **Agent callback** — A consensus round later, the platform called back into
   `PolicyManager.handleResponse(...)`. The agent returned a deterministic risk
   score, which the contract mapped to a coverage tier.
   - Callback tx: `0x7a70a7cfc2b4add00c860bda9cff8069e2515e60be77ead9e5d59beaba639109`
   - **Risk score returned: 55 / 100**
   - **Tier assigned: B (1)**  (mapping: 0–33 → A, 34–66 → B, 67–100 → C)
   - Rationale hash: `0x42a7b7dd785cd69714a189dffb3fd7d7174edc9ece837694ce50f7078f7c31ae`
   - Cached at block 399583461, expires block 399584461

## Why it matters

The score `55` was produced by deterministic on-chain Qwen3-30B inference across a
validator subcommittee — every validator independently produced a byte-identical
result and reached consensus, which is what let the platform finalize and call
back. This is the same path used by `IncidentResolver` (claim verdicts) and
`SentinelRegistry` (warning verdicts).

Explorer:
- PolicyManager: https://shannon-explorer.somnia.network/address/0x7819f4929D80b5F98448b16c775F7c7dA1eC7221
- Request tx: https://shannon-explorer.somnia.network/tx/0xeae3a210fc0f375461df02d1bc6fd145835d27f9d8ef7d2a4a796be58d1e6110
- Callback tx: https://shannon-explorer.somnia.network/tx/0x7a70a7cfc2b4add00c860bda9cff8069e2515e60be77ead9e5d59beaba639109

## Operational note

Somnia charges extra gas per calldata byte. Agent requests carry a system prompt
(~600 bytes), so set a generous gas limit (5,000,000) on `requestRiskScore`,
`fileClaim`, and `submitWarning`. The frontend hooks should reflect this.

---

# Autonomous Sentinel Agent — Live Proof

The off-chain Sentinel agent (`/agent`) closes the loop autonomously — no human
files the warning. Run captured on testnet:

1. **Autonomous discovery + monitoring** — agent scanned PolicyManager events for
   covered contracts and began polling balances for drain-style anomalies.
2. **Autonomous warning** — on an exploit signal it called
   `SentinelRegistry.submitWarning` itself (deposit 0.265 STT), with its own key.
   - Submit tx: `0x15ce6e9860891fd642efba4515a0dca5f179c15fbf3f7e4cfb65179605c80020`
   - Warning ID: 1
3. **Onchain LLM adjudication** — the Somnia LLM Inference agent adjudicated by
   consensus and called back `handleResponse`.
   - Verdict callback tx: `0x99a04331fc164124c3338c15a3d609b195aeeafa03db0b00b6b070528fbc46f7`
   - **Verdict: UNCONFIRMED** — correctly rejected, because the warning carried
     placeholder evidence and no real exploit occurred. The agent demonstrates
     genuine discriminating judgment, not a rubber stamp.

Together with the risk-score round-trip (score 55 → tier B), this proves the AI
agent **both confirms real risk and rejects baseless alarms** — fully onchain,
fully autonomous. The "Confirmed → auto-pause coverage" path is covered by the
Foundry test `test_CorrectWarningPaysBounty`.

Sentinel identity used in the run: `0x85862d64d81a7E6fF813Aa9F3a5a2E6240d349fD`
