<div align="center">

# 🛡️ Vigilant

### Autonomous onchain exploit insurance, settled by AI consensus

**Claims and exploit warnings decided in real time by consensus-validated AI agents — no human adjusters, no DAO votes, no off-chain oracles.**

Built on the **Somnia Agentic L1** · Somnia Agentathon 2026

[![Live Demo](https://img.shields.io/badge/Live_Demo-vigilant--insure--protocol.vercel.app-2dd4bf?style=for-the-badge)](https://vigilant-insure-protocol.vercel.app)
[![Demo Video](https://img.shields.io/badge/Demo_Video-YouTube-ff0000?style=for-the-badge&logo=youtube&logoColor=white)](https://youtu.be/hWfCSEZBIF8)
[![Pitch Deck](https://img.shields.io/badge/Pitch_Deck-Slides-fbbf24?style=for-the-badge&logo=googleslides&logoColor=white)](https://docs.google.com/presentation/d/1CfEL1hSJlsg54C3FUCNAyduUotHp2Uy6nfPJQR74n4I/edit?usp=sharing)
[![Repo](https://img.shields.io/badge/Source-GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/aliveevie/vigilant)

</div>

---

## Links

| Resource | URL |
|---|---|
| 🌐 **Live dApp** | https://vigilant-insure-protocol.vercel.app |
| 🎥 **Demo video** | https://youtu.be/hWfCSEZBIF8 |
| 📊 **Presentation** | https://docs.google.com/presentation/d/1CfEL1hSJlsg54C3FUCNAyduUotHp2Uy6nfPJQR74n4I/edit?usp=sharing |
| 💻 **Source code** | https://github.com/aliveevie/vigilant |
| 🔎 **Block explorer** | https://shannon-explorer.somnia.network |

---

## Overview

Vigilant is a fully onchain insurance market for smart-contract risk. Underwriters
supply capital to risk-tranched vaults and earn premiums, policyholders buy
parametric exploit coverage, and sentinels earn bounties for flagging live
exploits. Every decision — risk scores, claim verdicts, and exploit warnings — is
made by **AI agents operating onchain**, finalized through validator consensus.

Two agents compose into an autonomous network:

1. An **off-chain Sentinel agent** that autonomously discovers covered contracts,
   monitors them for exploit signals, and files warnings onchain by itself.
2. The **onchain Somnia LLM Inference agent** (deterministic Qwen3-30B across a
   validator subcommittee) that adjudicates risk scores, claim verdicts, and
   warnings — and triggers payouts and coverage pauses atomically.

No human adjusters. No DAO claim votes. No off-chain oracle or attestation. Every
policy, premium, claim, agent invocation, verdict, and payout is a transaction on
Somnia, and the source of truth is contract storage and consensus-finalised agent
receipts.

---

## How it works

```
  Off-chain Sentinel agent                    Onchain (Somnia)
  ────────────────────────                    ────────────────
  discovers covered contracts  ──reads──►   PolicyManager
  monitors balances for drains
        │  exploit signal
        ▼
  files warning autonomously  ──────────►   SentinelRegistry
                                                 │ createRequest
                                                 ▼
                                            Somnia LLM Inference agent
                                            (Qwen3-30B · validator consensus)
                                                 │ handleResponse
                                                 ▼
                                            Confirmed ► auto-pause coverage
                                            Exploit   ► atomic payout
```

The same onchain agent path scores contracts for `PolicyManager` and adjudicates
claims for `IncidentResolver`, paying out atomically on an `Exploit` verdict.

### Three roles, one AI brain

| Role | Action | AI decision |
|---|---|---|
| **Underwriter** | deposits into A / B / C risk tranches | earns premium |
| **Policyholder** | buys parametric exploit coverage | risk **score 0–100 → tier** |
| **Sentinel** | flags a live exploit for a bounty | warning **Confirmed / Unconfirmed** |
| **Claim** | files after an incident | **Exploit → atomic payout** |

One Somnia LLM Inference agent serves all three — each contract sends its own
system prompt and constrained answer set.

---

## Deployed contracts — Somnia Testnet (chainId `50312`)

**Somnia Agents platform:** `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` · **LLM Inference agent ID:** `12847293847561029384`

| Contract | Address | Explorer |
|---|---|---|
| **Governor** | `0xF7B1ce04f92b39162Dfa528D3a29604d477ce6ec` | [view](https://shannon-explorer.somnia.network/address/0xF7B1ce04f92b39162Dfa528D3a29604d477ce6ec) |
| **CoverageVault** | `0x6b0462e6af572Ed59c9B2e7dAd2a2C031C2b49FB` | [view](https://shannon-explorer.somnia.network/address/0x6b0462e6af572Ed59c9B2e7dAd2a2C031C2b49FB) |
| **PolicyManager** | `0x7819f4929D80b5F98448b16c775F7c7dA1eC7221` | [view](https://shannon-explorer.somnia.network/address/0x7819f4929D80b5F98448b16c775F7c7dA1eC7221) |
| **IncidentResolver** | `0x790564795C471AD5FC20b1dac9fc837029eF9876` | [view](https://shannon-explorer.somnia.network/address/0x790564795C471AD5FC20b1dac9fc837029eF9876) |
| **SentinelRegistry** | `0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357` | [view](https://shannon-explorer.somnia.network/address/0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357) |
| **PremiumDistributor** | `0xAb5597214489bf4F3BB69419AFdF3fB21649A492` | [view](https://shannon-explorer.somnia.network/address/0xAb5597214489bf4F3BB69419AFdF3fB21649A492) |
| **VaultShare-A (vVIG-A)** | `0x9d2B2ff18f99D3bA2A06a904a572a42BE1c54BEe` | [view](https://shannon-explorer.somnia.network/address/0x9d2B2ff18f99D3bA2A06a904a572a42BE1c54BEe) |
| **VaultShare-B (vVIG-B)** | `0xbD218c55326967a54c58e823AED1d59a4E47A101` | [view](https://shannon-explorer.somnia.network/address/0xbD218c55326967a54c58e823AED1d59a4E47A101) |
| **VaultShare-C (vVIG-C)** | `0x269794Bb84e22BDDd8B8cbef004996166D699598` | [view](https://shannon-explorer.somnia.network/address/0x269794Bb84e22BDDd8B8cbef004996166D699598) |

All nine contracts are verified on the Shannon explorer.

### Live agent proof (real testnet transactions)

| Event | Transaction |
|---|---|
| Risk-score request → LLM agent | [`0xeae3a2…6110`](https://shannon-explorer.somnia.network/tx/0xeae3a210fc0f375461df02d1bc6fd145835d27f9d8ef7d2a4a796be58d1e6110) |
| Agent callback (**score 55 → Tier B**) | [`0x7a70a7…9109`](https://shannon-explorer.somnia.network/tx/0x7a70a7cfc2b4add00c860bda9cff8069e2515e60be77ead9e5d59beaba639109) |
| Autonomous Sentinel warning | [`0x15ce6e…0020`](https://shannon-explorer.somnia.network/tx/0x15ce6e9860891fd642efba4515a0dca5f179c15fbf3f7e4cfb65179605c80020) |
| LLM verdict callback (Unconfirmed) | [`0x99a043…46f7`](https://shannon-explorer.somnia.network/tx/0x99a04331fc164124c3338c15a3d609b195aeeafa03db0b00b6b070528fbc46f7) |

Full receipts: [`deployments/AGENT_PROOF.md`](./deployments/AGENT_PROOF.md).

---

## Agents

Vigilant invokes the **Somnia LLM Inference base agent** (id `12847293847561029384`,
deterministic Qwen3-30B) through the documented `IAgentRequester` interface. Each
consuming contract embeds its own system prompt and constrained answer set, so one
base agent serves three roles:

| Consumer | Method | Output the contract acts on |
|---|---|---|
| `PolicyManager` | `inferNumber(prompt, system, 0, 100, …)` | risk score 0–100 → tier A/B/C |
| `IncidentResolver` | `inferString(…, ["Exploit","NotExploit","Inconclusive"])` | claim verdict → atomic payout on `Exploit` |
| `SentinelRegistry` | `inferString(…, ["Confirmed","Unconfirmed","Inconclusive"])` | warning verdict → auto-pause on `Confirmed` |

All system prompts are governor-tunable without redeploy. Agent IDs are
governor-settable and default to the LLM Inference base agent on testnet.

---

## Contracts

- **CoverageVault** — three-tranche underwriting vault holding the native asset.
  Each tranche issues a transferable ERC-20 share (`vVIG-A/B/C`). Applies a loss
  waterfall **C → B → A** on payout; multipliers (bps): A = 6,000, B = 10,000, C = 14,000.
- **PolicyManager** — issues EIP-712 policies, requests AI risk scores, caches the
  `(score, tier, expiry)` per covered contract, and asserts the signed tier matches
  the cached agent verdict on issuance.
- **IncidentResolver** — claim engine; pays `coverageAmount` from the vault to the
  policyholder atomically on an `Exploit` verdict, with a larger-committee escalation path.
- **SentinelRegistry** — reputation + bounty engine; adjudicates exploit warnings,
  pays `deposit + bounty` on `Confirmed`, raises the sentinel's score, and auto-pauses coverage.
- **PremiumDistributor** — pull-payment revenue router: 70% vault / 20% sentinel reserve / 10% treasury.
- **Governor** — timelock + admin passthrough for tunable parameters and module wiring.
- **AgentClient** — reusable base for any contract that invokes a Somnia agent
  (callback wiring, deposit math, failure-driven circuit breaker).

Replay protection, checks-effects-interactions, and circuit breakers throughout.

---

## Repository structure

```
.
├── architecture.md                  — full protocol design doc
├── contracts/                       — Foundry project (9 contracts, 26 tests)
│   ├── src/
│   │   ├── interfaces/              — IAgentRequester, IAgentResponder, IAgents (ILLMInference)
│   │   ├── agents/AgentClient.sol   — base agent invoker
│   │   ├── vault/                   — CoverageVault, VaultShare
│   │   ├── PolicyManager.sol  IncidentResolver.sol  SentinelRegistry.sol
│   │   ├── PremiumDistributor.sol   Governor.sol
│   │   └── libraries/               — PolicyLib (EIP-712), Types, Errors, Events
│   ├── test/                        — 26 passing tests
│   └── script/Deploy.s.sol
├── agent/                           — autonomous off-chain Sentinel daemon (TypeScript + viem)
├── vigilant-insure-protocol/        — frontend (Vite + React + viem, MetaMask)
├── deployments/
│   ├── somnia-testnet.json          — live addresses + agent IDs
│   └── AGENT_PROOF.md               — real testnet agent round-trip receipts
├── slides-format.md                 — pitch deck (slide-by-slide + speaker notes)
└── DEMO_SCRIPT.md                   — demo video run-of-show
```

---

## Quick start

```bash
git clone https://github.com/aliveevie/vigilant.git
cd vigilant
```

**Contracts**
```bash
cd contracts
forge build && forge test          # 26 tests
```

**Autonomous Sentinel agent**
```bash
cd agent
npm install
cp .env.example .env               # set SENTINEL_PRIVATE_KEY (funded hot wallet)
npm run demo                       # full end-to-end: risk score + autonomous warning
```

**Frontend**
```bash
cd vigilant-insure-protocol
npm install                        # use npm (arch-correct native deps)
npm run dev                        # http://localhost:8080
```

### Somnia notes
- Deploys: `--gas-estimate-multiplier 3000 --legacy` (Somnia charges ~3,125 gas/byte of bytecode).
- Agent calls carry a ~600-byte prompt → set `--gas-limit 5000000` on
  `requestRiskScore`, `fileClaim`, `submitWarning`, or the tx reverts.
- Canonical RPC: `https://api.infra.testnet.somnia.network/`.

---

## Tech stack

- **Contracts:** Solidity 0.8.26, Foundry, OpenZeppelin
- **Agent:** TypeScript, viem, Node
- **Frontend:** Vite, React, TypeScript, viem + wagmi, MetaMask
- **Chain:** Somnia Shannon Testnet (chainId 50312), Somnia Agents (onchain LLM inference)

---

<div align="center">

**Vigilant** · Detect. Adjudicate. Pay. — autonomous onchain insurance for the agentic economy.

[Live dApp](https://vigilant-insure-protocol.vercel.app) · [Demo](https://youtu.be/hWfCSEZBIF8) · [Slides](https://docs.google.com/presentation/d/1CfEL1hSJlsg54C3FUCNAyduUotHp2Uy6nfPJQR74n4I/edit?usp=sharing) · [Explorer](https://shannon-explorer.somnia.network)

</div>
