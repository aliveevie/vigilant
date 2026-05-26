// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentClient} from "./agents/AgentClient.sol";
import {CoverageVault} from "./vault/CoverageVault.sol";
import {PolicyManager} from "./PolicyManager.sol";
import {Response, ResponseStatus, Request} from "./interfaces/IAgentRequester.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {Claim, ClaimState, Classification, Policy, PolicyState} from "./libraries/Types.sol";

/// @title IncidentResolver
/// @notice Claim engine. Invokes the ExploitClassifierAgent, atomically pays out on Exploit verdict.
contract IncidentResolver is AgentClient {
    PolicyManager public immutable policyManager;
    CoverageVault public immutable vault;

    uint256 public exploitClassifierAgentId;
    uint256 public exploitClassifyCostPerAgent;
    uint8 public classifySubcommitteeSize;
    uint8 public escalatedSubcommitteeSize;
    uint8 public escalatedThreshold;

    uint8 public confidenceFloor;
    uint8 public constant MIN_CONFIDENCE_FLOOR = 51;

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
        uint8 confidenceFloor_
    ) AgentClient(platform_, governor_, 5, 2) {
        if (policyManager_ == address(0) || vault_ == address(0)) revert Errors.ZeroAddress();
        if (confidenceFloor_ < MIN_CONFIDENCE_FLOOR) revert Errors.InvalidConfidence();
        policyManager = PolicyManager(payable(policyManager_));
        vault = CoverageVault(payable(vault_));
        exploitClassifierAgentId = exploitClassifierAgentId_;
        exploitClassifyCostPerAgent = exploitClassifyCostPerAgent_;
        classifySubcommitteeSize = classifySubcommitteeSize_;
        confidenceFloor = confidenceFloor_;
        escalatedSubcommitteeSize = classifySubcommitteeSize_ * 2;
        escalatedThreshold = (escalatedSubcommitteeSize * 3) / 4; // 75%
    }

    function setConfidenceFloor(uint8 v) external onlyGovernor {
        if (v < MIN_CONFIDENCE_FLOOR) revert Errors.InvalidConfidence();
        emit Events.ConfidenceFloorChanged(confidenceFloor, v);
        confidenceFloor = v;
    }

    function setExploitClassifyCostPerAgent(uint256 v) external onlyGovernor {
        emit Events.PerAgentBudgetChanged("EXPLOIT_CLASSIFY", exploitClassifyCostPerAgent, v);
        exploitClassifyCostPerAgent = v;
    }

    function setExploitClassifierAgentId(uint256 v) external onlyGovernor {
        exploitClassifierAgentId = v;
    }

    function setEscalationParams(uint8 size, uint8 threshold) external onlyGovernor {
        if (threshold == 0 || threshold > size) revert Errors.InvalidConfidence();
        escalatedSubcommitteeSize = size;
        escalatedThreshold = threshold;
    }

    function quoteClaimDeposit() public view returns (uint256) {
        return _quoteDeposit(classifySubcommitteeSize, exploitClassifyCostPerAgent);
    }

    function quoteEscalationDeposit() public view returns (uint256) {
        return _quoteDeposit(escalatedSubcommitteeSize, exploitClassifyCostPerAgent);
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
        bytes memory payload = abi.encode(coveredContract, exploitTx, incidentBlock);
        requestId = platform.createRequest{value: value}(exploitClassifierAgentId, payload);
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
        bytes memory payload = abi.encode(coveredContract, c.exploitTx, c.incidentBlock);

        uint256 newRequestId = platform.createAdvancedRequest{value: msg.value}(
            exploitClassifierAgentId, payload, escalatedSubcommitteeSize, escalatedThreshold
        );

        c.state = ClaimState.Escalated;
        c.platformRequestId = newRequestId;
        requestToClaim[newRequestId] = claimId;
        emit Events.ClaimEscalated(claimId, newRequestId);
    }

    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata /*details*/
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

        (uint8 classification, uint8 confidence, bytes32 rationaleHash) =
            abi.decode(responses[0].result, (uint8, uint8, bytes32));
        rationaleHash;
        c.classification = classification;
        c.confidence = confidence;
        _onSuccess();
        emit Events.ClaimResolved(claimId, classification, confidence);

        if (classification == uint8(Classification.Exploit) && confidence >= confidenceFloor) {
            _payout(claimId, c);
        } else {
            c.state = ClaimState.Rejected;
            emit Events.ClaimRejected(claimId);
        }
    }

    function _payout(uint256 claimId, Claim storage c) internal {
        (,,, address holder,, uint256 coverageAmount, uint8 tier,,) =
            policyManager.policies(c.policyId);

        // checks-effects-interactions: state first, transfer second.
        c.state = ClaimState.Confirmed;
        policyManager.markPaidOut(c.policyId, coverageAmount);
        vault.unlock(tier, coverageAmount);
        vault.absorb(coverageAmount, holder);

        emit Events.ClaimPaid(claimId, coverageAmount);
    }

    function _circuitTag() internal pure override returns (string memory) {
        return "IncidentResolver";
    }
}
