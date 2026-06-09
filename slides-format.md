# Vigilant — Pitch Deck Format (slide-by-slide)

A complete, slide-by-slide plan for the Vigilant pitch. For each slide:
**Content** = what appears on the slide. **Speaker Notes** = what you say.
Target total length: ~3–4 minutes spoken. Build these in any tool (Canva,
Slides, Pitch, Figma).

---

## Slide 1 — Title

**Content**
- Project name: **Vigilant**
- Tagline: *Autonomous onchain exploit insurance*
- Sub-line: *Claims settled by onchain AI consensus — no human adjusters, no DAO votes, no off-chain oracles.*
- Footer: Built on the Somnia Agentic L1 · Somnia Agentathon 2026
- Visual: dark background, teal/amber accent, small Vigilant logo

**Speaker Notes**
> "Hi, I'm Ibrahim, and this is Vigilant — autonomous onchain insurance for smart
> contracts. The one thing to remember: with Vigilant, an AI agent decides
> insurance claims, onchain, in seconds — no human adjusters, no DAO votes."

---

## Slide 2 — The Problem

**Content**
- Heading: *Insurance is the last piece of DeFi still run by committees.*
- Three bullets:
  - Claims decided by human adjusters or DAO votes — slow, subjective, capturable
  - Off-chain oracles re-introduce trusted third parties DeFi tried to remove
  - By the time a payout clears, the capital is gone and the holder is wrecked
- Visual: a clock / "weeks" stat, or a drained-vault icon

**Speaker Notes**
> "When a protocol gets exploited today, victims wait weeks. Claims are decided by
> human adjusters or DAO votes — slow, subjective, and capturable. Off-chain
> oracles just re-introduce the trusted middlemen DeFi was supposed to remove.
> Insurance is the last piece of DeFi still run by committees and spreadsheets."

---

## Slide 3 — The Insight

**Content**
- Heading: *What if the adjuster were an onchain AI?*
- Key point: Somnia's Agentic L1 runs **deterministic LLM inference onchain**, finalized by validator consensus
- Implication: every validator reproduces the same result → the AI verdict is **trustless** and settles like any transaction
- Visual: subcommittee of validators all agreeing on one output

**Speaker Notes**
> "Here's the insight. Somnia's Agentic L1 runs deterministic LLM inference
> onchain — fixed seed, temperature zero — so every validator independently
> reproduces the exact same answer and reaches consensus on it. That makes an AI
> verdict trustless. So we let the AI be the claims adjuster."

---

## Slide 4 — What Vigilant Is

**Content**
- One sentence, large: *A fully onchain insurance market where coverage payouts and exploit warnings are decided in real time by consensus-validated AI agents, the moment an incident occurs.*
- Three small chips: Underwriters earn yield · Policyholders get cover · Sentinels earn bounties

**Speaker Notes**
> "Vigilant is a fully onchain insurance market. Underwriters supply capital and
> earn premiums, policyholders buy parametric exploit coverage, sentinels earn
> bounties for catching exploits — and AI agents decide every outcome in real time."

---

## Slide 5 — How It Works (the agent loop)

**Content**
- Diagram (left = off-chain agent, right = onchain):
  - Sentinel agent: discovers covered contracts → monitors balances → detects exploit signal → files warning
  - Onchain: SentinelRegistry → Somnia LLM Inference agent (Qwen3-30B, validator consensus) → Confirmed = auto-pause / real exploit = atomic payout
- Caption: **Two agents compose — one detects & reports, one adjudicates & acts.**

**Speaker Notes**
> "Two agents compose. Our off-chain Sentinel agent discovers covered contracts,
> watches them for drain-style anomalies, and files a warning onchain by itself.
> The onchain Somnia LLM agent then adjudicates that warning by validator
> consensus — and the protocol acts: it auto-pauses coverage, or on a real claim,
> pays out atomically. No human touches any of it."

---

## Slide 6 — Three Roles, One AI Brain

**Content**
- Table:
  | Role | Action | AI decision |
  |---|---|---|
  | Underwriter | deposits into A/B/C tranches | earns premium |
  | Policyholder | buys exploit coverage | risk score 0–100 → tier |
  | Sentinel | flags a live exploit | Confirmed / Unconfirmed |
  | Claim | files after an incident | Exploit → atomic payout |
