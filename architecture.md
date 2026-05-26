# Vigilant

**Agentic L1 insurance protocol — consensus-resolved coverage for onchain assets**

---

## Overview

Vigilant is an onchain insurance protocol that underwrites coverage for smart-contract risk and settles claims through consensus-validated AI inference rather than human adjusters or off-chain attestors. Underwriters supply capital to tiered coverage vaults, policyholders purchase parametric policies against specific covered contracts, and the protocol resolves claims by invoking Somnia Agents that fetch live forensic data, classify incidents with deterministic LLMs, and have validators rerun the verdict as part of consensus.

The protocol is fully onchain. There is no centralised oracle, no DAO claim vote, no off-chain attestation, and no off-chain database. Every policy, premium, claim, agent invocation, and payout is a transaction on Somnia, and the source of truth is contract storage and consensus-finalised agent receipts.

---

## Protocol design

### Coverage model

Vigilant issues **parametric exploit policies** against specific covered contract addresses. A policy specifies:

- a `coveredContract` address
- a `coverageAmount` denominated in the protocol's settlement asset (SOMI on mainnet, STT on testnet)
- a `riskTier` assigned at issuance by an AI risk-scoring agent
- a `premium` derived from the tier and the coverage amount
- a `policyTerm` measured in blocks
- an EIP-712 signed `RiskPolicy` envelope binding the above to the policyholder's address

Policies do not require human inspection of the covered contract. Risk tiering is performed by the **RiskScoringAgent**, which combines onchain reads of the target's bytecode and recent activity with an LLM-inference call that classifies the contract's exposure surface. The tier is finalised before the policy is minted, and is sealed into the policy hash, so the premium cannot be retroactively repriced.

### Claim resolution

Claims are filed by referencing a transaction hash alleged to be an exploit of the covered contract. The **IncidentResolver** contract invokes the **ExploitClassifierAgent**, which performs three operations consensus-validated on Somnia:

1. A JSON API fetch of the alleged exploit transaction trace and receipts from an archive endpoint.
2. A JSON API fetch of the covered contract's storage delta across the incident block range.
3. A deterministic LLM inference over the assembled forensic payload, returning a verdict tuple `(classification, confidence, rationaleHash)`.

The agent returns a single ABI-encoded result. Validators in the elected subcommittee independently rerun all three operations; consensus is reached only if a majority produce identical result bytes, which the determinism of Somnia's fixed-seed LLM inference guarantees for a given input. On `ResponseStatus.Success` with `classification = Exploit` above a configured confidence floor, payout is automatic and atomic in the same block as the callback.

If consensus returns `Legitimate`, `Inconclusive`, `Failed`, or `TimedOut`, the policy remains active. Inconclusive verdicts route to a second-opinion path that increases subcommittee size and threshold; this is invoked via `createAdvancedRequest`.

### Capital model

Underwriters deposit settlement assets into the **CoverageVault**. Capital is tranched by `riskTier`:

- **Tier A** — highest-rated covered contracts, lowest premium yield, paid out last in a loss event.
- **Tier B** — mid-tier, balanced yield, paid out second.
- **Tier C** — newly deployed or unaudited contracts, highest premium yield, first-loss tranche.

Premiums flow into a streaming distribution module that pays each tranche proportionally to its capital share, weighted by tranche multiplier. A bounded **lossWaterfall** drains tranches in reverse order on each claim payout.

Underwriters cannot withdraw capital that backs an unexpired policy. Tranche shares are represented by ERC-4626 vault tokens, which are transferable and composable with the rest of the Somnia DeFi ecosystem.

### Sentinel layer

The **SentinelRegistry** records reputation for two participant classes:

- **Underwriter sentinels** — addresses whose capital has historically backed policies that did not pay out. Score increases with covered-block-volume and decreases with realised losses.
- **Watcher sentinels** — external addresses that submit advance warnings against covered contracts. A warning is a signed claim that a covered contract has been compromised, accompanied by a deposit. The registry invokes the ExploitClassifierAgent on the submitted evidence; correct warnings are paid a bounty from the protocol fee stream and the sentinel's score rises. Incorrect warnings forfeit the deposit.

Reputation is stored as a fixed-point score plus the supporting event history, and is queryable by other protocols as an onchain risk signal.

---

