# Vigilant

**Agentic L1 insurance protocol — consensus-resolved coverage for onchain assets.**

Vigilant underwrites smart-contract risk and settles claims through consensus-validated AI inference rather than human adjusters. Underwriters supply capital to tiered coverage vaults, policyholders purchase parametric exploit policies against specific covered contracts, and the protocol resolves claims by invoking Somnia Agents that fetch live forensic data, classify incidents with deterministic LLMs, and have validators rerun the verdict as part of consensus.

The protocol is fully onchain. No oracle, no DAO claim vote, no off-chain attestation, no off-chain database. Every policy, premium, claim, agent invocation, and payout is a transaction on Somnia, and the source of truth is contract storage and consensus-finalised agent receipts.

See [`architecture.md`](./architecture.md) for full protocol design, security model, and lifecycle flows.

---

## Deployed contracts — Somnia Testnet (chainId `50312`)

Block explorer: <https://shannon-explorer.somnia.network/>
RPC: `https://api.infra.testnet.somnia.network/`
Platform contract (Somnia Agents): `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776`

| Contract | Address | Explorer | Status |
|---|---|---|---|
| **Governor** | `0x6E36FEF89012f8D7C9E8B895Ca17117BD4af51FA` | [view](https://shannon-explorer.somnia.network/address/0x6E36FEF89012f8D7C9E8B895Ca17117BD4af51FA) | ✓ admin/delay readable |
| **CoverageVault** | `0xbc597Cf262ED16662BBE5b29a4922dB470c2cC84` | [view](https://shannon-explorer.somnia.network/address/0xbc597Cf262ED16662BBE5b29a4922dB470c2cC84) | ✓ holds 0.5 STT |
| **PolicyManager** | `0x30d1758D2680ED6ecA5322704d7093F53a58B824` | [view](https://shannon-explorer.somnia.network/address/0x30d1758D2680ED6ecA5322704d7093F53a58B824) | ✓ EIP-712 domain live |
| **IncidentResolver** | `0xD9d29945ffd4D79bEd40395E7a074D9506FfB919` | [view](https://shannon-explorer.somnia.network/address/0xD9d29945ffd4D79bEd40395E7a074D9506FfB919) | ✓ confidenceFloor=75 |
| **SentinelRegistry** | `0x5CC59B5806d604F68875D8b6b069100767F84f6F` | [view](https://shannon-explorer.somnia.network/address/0x5CC59B5806d604F68875D8b6b069100767F84f6F) | ✓ bounty=0.05 STT |
| **PremiumDistributor** | `0xB3031C42585b49BC074c6e416aF537a1e8Fc24bd` | [view](https://shannon-explorer.somnia.network/address/0xB3031C42585b49BC074c6e416aF537a1e8Fc24bd) | ✓ splits 70/20/10 |
| **VaultShare-A (vVIG-A)** | `0xD170d046287452DdDDa166924F400c2Ea613160F` | [view](https://shannon-explorer.somnia.network/address/0xD170d046287452DdDDa166924F400c2Ea613160F) | ✓ supply 0 |
| **VaultShare-B (vVIG-B)** | `0x7F15D2e562548F529Bb656a92F01A61f9Dadc268` | [view](https://shannon-explorer.somnia.network/address/0x7F15D2e562548F529Bb656a92F01A61f9Dadc268) | ✓ supply 5e17 |
| **VaultShare-C (vVIG-C)** | `0x66CFe382793A64C7E86AFCE52843257F3bcF62Df` | [view](https://shannon-explorer.somnia.network/address/0x66CFe382793A64C7E86AFCE52843257F3bcF62Df) | ✓ supply 0 |

Smoke test (live deposit): [`0x16c04981f195769cd05366e2670afb06830578473fc53d85502c14a76e7d2dba`](https://shannon-explorer.somnia.network/tx/0x16c04981f195769cd05366e2670afb06830578473fc53d85502c14a76e7d2dba)

---

## Contract descriptions

### `Governor`
Minimal timelock + admin-only passthrough. Holds the privilege to update tunable parameters across the protocol — confidence floor, per-agent budgets, circuit-breaker thresholds, tranche multipliers, premium splits. Owns the wiring between vault, policy manager, incident resolver, and premium distributor. Cannot modify already-issued policies, pending claims, or locked vault capital. Two interfaces:
- `queue(target, value, data) → id` + `execute(id)` for timelocked operations.
- `call(target, value, data)` for direct admin passthroughs (no timelock; used at deploy for wiring).

### `CoverageVault`
Three-tranche underwriting vault. Holds the native settlement asset (SOMI on mainnet, STT on testnet). Each tranche (A / B / C) issues a transferable ERC-20 share token (`VaultShare`) so depositor positions are composable with the rest of the Somnia DeFi ecosystem.
- **`deposit(tier)`** — payable, mints `vVIG-{A|B|C}` shares pro-rata.
- **`withdraw(tier, shares)`** — burns shares, returns native asset, reverts if the requested amount is locked.
- **`lock(tier, amount)` / `unlock(tier, amount)`** — gated to `PolicyManager` / `IncidentResolver`; blocks underwriter withdrawals against capital backing an active policy.
- **`absorb(amount, recipient)`** — only `IncidentResolver`. Applies the loss waterfall **C → B → A** and transfers native asset to the policyholder atomically with claim settlement.
- **`receivePremium()`** — payable, splits incoming premium 90% to tranches (weighted by multiplier × capital) and 10% to the protocol reserve.

Tranche multipliers (premium weight, bps): **A = 6,000**, **B = 10,000**, **C = 14,000**. C is first-loss / highest yield, A is paid out last / lowest yield.

### `VaultShare` (×3, one per tranche)
Standard ERC-20 share token (`vVIG-A` / `vVIG-B` / `vVIG-C`). Mint/burn restricted to the parent `CoverageVault`. Transferable and composable.

### `PolicyManager`
Issues, holds, and retires policies. The only contract allowed to call `vault.lock` and to mark a policy `PaidOut`. Verifies an EIP-712 `RiskPolicy` signature on issuance.
- **`requestRiskScore(coveredContract)`** — invokes `RiskScoringAgent` via the Somnia platform; caches `(score, tier, expiresAtBlock)` per covered contract for `tierCacheTTLBlocks` (deployed at 1,000 blocks).
- **`handleResponse(...)`** — Somnia platform callback; only `msg.sender == platform`.
- **`issue(RiskPolicy, signature)`** — verifies the EIP-712 envelope, asserts `riskTier` matches the cached agent verdict, enforces strictly-increasing nonce per holder, locks tranche capital, forwards premium to vault, mints the policy.
- **`expire(policyId)`** — anyone may call after `endBlock`; releases the locked capital.
- **`markPaidOut(policyId, amount)`** — only `IncidentResolver`.
- Circuit breaker auto-trips after 5 consecutive `Failed`/`TimedOut` agent responses; governor-resettable.

EIP-712 domain: `name = "Vigilant"`, `version = "1"`, `verifyingContract = PolicyManager`. Live domainSeparator on testnet: `0x88faaa29a958162cc19e0a13a438d0f299ef0b758b22d7169fceabfddfd41d6b`.

### `IncidentResolver`
Claim engine. Invokes the `ExploitClassifierAgent` and atomically pays out on an `Exploit` verdict above `confidenceFloor`.
- **`fileClaim(policyId, exploitTx, incidentBlock)`** — payable (covers platform deposit + per-agent budget); only the policyholder may file; reverts unless the incident block falls within the policy window.
- **`handleResponse(...)`** — platform-only callback. On `Success` + `classification == Exploit` + `confidence ≥ confidenceFloor`, transfers `coverageAmount` from the vault directly to the policyholder via `vault.absorb`, marks policy `PaidOut`. Otherwise marks claim `Rejected`.
- **`escalate(claimId)`** — re-routes via `platform.createAdvancedRequest` with `2×` subcommittee size and a 75% threshold for second-opinion paths.
- `confidenceFloor` is governor-tunable but cannot go below 51%.

### `SentinelRegistry`
Reputation + bounty engine for two participant classes:
- **Watcher sentinels**: submit `submitWarning(coveredContract, evidenceTx, incidentBlock)` with a bonded deposit. The `WarningVerifierAgent` adjudicates; on confirmation the watcher receives `deposit + warningBounty` (deployed at 0.05 STT bounty, 0.025 STT minimum deposit), score increases, and new policy issuance against the covered contract is paused until governor review. On a `Legitimate` or `Inconclusive` verdict, the deposit is forfeited to the protocol reserve.
- **Underwriter sentinels**: `recordUnderwriterOutcome(addr, loss)` lets the governor mark clean/loss events.
- `getScore(addr)` and `getHistory(addr)` expose the public reputation surface for other protocols.

Stricter agent floor than the claim flow (confidence ≥ 80%) since warnings are time-sensitive.

### `PremiumDistributor`
Pull-payment router for protocol revenue. Accepts native asset via `receive()` and splits into three accrual buckets:
- **70%** → vault (call `pushToVault()` to forward to `CoverageVault.receivePremium`).
- **20%** → sentinel reserve (call `pushToSentinel()` to fund `SentinelRegistry.protocolReserve`).
- **10%** → treasury (call `pushToTreasury()`).
Splits are governor-tunable as long as the three bps sum to 10,000.

---

## Somnia Agents

The protocol drives three agents through the standard `IAgentRequester` interface against the Somnia Agents platform at `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776`. Agent IDs are governor-settable on each invoking contract:

| Agent | Setter | Current ID |
|---|---|---|
| **RiskScoringAgent** | `PolicyManager.setRiskScoringAgentId(uint256)` (via Governor) | `0` (placeholder) |
| **ExploitClassifierAgent** | `IncidentResolver.setExploitClassifierAgentId(uint256)` | `0` (placeholder) |
| **WarningVerifierAgent** | `SentinelRegistry.setWarningVerifierAgentId(uint256)` | `0` (placeholder) |

Agent signatures (see `architecture.md` for full spec):

- `scoreContract(address target, string contextUri)` → ABI-encoded `(uint16 score, uint8 tier, bytes32 rationaleHash)`
- `classifyIncident(address coveredContract, bytes32 exploitTx, uint256 incidentBlock)` → ABI-encoded `(uint8 classification, uint8 confidence, bytes32 rationaleHash)`
- `verifyWarning(...)` — same shape as `classifyIncident`, stricter confidence floor and shorter timeout configured agent-side.

Register at <https://agents.somnia.network>, then set the IDs by sending three `Governor.call` transactions from the admin EOA.

---

## Repo layout

```
.
├── architecture.md                 — full protocol design doc
├── contracts/                      — Foundry project
│   ├── src/
│   │   ├── interfaces/             — IAgentRequester, IAgentResponder
│   │   ├── libraries/              — PolicyLib (EIP-712), Types, Errors, Events
│   │   ├── agents/AgentClient.sol  — base for any agent invoker (circuit breaker, deposit math)
│   │   ├── vault/                  — CoverageVault, VaultShare
│   │   ├── PolicyManager.sol
│   │   ├── IncidentResolver.sol
│   │   ├── SentinelRegistry.sol
│   │   ├── PremiumDistributor.sol
│   │   └── Governor.sol
│   ├── test/                       — 25 tests, all passing
│   └── script/Deploy.s.sol
└── deployments/somnia-testnet.json
```

---

## Development

```bash
cd contracts
forge build
forge test                          # 25 tests
```

## Deploying (Somnia testnet)

```bash
cd contracts
# 1) Populate .env (see .env.example)
# 2) Ensure the Foundry keystore `vigil-deployer` exists and is funded with STT.
forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://api.infra.testnet.somnia.network/ \
  --account vigil-deployer \
  --sender 0xdb0Da230344Db3c46F2c33C085fB3670b4593B7F \
  --broadcast --slow --legacy \
  --gas-estimate-multiplier 3000
```

### Somnia gas notes

Somnia charges **3,125 gas / byte** of deployed bytecode (15.6× Ethereum's 200), inflated `KECCAK256` and `LOG*` costs, and per-cold-storage-key surcharges. Forge estimates with Ethereum costs, so:
- **deploys** need `--gas-estimate-multiplier 3000` (30×).
- **runtime calls** that touch storage + emit events need an explicit `--gas-limit 5000000`.

Use the **canonical RPC** `https://api.infra.testnet.somnia.network/` (not `dream-rpc.somnia.network`).

---

## Testing on testnet

| Action | Command |
|---|---|
| Deposit to tranche B | `cast send 0xbc597Cf262ED16662BBE5b29a4922dB470c2cC84 'deposit(uint8)' 1 --value 0.5ether --account vigil-deployer --legacy --gas-limit 5000000 --rpc-url <RPC>` |
| Read total capital | `cast call 0xbc597Cf262ED16662BBE5b29a4922dB470c2cC84 'totalCapital()(uint256)' --rpc-url <RPC>` |
| Read tranche totals | `cast call 0xbc597Cf262ED16662BBE5b29a4922dB470c2cC84 'trancheTotals(uint8)(uint256,uint256,uint256,uint16)' 1 --rpc-url <RPC>` |
| Set agent ID via Governor | `cast send 0x6E36FEF89012f8D7C9E8B895Ca17117BD4af51FA 'call(address,uint256,bytes)' 0x30d1758D2680ED6ecA5322704d7093F53a58B824 0 $(cast calldata 'setRiskScoringAgentId(uint256)' <ID>) --account vigil-deployer --legacy --gas-limit 200000 --rpc-url <RPC>` |