- Caption: One LLM Inference agent serves all three — each contract sends its own prompt + answer set.

**Speaker Notes**
> "There are three roles, and one AI brain behind all of them. The same Somnia LLM
> agent scores contract risk for policyholders, adjudicates sentinel warnings, and
> classifies claims — each contract just sends its own prompt and constrained set
> of answers."

---

## Slide 7 — Proven Live on Testnet

**Content**
- Heading: *Not a mock. Real onchain AI verdicts.*
- Mini table:
  | Event | Result |
  |---|---|
  | Risk score request → LLM agent | accepted, 3-validator subcommittee |
  | Agent callback | **score 75/100 → Tier C** |
  | Autonomous Sentinel warning | filed by the agent itself |
  | LLM verdict | **Unconfirmed** — baseless alarm rejected |
- Pull-quote: *The AI confirms real risk AND rejects false alarms — a genuine decision-maker.*
- Footer: receipts in `deployments/AGENT_PROOF.md`

**Speaker Notes**
> "And this is live — not a mock. On testnet, a real risk request came back with a
> score of 75 out of 100, mapped to our high-risk tier. Then our agent
> autonomously filed an exploit warning, and the onchain AI returned 'Unconfirmed'
> — correctly rejecting a baseless alarm. That's the important part: the AI is a
> real decision-maker, not a rubber stamp. Every transaction is on the explorer."

---

## Slide 8 — Why the Autonomy Matters

**Content**
- Heading: *No human in the path.*
- 4 numbered steps: 1) Discovers covered contracts  2) Monitors for anomalies  3) Files the warning itself  4) AI adjudicates → protocol acts
- Big caption: **Detect → report → adjudicate → act. Fully autonomous.**

**Speaker Notes**
> "This is what makes Vigilant agent-first, not just agent-calling. The Sentinel
> discovers what to watch, monitors it, files the warning from its own wallet, and
> the onchain AI adjudicates and the protocol acts. Detect, report, adjudicate,
> act — with no human in the loop at any step."

---

## Slide 9 — Architecture

**Content**
- Component list (icons optional):
  - CoverageVault — 3-tranche vault, ERC-20 shares, loss waterfall C→B→A
  - PolicyManager — EIP-712 policies, AI risk scoring
  - IncidentResolver — claim engine, atomic payout, escalation
  - SentinelRegistry — reputation + bounties, AI warnings, auto-pause
  - PremiumDistributor — revenue split 70/20/10
  - Governor — timelocked parameters
  - AgentClient — reusable Somnia-agent base (circuit breaker, callbacks)
- Footer: replay protection, checks-effects-interactions, circuit breakers throughout

**Speaker Notes**
> "Under the hood: a tranched underwriting vault with a loss waterfall, an EIP-712
> policy manager, a claim resolver that pays out atomically, the sentinel registry,
> a premium distributor, and a timelocked governor — all built on a reusable
> agent-client base with circuit breakers and replay protection."

---

## Slide 10 — Tech & Status

**Content**
- Checklist:
  - ✅ 9 contracts deployed AND verified on Somnia testnet (chain 50312)
  - ✅ 26 Foundry tests passing
  - ✅ Autonomous Sentinel agent (TypeScript + viem)
  - ✅ React frontend (Vite + viem + MetaMask)
  - ✅ One-command end-to-end demo
- Footer: open source — github.com/aliveevie/vigilant

**Speaker Notes**
> "On delivery: nine contracts deployed and verified on Somnia testnet, 26 passing
> tests, the autonomous agent daemon, a working React frontend, and a one-command
> demo. It's all open source."

---

## Slide 11 — Judging Criteria Map

**Content**
- Table:
  | Criterion | Vigilant |
  |---|---|
  | Functionality | 9 verified contracts, 26 tests, live demo |
  | Agent-First Design | agents discover, invoke, and act autonomously |
  | Innovation | AI-settled insurance claims — a new primitive |
  | Autonomous Performance | detect → adjudicate → pay, no human |

**Speaker Notes**
> "Mapped straight to the judging criteria: it's functional and deployed; it's
> genuinely agent-first — agents discover, invoke, and act on their own; it's a
> novel primitive — AI-settled insurance; and it performs autonomously end to end."

*(Optional: skip reading this slide aloud if short on time — let it sit on screen.)*

