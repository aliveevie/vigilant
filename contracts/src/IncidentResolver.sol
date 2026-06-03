// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentClient} from "./agents/AgentClient.sol";
import {CoverageVault} from "./vault/CoverageVault.sol";
import {PolicyManager} from "./PolicyManager.sol";
import {ConsensusType, Response, ResponseStatus, Request} from "./interfaces/IAgentRequester.sol";
import {ILLMInference, AgentIds} from "./interfaces/IAgents.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {Claim, ClaimState, Policy, PolicyState} from "./libraries/Types.sol";

/// @title IncidentResolver
/// @notice Claim engine. Invokes the Somnia LLM Inference base agent
///         (inferString, with allowedValues forming a verdict enum) to classify
///         whether a reported transaction is an exploit. Atomically pays out
///         when the verdict is "Exploit".
contract IncidentResolver is AgentClient {
    PolicyManager public immutable policyManager;
    CoverageVault public immutable vault;

    uint256 public exploitClassifierAgentId;
    uint256 public exploitClassifyCostPerAgent;
    uint8 public classifySubcommitteeSize;

    /// @dev Escalation tunables for `createAdvancedRequest`.
    uint8 public escalatedSubcommitteeSize;
    uint8 public escalatedThreshold;
    uint256 public escalatedTimeout;

    /// @dev System prompt fed to the LLM Inference agent for every classification.
    string public classifierSystemPrompt;
    string public constant VERDICT_EXPLOIT = "Exploit";
    string public constant VERDICT_NOT_EXPLOIT = "NotExploit";
    string public constant VERDICT_INCONCLUSIVE = "Inconclusive";

    uint256 public nextClaimId = 1;
    mapping(uint256 => Claim) public claims;
    mapping(uint256 => uint256) public requestToClaim;

    constructor(
        address platform_,
        address governor_,
        address policyManager_,
        address vault_,
        uint256 exploitClassifierAgentId_,
        uint256 exploitClassifyCostPerAgent_,
        uint8 classifySubcommitteeSize_,
        uint256 escalatedTimeout_
    ) AgentClient(platform_, governor_, 5, 2) {
        if (policyManager_ == address(0) || vault_ == address(0)) revert Errors.ZeroAddress();
        policyManager = PolicyManager(payable(policyManager_));
        vault = CoverageVault(payable(vault_));
        exploitClassifierAgentId = exploitClassifierAgentId_ == 0
            ? AgentIds.LLM_INFERENCE_ID
            : exploitClassifierAgentId_;
        exploitClassifyCostPerAgent = exploitClassifyCostPerAgent_;
        classifySubcommitteeSize = classifySubcommitteeSize_;
        escalatedSubcommitteeSize = classifySubcommitteeSize_ * 2;
        escalatedThreshold = (escalatedSubcommitteeSize * 3) / 4; // 75%
        escalatedTimeout = escalatedTimeout_ == 0 ? 1 hours : escalatedTimeout_;

        classifierSystemPrompt =
            "You are Vigilant's claim adjudicator. Given a Somnia contract address, "
            "a candidate exploit transaction hash, and the block at which the incident occurred, "
            "decide if the transaction exploited the contract. Respond with exactly one of: "
            "\"Exploit\", \"NotExploit\", \"Inconclusive\". "
            "Only answer \"Exploit\" if the transaction caused unauthorized loss of value or "
            "abuse of an unintended state transition. Use \"Inconclusive\" if evidence is "
            "insufficient. Never fabricate.";
    }

    function setExploitClassifyCostPerAgent(uint256 v) external onlyGovernor {
        emit Events.PerAgentBudgetChanged("EXPLOIT_CLASSIFY", exploitClassifyCostPerAgent, v);
        exploitClassifyCostPerAgent = v;
    }

    function setExploitClassifierAgentId(uint256 v) external onlyGovernor {
        exploitClassifierAgentId = v;
    }

    function setEscalationParams(uint8 size, uint8 threshold, uint256 timeout)
        external
        onlyGovernor
    {
        if (threshold == 0 || threshold > size) revert Errors.InvalidConfidence();
        escalatedSubcommitteeSize = size;
        escalatedThreshold = threshold;
        if (timeout != 0) escalatedTimeout = timeout;
    }

    function setClassifierSystemPrompt(string calldata v) external onlyGovernor {
        classifierSystemPrompt = v;
    }

    function quoteClaimDeposit() public view returns (uint256) {
        return _quoteDeposit(classifySubcommitteeSize, exploitClassifyCostPerAgent);
    }

    function quoteEscalationDeposit() public view returns (uint256) {
        return _quoteAdvancedDeposit(escalatedSubcommitteeSize, exploitClassifyCostPerAgent);
    }

    // ---- Claim lifecycle ----

    function fileClaim(uint256 policyId, bytes32 exploitTx, uint256 incidentBlock)
        external
        payable
        whenCircuitClosed
        returns (uint256 claimId)
    {
        _assertClaimFilable(policyId, incidentBlock);
        if (msg.value < quoteClaimDeposit()) revert Errors.InsufficientDeposit();

        uint256 requestId = _dispatchClassifier(policyId, exploitTx, incidentBlock, msg.value);

        claimId = nextClaimId++;
        Claim storage c = claims[claimId];
        c.policyId = policyId;
        c.exploitTx = exploitTx;
        c.incidentBlock = incidentBlock;
        c.filer = msg.sender;
        c.state = ClaimState.Pending;
        c.platformRequestId = requestId;
        requestToClaim[requestId] = claimId;

        emit Events.ClaimFiled(claimId, policyId, msg.sender, exploitTx, incidentBlock, requestId);
    }

    function _assertClaimFilable(uint256 policyId, uint256 incidentBlock) internal view {
        (
            ,
            PolicyState state,
            ,
            address holder,
            ,
            ,
            ,
            uint64 startBlock,
            uint64 endBlock
        ) = policyManager.policies(policyId);
        if (state == PolicyState.None) revert Errors.UnknownPolicy();
        if (state != PolicyState.Active) revert Errors.PolicyNotActive();
        if (msg.sender != holder) revert Errors.NotPolicyManager();
        if (incidentBlock < startBlock || incidentBlock > endBlock) revert Errors.InvalidBlockRange();
    }

    function _dispatchClassifier(
        uint256 policyId,
        bytes32 exploitTx,
        uint256 incidentBlock,
        uint256 value
    ) internal returns (uint256 requestId) {
        (,,,, address coveredContract,,,,) = policyManager.policies(policyId);
        bytes memory payload = _buildClassifierPayload(coveredContract, exploitTx, incidentBlock);
        requestId = _createRequest(exploitClassifierAgentId, payload, value);
    }

    function escalate(uint256 claimId) external payable whenCircuitClosed {
        Claim storage c = claims[claimId];
        if (c.state == ClaimState.None) revert Errors.UnknownClaim();
        if (c.state != ClaimState.Rejected && c.state != ClaimState.Pending) {
            revert Errors.ClaimNotEscalatable();
        }
        if (msg.sender != c.filer) revert Errors.NotPolicyManager();

        uint256 needed = quoteEscalationDeposit();
        if (msg.value < needed) revert Errors.InsufficientDeposit();

        (,,,, address coveredContract,,,,) = policyManager.policies(c.policyId);
        bytes memory payload = _buildClassifierPayload(coveredContract, c.exploitTx, c.incidentBlock);

        uint256 newRequestId = _createAdvancedRequest(
            exploitClassifierAgentId,
            payload,
            msg.value,
            escalatedSubcommitteeSize,
            escalatedThreshold,
            ConsensusType.Threshold,
            escalatedTimeout
        );

        c.state = ClaimState.Escalated;
        c.platformRequestId = newRequestId;
        requestToClaim[newRequestId] = claimId;
        emit Events.ClaimEscalated(claimId, newRequestId);
    }

    function handleResponse(
        uint256 requestId,
        Response[] memory responses,
        ResponseStatus status,
        Request memory /*details*/
    ) external override onlyPlatform {
        uint256 claimId = requestToClaim[requestId];
        if (claimId == 0) revert Errors.UnknownRequest();
        delete requestToClaim[requestId];

        Claim storage c = claims[claimId];

        if (status != ResponseStatus.Success || responses.length == 0) {
            _onFailure();
            c.state = ClaimState.Rejected;
            emit Events.ClaimRejected(claimId);
            return;
        }

        string memory verdict = abi.decode(responses[0].result, (string));
        bool isExploit = _stringEq(verdict, VERDICT_EXPLOIT);
        c.classification = isExploit ? 1 : 0;
        c.confidence = 0;
        _onSuccess();
        emit Events.ClaimResolved(claimId, c.classification, c.confidence);

        if (isExploit) {
            _payout(claimId, c);
        } else {
            c.state = ClaimState.Rejected;
            emit Events.ClaimRejected(claimId);
        }
    }

    function _payout(uint256 claimId, Claim storage c) internal {
        (,,, address holder,, uint256 coverageAmount, uint8 tier,,) =
            policyManager.policies(c.policyId);

        // checks-effects-interactions: state first, transfers second.
        c.state = ClaimState.Confirmed;
        policyManager.markPaidOut(c.policyId, coverageAmount);
        vault.unlock(tier, coverageAmount);
        vault.absorb(coverageAmount, holder);

        emit Events.ClaimPaid(claimId, coverageAmount);
    }

    function _buildClassifierPayload(
        address coveredContract,
        bytes32 exploitTx,
        uint256 incidentBlock
    ) internal view returns (bytes memory) {
        string memory prompt = string(
            abi.encodePacked(
                "Contract: ",
                _toHex(coveredContract),
                ". Suspect transaction: ",
                _toHex32(exploitTx),
                ". Incident block: ",
                _toDec(incidentBlock),
                ". Was this transaction an exploit?"
            )
        );
        string[] memory allowed = new string[](3);
        allowed[0] = VERDICT_EXPLOIT;
        allowed[1] = VERDICT_NOT_EXPLOIT;
        allowed[2] = VERDICT_INCONCLUSIVE;
        return abi.encodeCall(
            ILLMInference.inferString, (prompt, classifierSystemPrompt, false, allowed)
        );
    }

    function _stringEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _toHex(address a) internal pure returns (string memory) {
        return _bytesToHex(abi.encodePacked(a), 20);
    }

    function _toHex32(bytes32 b) internal pure returns (string memory) {
        return _bytesToHex(abi.encodePacked(b), 32);
    }

    function _bytesToHex(bytes memory raw, uint256 len) internal pure returns (string memory) {
        bytes memory out = new bytes(2 + len * 2);
        out[0] = "0";
        out[1] = "x";
        bytes16 hexAlphabet = 0x30313233343536373839616263646566;
        for (uint256 i = 0; i < len; ++i) {
            out[2 + i * 2] = hexAlphabet[uint8(raw[i]) >> 4];
            out[3 + i * 2] = hexAlphabet[uint8(raw[i]) & 0x0f];
        }
        return string(out);
    }

    function _toDec(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 n = v;
        uint256 len;
        while (n != 0) {
            ++len;
            n /= 10;
        }
        bytes memory out = new bytes(len);
        n = v;
        while (n != 0) {
            --len;
            out[len] = bytes1(uint8(48 + (n % 10)));
            n /= 10;
        }
        return string(out);
    }

    function _circuitTag() internal pure override returns (string memory) {
        return "IncidentResolver";
    }
}
