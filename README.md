# Vigilant

**An autonomous agent network for onchain exploit insurance — built on the Somnia Agentic L1.**

Vigilant underwrites smart-contract risk and settles claims through **onchain AI
consensus**, with no human in the loop. Two agents compose:

1. An **off-chain Sentinel agent** that autonomously discovers covered contracts,
   monitors them for exploit signals, and files warnings onchain by itself.
2. The **onchain Somnia LLM Inference agent** (deterministic Qwen3-30B across a
   validator subcommittee) that adjudicates risk scores, claim verdicts, and
   warnings by consensus — and triggers payouts and coverage pauses atomically.

No human adjusters. No DAO claim votes. No off-chain oracle or attestation. Every
policy, premium, claim, agent invocation, verdict, and payout is a transaction on
Somnia; the source of truth is contract storage and consensus-finalised agent
receipts.

### Repositories
- **Protocol + autonomous agent (this repo):** <https://github.com/aliveevie/vigilant>
  - Solidity contracts → [`contracts/`](https://github.com/aliveevie/vigilant/tree/main/contracts)
  - Autonomous Sentinel agent → [`agent/`](https://github.com/aliveevie/vigilant/tree/main/agent)
  - Live agent proof → [`deployments/AGENT_PROOF.md`](https://github.com/aliveevie/vigilant/blob/main/deployments/AGENT_PROOF.md)
- **Frontend (Vite + React + viem, MetaMask):** <https://github.com/aliveevie/vigilant-insure-protocol>

> **Proven live on testnet.** A real risk-score request returned an AI score of
> **55/100 → Tier B** by consensus, and the autonomous Sentinel filed a warning
> that the LLM agent adjudicated in ~4 seconds. Receipts:
> [`deployments/AGENT_PROOF.md`](./deployments/AGENT_PROOF.md).

See [`architecture.md`](./architecture.md) for the full protocol design.

---

## How it maps to the judging criteria

- **Functionality** — 9 contracts deployed and **verified** on Somnia testnet,
  26 passing Foundry tests, a working React frontend, and a runnable agent daemon.
- **Agent-First Design** — agents *discover, invoke, and act on* the system
  autonomously. The Sentinel finds covered contracts and files warnings on its
  own; the onchain LLM agent adjudicates and the protocol acts on the verdict.
- **Innovation** — insurance claims settled by onchain AI consensus is a novel
  primitive: deterministic inference replaces human adjusters and DAO votes.
- **Autonomous Performance** — detect → report → adjudicate → pay, end to end,
  with no human. The AI also *rejects* baseless warnings (proven live), so it is
  a real decision-maker, not a rubber stamp.

---

## The agent loop (no human in the path)

```
  off-chain Sentinel agent                    onchain (Somnia)
  ────────────────────────                    ────────────────
  discover covered contracts  ───reads───►   PolicyManager events
  monitor balances for drains
        │  exploit signal
        ▼
  submitWarning() ───────────────────────►   SentinelRegistry
                                                   │ createRequest
                                                   ▼
                                              Somnia LLM Inference agent
                                              (Qwen3-30B, validator consensus)
                                                   │ handleResponse
                                                   ▼
                                              Confirmed ► auto-pause coverage
                                              Unconfirmed ► forfeit deposit
```

The same onchain agent path scores contracts for `PolicyManager` and adjudicates
claims for `IncidentResolver`, paying out atomically on an `Exploit` verdict.

---

## Deployed contracts — Somnia Testnet (chainId `50312`)

Explorer: <https://shannon-explorer.somnia.network/> · RPC: `https://api.infra.testnet.somnia.network/`
Somnia Agents platform: `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` · LLM Inference agent ID: `12847293847561029384`

| Contract | Address | Status |
|---|---|---|
| **Governor** | [`0xF7B1ce04f92b39162Dfa528D3a29604d477ce6ec`](https://shannon-explorer.somnia.network/address/0xF7B1ce04f92b39162Dfa528D3a29604d477ce6ec) | ✓ verified |
| **CoverageVault** | [`0x6b0462e6af572Ed59c9B2e7dAd2a2C031C2b49FB`](https://shannon-explorer.somnia.network/address/0x6b0462e6af572Ed59c9B2e7dAd2a2C031C2b49FB) | ✓ verified |
| **PolicyManager** | [`0x7819f4929D80b5F98448b16c775F7c7dA1eC7221`](https://shannon-explorer.somnia.network/address/0x7819f4929D80b5F98448b16c775F7c7dA1eC7221) | ✓ verified |
| **IncidentResolver** | [`0x790564795C471AD5FC20b1dac9fc837029eF9876`](https://shannon-explorer.somnia.network/address/0x790564795C471AD5FC20b1dac9fc837029eF9876) | ✓ verified |
| **SentinelRegistry** | [`0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357`](https://shannon-explorer.somnia.network/address/0x810fe610A7ad36810d68BF9BA3E1B7c9c22D8357) | ✓ verified |
| **PremiumDistributor** | [`0xAb5597214489bf4F3BB69419AFdF3fB21649A492`](https://shannon-explorer.somnia.network/address/0xAb5597214489bf4F3BB69419AFdF3fB21649A492) | ✓ verified |
| **VaultShare-A (vVIG-A)** | [`0x9d2B2ff18f99D3bA2A06a904a572a42BE1c54BEe`](https://shannon-explorer.somnia.network/address/0x9d2B2ff18f99D3bA2A06a904a572a42BE1c54BEe) | ✓ verified |
| **VaultShare-B (vVIG-B)** | [`0xbD218c55326967a54c58e823AED1d59a4E47A101`](https://shannon-explorer.somnia.network/address/0xbD218c55326967a54c58e823AED1d59a4E47A101) | ✓ verified |
| **VaultShare-C (vVIG-C)** | [`0x269794Bb84e22BDDd8B8cbef004996166D699598`](https://shannon-explorer.somnia.network/address/0x269794Bb84e22BDDd8B8cbef004996166D699598) | ✓ verified |

### Live agent proof (real testnet transactions)

| Event | Tx |
|---|---|
| Risk-score request → LLM agent | [`0xeae3a2…6110`](https://shannon-explorer.somnia.network/tx/0xeae3a210fc0f375461df02d1bc6fd145835d27f9d8ef7d2a4a796be58d1e6110) |
| Agent callback (score **55** → Tier B) | [`0x7a70a7…9109`](https://shannon-explorer.somnia.network/tx/0x7a70a7cfc2b4add00c860bda9cff8069e2515e60be77ead9e5d59beaba639109) |
| Autonomous Sentinel warning | [`0x15ce6e…0020`](https://shannon-explorer.somnia.network/tx/0x15ce6e9860891fd642efba4515a0dca5f179c15fbf3f7e4cfb65179605c80020) |
| LLM verdict callback (Unconfirmed) | [`0x99a043…46f7`](https://shannon-explorer.somnia.network/tx/0x99a04331fc164124c3338c15a3d609b195aeeafa03db0b00b6b070528fbc46f7) |

---

## Agents

The protocol invokes the **Somnia LLM Inference base agent**
(id `12847293847561029384`, deterministic Qwen3-30B) through the documented
`IAgentRequester` interface. Each consuming contract embeds its own system prompt
and constrained answer set, so one base agent serves three roles:

| Consumer | Method | Output the contract acts on |
|---|---|---|
| `PolicyManager` | `inferNumber(prompt, system, 0, 100, …)` | risk score 0–100 → tier A/B/C |
| `IncidentResolver` | `inferString(…, ["Exploit","NotExploit","Inconclusive"])` | claim verdict → atomic payout on `Exploit` |
| `SentinelRegistry` | `inferString(…, ["Confirmed","Unconfirmed","Inconclusive"])` | warning verdict → auto-pause on `Confirmed` |

All three system prompts are governor-tunable without redeploy. Agent IDs are
governor-settable and default to the LLM Inference base agent on testnet.

---

## Contracts

### `Governor`
Timelock + admin passthrough. Holds the privilege to tune parameters (system
prompts, per-agent budgets, circuit-breaker thresholds, tranche multipliers,
premium splits) and owns the wiring between modules. Cannot touch issued policies,
pending claims, or locked capital.

### `CoverageVault`
Three-tranche underwriting vault holding the native asset (STT on testnet). Each
tranche issues a transferable ERC-20 share (`vVIG-A/B/C`).
- `deposit(tier)` / `withdraw(tier, shares)` — pro-rata mint/burn.
- `lock` / `unlock` — gated to PolicyManager / IncidentResolver.
- `absorb(amount, recipient)` — IncidentResolver only; applies the loss waterfall
  **C → B → A** and pays the policyholder atomically with settlement.
- `receivePremium()` — splits premium across tranches (weighted by multiplier ×
  capital) and the reserve. Multipliers (bps): A = 6,000, B = 10,000, C = 14,000.

### `PolicyManager`
Issues, holds, and retires policies; verifies an EIP-712 `RiskPolicy` on issuance.
- `requestRiskScore(coveredContract)` — invokes the LLM agent; caches
  `(score, tier, expiry)` for `tierCacheTTLBlocks` (1,000).
- `issue(RiskPolicy, signature)` — verifies the EIP-712 envelope, asserts the
  signed tier matches the cached agent verdict, enforces a strictly-increasing
  nonce, locks tranche capital, forwards premium.
- `expire(policyId)` / `markPaidOut(...)` (IncidentResolver only).
- Circuit breaker trips after 5 consecutive failed agent responses.

EIP-712 domain: `name="Vigilant"`, `version="1"`, `verifyingContract=PolicyManager`.

### `IncidentResolver`
Claim engine. `fileClaim(policyId, exploitTx, incidentBlock)` invokes the LLM
agent; on an `Exploit` verdict it pays `coverageAmount` from the vault to the
policyholder via `vault.absorb` and marks the policy `PaidOut`. `escalate(claimId)`
re-routes via `createAdvancedRequest` with a 2× subcommittee and 75% threshold.

### `SentinelRegistry`
Reputation + bounty engine. `submitWarning(coveredContract, evidenceTx,
incidentBlock)` bonds a deposit and asks the LLM agent to adjudicate; a
`Confirmed` verdict pays `deposit + bounty`, raises the sentinel's score, and
auto-pauses new coverage for the contract. Otherwise the deposit is forfeit.
`getScore` / `getHistory` expose a public reputation surface.

### `PremiumDistributor`
Pull-payment revenue router: 70% vault / 20% sentinel reserve / 10% treasury,
governor-tunable as long as the bps sum to 10,000.

---

## Repo layout

```
.
├── architecture.md                  — full protocol design doc
├── contracts/                       — Foundry project (9 contracts, 26 tests)
│   ├── src/
│   │   ├── interfaces/              — IAgentRequester, IAgentResponder, IAgents (ILLMInference)
│   │   ├── agents/AgentClient.sol   — base agent invoker (callback wiring, circuit breaker)
│   │   ├── vault/                   — CoverageVault, VaultShare
│   │   ├── PolicyManager.sol  IncidentResolver.sol  SentinelRegistry.sol
│   │   ├── PremiumDistributor.sol   Governor.sol
│   │   └── ...
│   ├── test/                        — 26 passing tests
│   └── script/Deploy.s.sol
├── agent/                           — autonomous off-chain Sentinel daemon (TypeScript + viem)
├── deployments/
│   ├── somnia-testnet.json          — live addresses + agent IDs
│   └── AGENT_PROOF.md               — real testnet agent round-trip receipts
└── DEMO_SCRIPT.md                   — demo video run-of-show
```

The autonomous Sentinel agent lives in [`agent/`](https://github.com/aliveevie/vigilant/tree/main/agent).
The frontend (Vite + React + viem, MetaMask) lives in its own repo:
[`vigilant-insure-protocol`](https://github.com/aliveevie/vigilant-insure-protocol),
pre-wired with these addresses and ABIs.

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
npm run simulate                   # demo the full autonomous detect→report→adjudicate flow
```

**Frontend** (separate repo)
```bash
npm install                        # use npm, not bun (arch-correct native deps)
npm run dev                        # http://localhost:8080
```

### Somnia gas notes
- Deploys: `--gas-estimate-multiplier 3000 --legacy` (Somnia charges ~3,125 gas/byte of bytecode).
- Agent calls carry a ~600-byte prompt → set `--gas-limit 5000000` on
  `requestRiskScore`, `fileClaim`, `submitWarning`, or the tx reverts.
- Use the canonical RPC `https://api.infra.testnet.somnia.network/`.
