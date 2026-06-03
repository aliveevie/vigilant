// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentClient} from "./agents/AgentClient.sol";
import {CoverageVault} from "./vault/CoverageVault.sol";
import {Response, ResponseStatus, Request} from "./interfaces/IAgentRequester.sol";
import {ILLMInference, AgentIds} from "./interfaces/IAgents.sol";
import {PolicyLib} from "./libraries/PolicyLib.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {RiskPolicy, Policy, PolicyState, CachedTier} from "./libraries/Types.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title PolicyManager
/// @notice Issues, holds, and retires Vigilant parametric exploit policies.
///         Invokes the Somnia LLM Inference base agent (inferNumber) to derive
///         a risk score for each covered contract, then maps that score to a
///         vault tranche tier.
contract PolicyManager is AgentClient {
    using PolicyLib for RiskPolicy;
    using ECDSA for bytes32;

    string public constant NAME = "Vigilant";
    string public constant VERSION = "1";

    bytes32 internal immutable _domainSeparator;

    CoverageVault public immutable vault;

    /// @dev Numeric ID of the agent invoked for risk scoring — defaults to
    ///      the LLM Inference base agent on Somnia testnet.
    uint256 public riskScoringAgentId;
    uint256 public riskScoreCostPerAgent;
    uint8 public riskScoreSubcommitteeSize;
    uint64 public tierCacheTTLBlocks;

    /// @dev System prompt fed to the LLM Inference agent for every risk-score
    ///      request. Governor-tunable.
    string public riskSystemPrompt;

    uint256 public nextPolicyId = 1;

    mapping(uint256 => Policy) public policies;
    mapping(uint256 => uint256) public requestToCoveredContract; // requestId => uint160(coveredContract)
    mapping(address => uint256[]) internal _policiesByHolder;
    mapping(address => CachedTier) public coveredContractTier;
    mapping(address => uint256) public usedNonces;

    address public incidentResolver;

    constructor(
        address platform_,
        address governor_,
        address vault_,
        uint256 riskScoringAgentId_,
        uint256 riskScoreCostPerAgent_,
        uint8 riskScoreSubcommitteeSize_,
        uint64 tierCacheTTLBlocks_
    ) AgentClient(platform_, governor_, 5, 2) {
        if (vault_ == address(0)) revert Errors.ZeroAddress();
        vault = CoverageVault(payable(vault_));
        riskScoringAgentId =
            riskScoringAgentId_ == 0 ? AgentIds.LLM_INFERENCE_ID : riskScoringAgentId_;
        riskScoreCostPerAgent = riskScoreCostPerAgent_;
        riskScoreSubcommitteeSize = riskScoreSubcommitteeSize_;
        tierCacheTTLBlocks = tierCacheTTLBlocks_;

        riskSystemPrompt =
            "You are Vigilant's risk-scoring agent for an onchain insurance protocol. "
            "Given a smart-contract address on the Somnia network, return a single integer in [0,100] "
            "representing the probability that the contract will be exploited within the next 30 days. "
            "0 means almost certainly safe, 100 means almost certainly exploitable. "
            "Consider audit history, code patterns, admin keys, oracle dependencies, and TVL.";

        _domainSeparator = PolicyLib.domainSeparator(NAME, VERSION, address(this));
    }

    function setIncidentResolver(address r) external onlyGovernor {
        if (r == address(0)) revert Errors.ZeroAddress();
        incidentResolver = r;
    }

    function setRiskScoreCostPerAgent(uint256 v) external onlyGovernor {
        emit Events.PerAgentBudgetChanged("RISK_SCORE", riskScoreCostPerAgent, v);
        riskScoreCostPerAgent = v;
    }

    function setRiskScoringAgentId(uint256 v) external onlyGovernor {
        riskScoringAgentId = v;
    }

    function setTierCacheTTLBlocks(uint64 v) external onlyGovernor {
        tierCacheTTLBlocks = v;
    }

    function setRiskSystemPrompt(string calldata v) external onlyGovernor {
        riskSystemPrompt = v;
    }

    // ---- Risk scoring ----

    function quoteRiskScoreDeposit() public view returns (uint256) {
        return _quoteDeposit(riskScoreSubcommitteeSize, riskScoreCostPerAgent);
    }

    /// @notice Request a fresh risk tier for `coveredContract`. Encodes a call
    ///         to ILLMInference.inferNumber as the payload.
    function requestRiskScore(address coveredContract)
        external
        payable
        whenCircuitClosed
        returns (uint256 requestId)
    {
        if (coveredContract == address(0)) revert Errors.ZeroAddress();
        uint256 needed = quoteRiskScoreDeposit();
        if (msg.value < needed) revert Errors.InsufficientDeposit();

        string memory prompt = _buildRiskPrompt(coveredContract);
        bytes memory payload =
            abi.encodeCall(ILLMInference.inferNumber, (prompt, riskSystemPrompt, int256(0), int256(100), false));

        requestId = _createRequest(riskScoringAgentId, payload, msg.value);
        requestToCoveredContract[requestId] = uint256(uint160(coveredContract));

        emit Events.RiskScoreRequested(requestId, coveredContract, msg.sender);
    }

    /// @notice Platform callback for the LLM Inference agent.
    function handleResponse(
        uint256 requestId,
        Response[] memory responses,
        ResponseStatus status,
        Request memory /*details*/
    ) external override onlyPlatform {
        uint256 raw = requestToCoveredContract[requestId];
        if (raw == 0) revert Errors.UnknownRequest();
        address coveredContract = address(uint160(raw));
        delete requestToCoveredContract[requestId];

        if (status != ResponseStatus.Success || responses.length == 0) {
            _onFailure();
            return;
        }

        int256 raw256 = abi.decode(responses[0].result, (int256));
        if (raw256 < 0) raw256 = 0;
        if (raw256 > 100) raw256 = 100;
        uint16 score = uint16(uint256(raw256));
        uint8 tier = _tierFromScore(score);

        CachedTier storage c = coveredContractTier[coveredContract];
        c.score = score;
        c.tier = tier;
        c.cachedAtBlock = uint64(block.number);
        c.expiresAtBlock = uint64(block.number) + tierCacheTTLBlocks;
        c.rationaleHash = keccak256(responses[0].result);

        _onSuccess();
        emit Events.RiskScoreReceived(coveredContract, score, tier, c.expiresAtBlock);
    }

    function _tierFromScore(uint16 score) internal pure returns (uint8) {
        // [0..33] → A, [34..66] → B, [67..100] → C
        if (score < 34) return 0;
        if (score < 67) return 1;
        return 2;
    }

    function _buildRiskPrompt(address coveredContract) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Estimate the 30-day exploit probability (0-100) for the Somnia contract at ",
                _toHex(coveredContract),
                "."
            )
        );
    }

    // ---- Issuance ----

    function issue(RiskPolicy calldata p, bytes calldata signature)
        external
        payable
        whenCircuitClosed
        returns (uint256 policyId)
    {
        if (p.policyholder == address(0) || p.coveredContract == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (p.coverageAmount == 0 || p.premium == 0) revert Errors.ZeroAmount();
        if (p.riskTier > 2) revert Errors.InvalidTier();
        if (p.endBlock <= p.startBlock || p.startBlock < block.number) {
            revert Errors.InvalidBlockRange();
        }

        CachedTier memory cached = coveredContractTier[p.coveredContract];
        if (cached.expiresAtBlock == 0) revert Errors.TierNotCached();
        if (block.number > cached.expiresAtBlock) revert Errors.TierExpired();
        if (cached.tier != p.riskTier) revert Errors.TierMismatch();

        if (p.nonce <= usedNonces[p.policyholder]) revert Errors.InvalidSignature();
        usedNonces[p.policyholder] = p.nonce;

        bytes32 digest = PolicyLib.digest(_domainSeparator, p.structHash());
        address signer = digest.recover(signature);
        if (signer != p.policyholder) revert Errors.InvalidSignature();

        if (msg.value < p.premium) revert Errors.InsufficientPremium();

        vault.lock(p.riskTier, p.coverageAmount);
        vault.receivePremium{value: p.premium}();

        if (msg.value > p.premium) {
            (bool ok,) = msg.sender.call{value: msg.value - p.premium}("");
            if (!ok) revert Errors.TransferFailed();
        }

        policyId = nextPolicyId++;
        Policy storage stored = policies[policyId];
        stored.policyHash = p.structHash();
        stored.state = PolicyState.Active;
        stored.policyholder = p.policyholder;
        stored.coveredContract = p.coveredContract;
        stored.coverageAmount = p.coverageAmount;
        stored.riskTier = p.riskTier;
        stored.startBlock = p.startBlock;
        stored.endBlock = p.endBlock;

        _policiesByHolder[p.policyholder].push(policyId);

        emit Events.PolicyIssued(
            policyId,
            p.policyholder,
            p.coveredContract,
            p.riskTier,
            p.coverageAmount,
            p.premium,
            p.endBlock
        );
    }

    function expire(uint256 policyId) external {
        Policy storage pol = policies[policyId];
        if (pol.state == PolicyState.None) revert Errors.UnknownPolicy();
        if (pol.state != PolicyState.Active) revert Errors.PolicyNotActive();
        if (block.number <= pol.endBlock) revert Errors.PolicyNotExpired();

        pol.state = PolicyState.Expired;
        vault.unlock(pol.riskTier, pol.coverageAmount);
        emit Events.PolicyExpired(policyId);
    }

    function markPaidOut(uint256 policyId, uint256 amount) external {
        if (msg.sender != incidentResolver) revert Errors.NotIncidentResolver();
        Policy storage pol = policies[policyId];
        if (pol.state == PolicyState.None) revert Errors.UnknownPolicy();
        if (pol.state == PolicyState.PaidOut) revert Errors.PolicyAlreadyPaid();
        pol.state = PolicyState.PaidOut;
        pol.paidOutAmount = amount;
        emit Events.PolicyPaidOut(policyId, amount);
    }

    // ---- Views ----

    function policiesOf(address holder) external view returns (uint256[] memory) {
        return _policiesByHolder[holder];
    }

    function policyDigest(RiskPolicy calldata p) external view returns (bytes32) {
        return PolicyLib.digest(_domainSeparator, p.structHash());
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator;
    }

    function _toHex(address a) internal pure returns (string memory) {
        bytes20 b = bytes20(a);
        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        bytes16 hexAlphabet = 0x30313233343536373839616263646566;
        for (uint256 i = 0; i < 20; ++i) {
            out[2 + i * 2] = hexAlphabet[uint8(b[i]) >> 4];
            out[3 + i * 2] = hexAlphabet[uint8(b[i]) & 0x0f];
        }
        return string(out);
    }

    function _circuitTag() internal pure override returns (string memory) {
        return "PolicyManager";
    }
}