---

## Slide 12 — LIVE DEMO

**Content**
- Big heading: **LIVE DEMO**
- Command on screen: `cd agent && npm run demo`
- Two labeled beats:
  - Act 1 — onchain AI risk scoring → score → tier
  - Act 2 — autonomous Sentinel warning → AI verdict
- Note: every step = a real tx on the Shannon explorer

**Speaker Notes (this is the demo — run it live or play the recording)**
> "Let me show you. One command runs the whole thing."
>
> *(Run `cd agent && npm run demo`. As the console prints, narrate:)*
>
> "Act one — the agent requests a real risk score. The request goes onchain… the
> Somnia LLM agent scores it by validator consensus… and here's the verdict — a
> risk score, mapped to a tier. I'll click this transaction link — there it is,
> live on the Shannon explorer.
>
> Act two — now the agent detects an exploit signal and **files a warning itself**,
> paying the deposit from its own wallet. The onchain AI adjudicates… and returns
> a verdict in seconds. No human filed anything; the agent and the chain did it all."
>
> *(If recorded: play the ~15s clip, then talk over it with the same narration.)*

**Backup if the live run is slow/fails**
> "Here are the receipts from an earlier run on the explorer —" *(show the
> AGENT_PROOF tx links)* "— the request, the AI callback with the score, the
> autonomous warning, and the verdict."

---

## Slide 13 — Market & Vision

**Content**
- Stats: DeFi TVL in the tens of billions · exploit losses $1B+/year
- Point: existing onchain cover still settles via human/DAO claims
- Vigilant: instant, objective, composable (vVIG tranche shares are ERC-20s)
- Roadmap: custom Somnia agents (Phase 2) → real exploit-feed detectors → mainnet → cover any contract on demand

**Speaker Notes**
> "The market is real — DeFi loses over a billion dollars a year to exploits, and
> existing onchain cover still settles through human or DAO claims. Vigilant makes
> cover instant, objective, and composable. Next we move to custom Somnia agents,
> richer exploit detectors, and mainnet."

---

## Slide 14 — Why Vigilant Wins / Close

**Content**
- Heading: *Autonomous onchain insurance for the agentic economy*
- Three bullets:
  - The only build where AI both underwrites AND adjudicates — autonomously, proven live
  - Production-grade: verified contracts, full tests, working agent + UI
  - A real product with a real market
- Links: github.com/aliveevie/vigilant · shannon-explorer.somnia.network
- Closing line: *Detect. Adjudicate. Pay. No humans required.*

**Speaker Notes**
> "To close: Vigilant is the only build where AI both underwrites and adjudicates
> insurance — autonomously, and proven live onchain. It's production-grade, it's a
> real product, and it's all open source. Detect, adjudicate, pay — no humans
> required. Thank you."

---

## Appendix — reference data to drop onto slides

- **Chain:** Somnia Shannon Testnet, id `50312`
- **Explorer:** https://shannon-explorer.somnia.network
- **LLM Inference agent id:** `12847293847561029384`
- **Key contracts:**
  - PolicyManager `0x7819f4929D80b5F98448b16c775F7c7dA1eC7221`
  - SentinelRegistry `0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357`
  - CoverageVault `0x6b0462e6af572Ed59c9B2e7dAd2a2C031C2b49FB`
- **Proof transactions:**
  - Risk request `0xeae3a210fc0f375461df02d1bc6fd145835d27f9d8ef7d2a4a796be58d1e6110`
  - Risk callback (score 55→B) `0x7a70a7cfc2b4add00c860bda9cff8069e2515e60be77ead9e5d59beaba639109`
  - Autonomous warning `0x15ce6e9860891fd642efba4515a0dca5f179c15fbf3f7e4cfb65179605c80020`
  - Warning verdict `0x99a04331fc164124c3338c15a3d609b195aeeafa03db0b00b6b070528fbc46f7`

## Timing guide (≈3:30 total)
- Slides 1–4: 0:45 (hook + problem + insight + what)
- Slides 5–6: 0:35 (how it works)
- Slides 7–8: 0:35 (live proof + autonomy)
- Slides 9–11: 0:30 (architecture + status + criteria)
- Slide 12: 0:45 (demo)
- Slides 13–14: 0:20 (vision + close)