## Contract architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                      Vigilant Protocol                            │
│                                                                   │
│   ┌──────────────────┐         ┌──────────────────────────────┐   │
│   │  PolicyManager   │ ─────►  │   CoverageVault              │   │
│   │  (EIP-712)       │ premium │   (ERC-4626 tranched)        │   │
│   └────────┬─────────┘         └──────────────┬───────────────┘   │
│            │ issue                            │ payout            │
│            ▼                                  ▼                   │
│   ┌──────────────────┐         ┌──────────────────────────────┐   │
│   │  RiskScoring     │         │   IncidentResolver           │   │
│   │  Agent client    │         │   Agent client               │   │
│   └────────┬─────────┘         └──────────────┬───────────────┘   │
│            │ createRequest                    │ createRequest     │
│            ▼                                  ▼                   │
│   ┌───────────────────────────────────────────────────────────┐   │
│   │           SomniaAgents platform (IAgentRequester)         │   │
│   │           0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776       │   │
│   └───────────────────────────────────────────────────────────┘   │
│                                                                   │
│   ┌──────────────────┐         ┌──────────────────────────────┐   │
│   │  SentinelRegistry│ ◄─────  │   PremiumDistributor         │   │
│   └──────────────────┘  reward └──────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

### `PolicyManager`

Issues, holds, and retires policies. Maintains the mapping from `policyId` to the EIP-712 hash of the `RiskPolicy` struct. Verifies signatures on issuance, settles premiums into the `CoverageVault`, and is the only contract authorised to mark a policy as paid out.

Key state:

- `mapping(uint256 => Policy) policies`
- `mapping(address => uint256[]) policiesByHolder`
- `mapping(address => RiskTier) coveredContractTier`

Key functions:

- `issue(RiskPolicy calldata p, bytes calldata signature) external payable returns (uint256 policyId)`
- `requestRiskScore(address coveredContract) external payable returns (uint256 requestId)`  *(invokes RiskScoringAgent)*
- `handleRiskScoreResponse(...) external`  *(IAgentRequester callback)*
- `expire(uint256 policyId) external`

### `CoverageVault`

ERC-4626 vault per tranche (A, B, C). Holds the protocol's underwriting capital. Exposes deposit, withdraw, and convert functions inherited from ERC-4626. Adds a `lock(amount)` mechanism that prevents withdrawal of capital actively backing policies, and an `absorb(amount)` function callable only by the `IncidentResolver` during payout.

Withdrawals from a locked vault revert. Locks are released when policies expire without claim.

### `IncidentResolver`

The protocol's claim engine. Receives claim filings from policyholders, invokes the ExploitClassifierAgent through `IAgentRequester.createRequest`, and triggers payout from the `CoverageVault` on a `Success` consensus with an `Exploit` verdict above the confidence floor.

Key state:

- `mapping(uint256 => Claim) claims`
- `mapping(uint256 => uint256) requestToClaim`
- `uint256 public confidenceFloor`

Key functions:

- `fileClaim(uint256 policyId, bytes32 exploitTx, uint256 incidentBlock) external payable returns (uint256 claimId)`
- `handleResponse(uint256 requestId, Response[] memory responses, ResponseStatus status, Request memory details) external`
- `escalate(uint256 claimId) external payable`  *(routes to `createAdvancedRequest` with increased subcommittee size)*

The callback verifies `msg.sender == address(platform)`, looks up the originating claim, decodes the result, and on `Exploit` calls `CoverageVault.absorb` followed by transfer to the policyholder.

### `SentinelRegistry`

Maintains reputation for underwriters and watchers. Exposes:

- `submitWarning(address coveredContract, bytes32 evidenceTx) external payable returns (uint256 warningId)`
- `handleResponse(...)`  *(callback for ExploitClassifierAgent verifying the warning)*
- `getScore(address sentinel) external view returns (uint256)`
- `getHistory(address sentinel) external view returns (Event[] memory)`

### `PremiumDistributor`

Streams premium income to the three vault tranches according to tranche multipliers, and routes a configurable share to watcher bounties and protocol reserves. Implements a pull-payment pattern so distribution gas is bounded per call.

---

## Agent integration

Vigilant interacts with three Somnia Agents via the platform contract at `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` (testnet, chain ID `50312`) and the mainnet equivalent at `0x5E5205CF39E766118C01636bED000A54D93163E6` (chain ID `5031`). All invocations are placed through the standard `IAgentRequester` interface; concrete agent IDs are resolved from `https://agents.somnia.network` and pinned as immutable constants per deployment.

### RiskScoringAgent

**Purpose.** Given a target contract address and chain context, produce a numeric risk score and a categorical tier (A / B / C) via deterministic LLM inference over onchain features.

**Invocation.** `PolicyManager.requestRiskScore` calls `createRequest` with a payload encoded against the agent's `scoreContract(address target, string contextUri)` selector. The payload includes the covered contract address and a URI pointing to its verified source on the Somnia explorer.

**Response shape.** ABI-encoded `(uint16 score, uint8 tier, bytes32 rationaleHash)`. The rationale itself is stored offchain and referenced by hash; the score and tier are sealed into the policy.

**Consensus.** `Majority` with default subcommittee size, sufficient because LLM inference is deterministic.

