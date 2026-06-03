# Vigilant — Demo Video Script (target 2:45, hard cap 5:00)

**Thesis to land in the judge's mind:** *Vigilant is an autonomous agent network
that underwrites smart-contract risk and settles claims with onchain AI
consensus — no human adjusters, no DAO votes, no off-chain oracles.*

Record at 1080p. Keep the Shannon explorer open in a second tab to show real txs.
Speak to the four judging criteria explicitly: Functionality, Agent-First Design,
Innovation, Autonomous Performance.

---

## 0:00–0:20 — Hook (talking head or voiceover over the frontend)

> "When a DeFi protocol gets exploited, victims wait weeks for a claims process
> run by humans or DAO votes. Vigilant settles in seconds — and no human decides
> the outcome. An onchain AI agent does, by validator consensus, on Somnia."

Show the Vigilant dashboard (dark terminal UI), hover the three tranches.

## 0:20–0:50 — What it is (frontend, 30s)

- "Underwriters deposit STT into three risk tranches — A, B, C — and earn
  premiums." → show the Underwrite tab, the tranche cards.
- "Policyholders buy parametric exploit coverage." → Coverage tab.
- "Sentinels earn bounties for flagging live exploits." → Sentinel tab.
- "Every risk decision is made by Somnia's onchain LLM Inference agent —
  deterministic Qwen3-30B, running across a validator subcommittee."

## 0:50–1:35 — Proof #1: AI risk scoring, live onchain (the killer shot)

Terminal + explorer.

> "This isn't a mock. Watch a real contract get scored by the agent."

- Run the risk-score request (or replay the captured tx). Show:
  - Request tx on Shannon explorer:
    `0xeae3a210fc0f375461df02d1bc6fd145835d27f9d8ef7d2a4a796be58d1e6110`
  - "The platform assigns a 3-validator subcommittee and runs the model."
  - The callback tx:
    `0x7a70a7cfc2b4add00c860bda9cff8069e2515e60be77ead9e5d59beaba639109`
  - "The agent returned a risk score of **55 out of 100** — which the contract
    mapped to Tier B. That score came from onchain AI consensus."

## 1:35–2:25 — Proof #2: the autonomous Sentinel loop (Agent-First + Autonomy)

Run `npm run simulate` in the `agent/` folder. Narrate the console as it prints:

> "This is our off-chain Sentinel agent. No human is driving it."

- "It discovers covered contracts on its own, monitors their balances…"
- "…detects a drain signal, and **files an onchain warning by itself** —
  paying the deposit from its own wallet." → show the `submitWarning` tx.
- "The onchain LLM agent then adjudicates by consensus — and returns a verdict
  in seconds."
- "Here it correctly returned **Unconfirmed**, because this was a baseless
  signal. The AI isn't a rubber stamp — it rejects false alarms. When it
  confirms a real exploit, coverage auto-pauses and the claim pays out
  atomically — no human, no vote."

(Optional B-roll: the passing Foundry test `test_CorrectWarningPaysBounty`
scrolling, to show the confirmed→payout path is covered.)

## 2:25–2:40 — Architecture one-liner (Innovation)

Show a single slide / the architecture diagram:

> "Two agents compose: an off-chain watcher that detects and reports, and an
> onchain AI committee that adjudicates and acts. Tranched ERC-4626-style vault,
> EIP-712 policies, circuit breakers, atomic payouts — nine verified contracts,
> all live on Somnia testnet."

## 2:40–2:55 — Close

> "Vigilant — autonomous, onchain insurance for the agentic economy. Code and
> live addresses are in the repo. Built on Somnia."

Show: GitHub URL + Shannon explorer link to the verified PolicyManager.

---

## On-screen assets to have ready
- Frontend running at `localhost:8080` (MetaMask connected to Somnia 50312).
- `agent/` terminal ready to `npm run simulate`.
- Shannon explorer tabs preloaded:
  - PolicyManager (verified): https://shannon-explorer.somnia.network/address/0x7819f4929D80b5F98448b16c775F7c7dA1eC7221
  - Risk request tx, risk callback tx (above)
  - SentinelRegistry: https://shannon-explorer.somnia.network/address/0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357
- `deployments/AGENT_PROOF.md` open as the receipts cheat-sheet.

## Soundbites to reuse verbatim (they map to the rubric)
- Functionality: "Nine verified contracts, live on testnet, 26 passing tests."
- Agent-First: "Agents discover, invoke, and act on the system autonomously."
- Innovation: "Insurance claims settled by onchain AI consensus — a first."
- Autonomy: "Detect, report, adjudicate, pay — with no human in the loop."
