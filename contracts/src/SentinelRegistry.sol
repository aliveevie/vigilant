// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentClient} from "./agents/AgentClient.sol";
import {Response, ResponseStatus, Request} from "./interfaces/IAgentRequester.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {SentinelEvent, SentinelKind, Classification} from "./libraries/Types.sol";

/// @title SentinelRegistry
/// @notice Tracks watcher/underwriter reputation and processes warning bounties.
contract SentinelRegistry is AgentClient {
    struct Warning {
        address sentinel;
        address coveredContract;
        bytes32 evidenceTx;
        uint256 incidentBlock;
        uint256 deposit;
        uint256 platformRequestId;
        bool resolved;
        bool confirmed;
    }

    uint256 public warningVerifierAgentId;
    uint256 public warningVerifyCostPerAgent;
    uint8 public warningSubcommitteeSize;
    uint8 public warningConfidenceFloor;

    uint256 public warningBounty;
    uint256 public minSentinelDeposit;

    uint256 public nextWarningId = 1;
    mapping(uint256 => Warning) public warnings;
    mapping(uint256 => uint256) public requestToWarning;
    mapping(address => bool) public coveragePaused;

    mapping(address => uint256) internal _scores;
    mapping(address => SentinelEvent[]) internal _history;

    int256 public constant SCORE_DELTA_CORRECT = 100;
    int256 public constant SCORE_DELTA_INCORRECT = -50;
    int256 public constant SCORE_DELTA_UNDERWRITER_CLEAN = 10;
    int256 public constant SCORE_DELTA_UNDERWRITER_LOSS = -100;

    constructor(
        address platform_,
        address governor_,
        uint256 warningVerifierAgentId_,
        uint256 warningVerifyCostPerAgent_,
        uint8 warningSubcommitteeSize_,
        uint8 warningConfidenceFloor_,
        uint256 warningBounty_,
        uint256 minSentinelDeposit_
    ) AgentClient(platform_, governor_, 5, 2) {
        if (warningConfidenceFloor_ < 51) revert Errors.InvalidConfidence();
        warningVerifierAgentId = warningVerifierAgentId_;
        warningVerifyCostPerAgent = warningVerifyCostPerAgent_;
        warningSubcommitteeSize = warningSubcommitteeSize_;
        warningConfidenceFloor = warningConfidenceFloor_;
        warningBounty = warningBounty_;
        minSentinelDeposit = minSentinelDeposit_;
    }

    function setWarningBounty(uint256 v) external onlyGovernor {
        warningBounty = v;
    }

    function setMinSentinelDeposit(uint256 v) external onlyGovernor {
        minSentinelDeposit = v;
    }

    function setWarningConfidenceFloor(uint8 v) external onlyGovernor {
        if (v < 51) revert Errors.InvalidConfidence();
        warningConfidenceFloor = v;
    }

    function setWarningVerifyCostPerAgent(uint256 v) external onlyGovernor {
        emit Events.PerAgentBudgetChanged("WARNING_VERIFY", warningVerifyCostPerAgent, v);
        warningVerifyCostPerAgent = v;
    }

    function setWarningVerifierAgentId(uint256 v) external onlyGovernor {
        warningVerifierAgentId = v;
    }

    function fundReserve() external payable {
        protocolReserve += msg.value;
    }

    function quoteWarningDeposit() public view returns (uint256) {
        return _quoteDeposit(warningSubcommitteeSize, warningVerifyCostPerAgent) + minSentinelDeposit;
    }

    // ---- Warning lifecycle ----

    function submitWarning(address coveredContract, bytes32 evidenceTx, uint256 incidentBlock)
        external
        payable
        whenCircuitClosed
        returns (uint256 warningId)
    {
        if (coveredContract == address(0)) revert Errors.ZeroAddress();
        uint256 platformPart = _quoteDeposit(warningSubcommitteeSize, warningVerifyCostPerAgent);
        if (msg.value < platformPart + minSentinelDeposit) revert Errors.InsufficientDeposit();

        bytes memory payload = abi.encode(coveredContract, evidenceTx, incidentBlock);
        uint256 requestId = platform.createRequest{value: platformPart}(
            warningVerifierAgentId, payload
        );

        warningId = nextWarningId++;
        Warning storage w = warnings[warningId];
        w.sentinel = msg.sender;
        w.coveredContract = coveredContract;
        w.evidenceTx = evidenceTx;
        w.incidentBlock = incidentBlock;
        w.deposit = msg.value - platformPart;
        w.platformRequestId = requestId;
        requestToWarning[requestId] = warningId;

        emit Events.WarningSubmitted(warningId, msg.sender, coveredContract, evidenceTx);
    }

    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata /*details*/
    ) external override onlyPlatform {
        uint256 warningId = requestToWarning[requestId];
        if (warningId == 0) revert Errors.UnknownRequest();
        delete requestToWarning[requestId];

        Warning storage w = warnings[warningId];
        w.resolved = true;

        if (status != ResponseStatus.Success || responses.length == 0) {
            _onFailure();
            _forfeit(warningId, w);
            return;
        }

        (uint8 classification, uint8 confidence,) =
            abi.decode(responses[0].result, (uint8, uint8, bytes32));
        _onSuccess();
        emit Events.WarningResolved(warningId, classification, confidence);

        if (
            classification == uint8(Classification.Exploit)
                && confidence >= warningConfidenceFloor
        ) {
            _reward(warningId, w);
        } else {
            _forfeit(warningId, w);
        }
    }

    function _reward(uint256 warningId, Warning storage w) internal {
        w.confirmed = true;
        coveragePaused[w.coveredContract] = true;
        emit Events.CoveragePaused(w.coveredContract);

        _bumpScore(w.sentinel, SCORE_DELTA_CORRECT, SentinelKind.WatcherCorrect);

        uint256 payout = w.deposit + warningBounty;
        if (payout > protocolReserve + w.deposit) {
            payout = protocolReserve + w.deposit;
        }
        if (warningBounty > 0) {
            if (warningBounty > protocolReserve) protocolReserve = 0;
            else protocolReserve -= warningBounty;
        }

        (bool ok,) = w.sentinel.call{value: payout}("");
        if (!ok) revert Errors.TransferFailed();
        emit Events.WarningBountyPaid(warningId, w.sentinel, payout);
    }

    function _forfeit(uint256 warningId, Warning storage w) internal {
        protocolReserve += w.deposit;
        _bumpScore(w.sentinel, SCORE_DELTA_INCORRECT, SentinelKind.WatcherIncorrect);
        emit Events.WarningForfeited(warningId, w.sentinel, w.deposit);
    }

    function _bumpScore(address sentinel, int256 delta, SentinelKind kind) internal {
        if (delta >= 0) {
            _scores[sentinel] += uint256(delta);
        } else {
            uint256 abs = uint256(-delta);
            _scores[sentinel] = _scores[sentinel] > abs ? _scores[sentinel] - abs : 0;
        }
        _history[sentinel].push(SentinelEvent({kind: kind, blockNumber: block.number, scoreDelta: delta}));
    }

    /// @notice Called by IncidentResolver / PolicyManager (via governor wiring) to record underwriter outcomes.
    function recordUnderwriterOutcome(address underwriter, bool loss) external onlyGovernor {
        if (loss) {
            _bumpScore(underwriter, SCORE_DELTA_UNDERWRITER_LOSS, SentinelKind.UnderwriterLoss);
        } else {
            _bumpScore(underwriter, SCORE_DELTA_UNDERWRITER_CLEAN, SentinelKind.UnderwriterClean);
        }
    }

    /// @notice Governor may resume coverage after manual review.
    function resumeCoverage(address coveredContract) external onlyGovernor {
        coveragePaused[coveredContract] = false;
    }

    // ---- Views ----

    function getScore(address sentinel) external view returns (uint256) {
        return _scores[sentinel];
    }

    function getHistory(address sentinel) external view returns (SentinelEvent[] memory) {
        return _history[sentinel];
    }

    function _circuitTag() internal pure override returns (string memory) {
        return "SentinelRegistry";
    }
}