### ExploitClassifierAgent

**Purpose.** Given a claim payload, return a verdict on whether the referenced transaction exploited the covered contract.

**Invocation.** `IncidentResolver.fileClaim` calls `createRequest` with a payload encoded against the agent's `classifyIncident(address coveredContract, bytes32 exploitTx, uint256 incidentBlock)` selector.

**Agent internal behaviour** (executed by validators):

1. JSON API fetch of `eth_getTransactionByHash` and `eth_getTransactionReceipt` for the alleged exploit tx.
2. JSON API fetch of `debug_traceTransaction` output, or its functional equivalent on Somnia.
3. JSON API fetch of the covered contract's storage layout via the explorer ABI endpoint.
4. Deterministic LLM inference over the assembled context, returning a verdict tuple.

**Response shape.** ABI-encoded `(uint8 classification, uint8 confidence, bytes32 rationaleHash)` where `classification ∈ {Legitimate=0, Exploit=1, Inconclusive=2}` and `confidence` is `0..100`.

**Consensus.** `Majority` on the initial call. Escalations from `IncidentResolver.escalate` use `createAdvancedRequest` with a larger subcommittee and a higher threshold.

### WarningVerifierAgent

**Purpose.** Verify a sentinel's submitted warning before reputation and bounty are awarded. Functionally a wrapper around the ExploitClassifierAgent with a stricter confidence floor and a shorter timeout, since warnings are time-sensitive.

---

## Data model

### `RiskPolicy` (EIP-712)

```solidity
struct RiskPolicy {
    address policyholder;
    address coveredContract;
    uint256 coverageAmount;
    uint8   riskTier;          // 0=A, 1=B, 2=C
    uint256 premium;
    uint64  startBlock;
    uint64  endBlock;
    uint256 nonce;
}
```

Domain separator: `Vigilant`, version `1`, chain ID, verifying contract `PolicyManager`.

### `Policy` (storage)

```solidity
struct Policy {
    bytes32 policyHash;        // keccak256 of RiskPolicy
    PolicyState state;         // Active | Expired | PaidOut
    uint256 paidOutAmount;
}
```

### `Claim` (storage)

```solidity
struct Claim {
    uint256 policyId;
    bytes32 exploitTx;
    uint256 incidentBlock;
    address filer;
    ClaimState state;          // Pending | Confirmed | Rejected | Escalated
    uint256 platformRequestId;
}
```

### `SentinelEvent` (storage)

```solidity
struct SentinelEvent {
    SentinelKind kind;         // UnderwriterClean | UnderwriterLoss | WatcherCorrect | WatcherIncorrect
    uint256 blockNumber;
    int256 scoreDelta;
}
```

---

## Lifecycle flows

### Policy issuance

1. Policyholder calls `PolicyManager.requestRiskScore(coveredContract)`, depositing the platform-required amount returned by `getRequestDeposit()` plus the agent reward floor.
2. SomniaAgents elects a subcommittee, validators rerun the RiskScoringAgent, and consensus is reached.
3. The platform calls back into `PolicyManager.handleRiskScoreResponse`; the contract caches the tier against `coveredContract`.
4. Policyholder signs a `RiskPolicy` envelope offchain and submits it with the premium to `PolicyManager.issue`.
5. `PolicyManager` verifies the signature, asserts the tier in the envelope matches the cached tier, locks the corresponding tranche capital in `CoverageVault`, and mints the policy.

### Claim payout

1. Policyholder calls `IncidentResolver.fileClaim(policyId, exploitTx, incidentBlock)` with the platform deposit.
2. `IncidentResolver` invokes the ExploitClassifierAgent through `createRequest`.
3. Validators independently fetch the forensic payload, run the deterministic classifier, and submit responses.
4. On consensus, the platform calls `IncidentResolver.handleResponse`.
5. If `status == Success` and the decoded `classification == Exploit` and `confidence >= confidenceFloor`, the resolver calls `CoverageVault.absorb(coverageAmount)` and transfers settlement to the policyholder atomically.
6. Otherwise the claim is marked `Rejected` or `Escalated`. Escalation re-invokes the agent via `createAdvancedRequest` with stricter parameters.

### Sentinel warning

1. Watcher calls `SentinelRegistry.submitWarning(coveredContract, evidenceTx)` with a bonded deposit.
2. The registry invokes the WarningVerifierAgent.
3. On a confirmed `Exploit` verdict, the bounty is paid from the protocol reserve, the watcher's score increases, and the registry triggers a precautionary pause of new policy issuance against `coveredContract` until governance reviews.
4. On a `Legitimate` or `Inconclusive` verdict, the watcher's deposit is forfeited to the protocol reserve.

---

## Gas and deposit sizing

Each agent invocation requires a deposit sized as

```
deposit = platform.getRequestDeposit() + perAgentBudget × subcommitteeSize
```

where `getRequestDeposit()` returns the operations reserve floor and `perAgentBudget` is the configured agent reward floor. For Vigilant's three agents, per-agent budgets are stored as governance-tunable constants on each invoking contract:

- `RISK_SCORE_COST_PER_AGENT` — used by `PolicyManager`.
- `EXPLOIT_CLASSIFY_COST_PER_AGENT` — used by `IncidentResolver` and `SentinelRegistry`.
- `WARNING_VERIFY_COST_PER_AGENT` — used by `SentinelRegistry`.

All three are set high enough that runners reliably accept the request. Excess deposit is rebated to the invoking contract at finalisation; each invoker implements `receive() external payable` to accept rebates and routes them back to the protocol reserve.

---

## Security model

### Trust assumptions

- **Somnia consensus** is trusted to correctly elect subcommittees, refuse forged responses, and only return `Success` when a majority of validators produce identical result bytes.
- **Determinism of Somnia LLM inference** is trusted: for a given prompt and seed, all validators produce the same output. This is the load-bearing property that allows AI-generated verdicts to be consensus-validated.
- **JSON API endpoints** queried by agents are not trusted individually. The agent fetches the same canonical onchain data (transactions, receipts, traces) from one source; tampering would require corrupting Somnia's archival query infrastructure.

### Attack surface and mitigations

- **Adversarial claim filing.** Filers must deposit the platform fee plus a small protocol bond. Rejected claims forfeit the bond, capping spam economics.
- **Adversarial warnings.** Symmetric: warnings are bonded, and the WarningVerifierAgent must return `Exploit` above the confidence floor before bounty is paid.
- **Vault drain via correlated claims.** Tier-C tranche absorbs first-loss; Tier-A is paid out only when lower tranches are exhausted. Per-block payout caps prevent a single block from draining the vault.
- **Policy front-running.** The risk tier is sealed in the EIP-712 envelope and tied to a `nonce`; the cached tier from the RiskScoringAgent has an expiry block, forcing re-scoring on stale issuances.
- **Callback reentrancy.** All agent callbacks follow checks-effects-interactions and verify `msg.sender == address(platform)`. Vault state mutations occur before settlement transfer.
- **Confidence-floor griefing.** The floor is governance-tunable, with a hard minimum to prevent it being set so low that low-confidence verdicts trigger payout.
- **Subcommittee collusion.** Escalation increases subcommittee size and threshold through `createAdvancedRequest`, raising the collusion bar.

### Circuit breakers

Each invoking contract embeds a hysteresis-bounded circuit breaker:

- A short-window counter of `Failed` and `TimedOut` agent responses.
- A threshold above which new agent invocations are paused.
- A separate, larger threshold required to *re-enable* invocations, preventing flapping.

When tripped, `PolicyManager.issue` and `IncidentResolver.fileClaim` revert with a structured error, and the protocol routes existing pending claims to escalation.

---

## Frontend

The protocol ships with a Vite + React frontend that consumes contract state directly via viem. There is no backend service and no indexer; all data displayed in the UI is read from contract storage or from logs. Three surfaces:

- **Underwriter dashboard** — tranche balances, locked capital, premium yield, withdrawal projections.
- **Policyholder console** — covered contract selection, risk tier display from the most recent RiskScoringAgent call, premium quote, policy issuance, claim filing.
- **Sentinel terminal** — warning submission, reputation score, history feed, bounty claim.

All write operations are signed by the user's wallet. Read operations use the public Somnia RPC endpoint.

---

## Deployment topology

- **Network.** Somnia Mainnet (chain ID `5031`) for production. Somnia Testnet (chain ID `50312`) for staging.
- **Toolchain.** Foundry for contracts and tests. Vite + React + viem for the frontend.
- **Source of truth.** Contract storage on Somnia. No subgraph, no relational database, no off-chain index.
- **Configuration.** Per-network constants are deployed as immutables on each contract: `platform` address, base-agent IDs, per-agent budgets, confidence floor, circuit-breaker thresholds.
- **Governance.** A `Governor` contract with timelocked execution holds the privilege to update tunable parameters (confidence floor, per-agent budgets, circuit-breaker thresholds, tranche multipliers). The governor cannot modify already-issued policies, pending claims, or locked vault capital.

---

## Resources

- Somnia documentation root — https://docs.somnia.network/
- Somnia Agents overview — https://docs.somnia.network/agents
- Invoking Agents from Solidity — https://docs.somnia.network/agents/invoking-agents/from-solidity
- Agent web app and ID registry — https://agents.somnia.network
- Somnia network info — https://docs.somnia.network/developer/network-info
