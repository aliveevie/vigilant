// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentClient} from "./agents/AgentClient.sol";
import {Response, ResponseStatus, Request} from "./interfaces/IAgentRequester.sol";
import {ILLMInference, AgentIds} from "./interfaces/IAgents.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {SentinelEvent, SentinelKind} from "./libraries/Types.sol";

/// @title SentinelRegistry
/// @notice Tracks watcher/underwriter reputation and processes warning bounties.
///         Invokes the Somnia LLM Inference base agent (inferString, constrained
///         to {"Confirmed","Unconfirmed","Inconclusive"}) to verify each warning.
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

    uint256 public warningBounty;
    uint256 public minSentinelDeposit;

    /// @dev System prompt fed to the LLM Inference agent for each warning.
    string public warningSystemPrompt;
    string public constant VERDICT_CONFIRMED = "Confirmed";
    string public constant VERDICT_UNCONFIRMED = "Unconfirmed";
    string public constant VERDICT_INCONCLUSIVE = "Inconclusive";

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
        uint256 warningBounty_,
        uint256 minSentinelDeposit_
    ) AgentClient(platform_, governor_, 5, 2) {
        warningVerifierAgentId =
            warningVerifierAgentId_ == 0 ? AgentIds.LLM_INFERENCE_ID : warningVerifierAgentId_;
        warningVerifyCostPerAgent = warningVerifyCostPerAgent_;
        warningSubcommitteeSize = warningSubcommitteeSize_;
        warningBounty = warningBounty_;
        minSentinelDeposit = minSentinelDeposit_;

        warningSystemPrompt =
            "You are Vigilant's sentinel warning verifier. Given a Somnia contract address and "
            "a transaction hash flagged by a sentinel as evidence of an active exploit, answer "
            "with exactly one of: \"Confirmed\", \"Unconfirmed\", \"Inconclusive\". "
            "Answer \"Confirmed\" only if the transaction shows active abuse of the contract.";
    }

    function setWarningBounty(uint256 v) external onlyGovernor {
        warningBounty = v;
    }

    function setMinSentinelDeposit(uint256 v) external onlyGovernor {
        minSentinelDeposit = v;
    }

    function setWarningVerifyCostPerAgent(uint256 v) external onlyGovernor {
        emit Events.PerAgentBudgetChanged("WARNING_VERIFY", warningVerifyCostPerAgent, v);
        warningVerifyCostPerAgent = v;
    }

    function setWarningVerifierAgentId(uint256 v) external onlyGovernor {
        warningVerifierAgentId = v;
    }

    function setWarningSystemPrompt(string calldata v) external onlyGovernor {
        warningSystemPrompt = v;
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
        uint256 platformPart =
            _quoteDeposit(warningSubcommitteeSize, warningVerifyCostPerAgent);
        if (msg.value < platformPart + minSentinelDeposit) revert Errors.InsufficientDeposit();

        bytes memory payload = _buildWarningPayload(coveredContract, evidenceTx, incidentBlock);
        uint256 requestId = _createRequest(warningVerifierAgentId, payload, platformPart);

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
        Response[] memory responses,
        ResponseStatus status,
        Request memory /*details*/
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

        string memory verdict = abi.decode(responses[0].result, (string));
        bool confirmed = _stringEq(verdict, VERDICT_CONFIRMED);
        _onSuccess();
        emit Events.WarningResolved(warningId, confirmed ? 1 : 0, 0);

        if (confirmed) {
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
        _history[sentinel].push(
            SentinelEvent({kind: kind, blockNumber: block.number, scoreDelta: delta})
        );
    }

    function recordUnderwriterOutcome(address underwriter, bool loss) external onlyGovernor {
        if (loss) {
            _bumpScore(underwriter, SCORE_DELTA_UNDERWRITER_LOSS, SentinelKind.UnderwriterLoss);
        } else {
            _bumpScore(underwriter, SCORE_DELTA_UNDERWRITER_CLEAN, SentinelKind.UnderwriterClean);
        }
    }

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

    // ---- Payload helpers ----

    function _buildWarningPayload(
        address coveredContract,
        bytes32 evidenceTx,
        uint256 incidentBlock
    ) internal view returns (bytes memory) {
        string memory prompt = string(
            abi.encodePacked(
                "Contract: ",
                _toHex(coveredContract),
                ". Evidence transaction: ",
                _toHex32(evidenceTx),
                ". Incident block: ",
                _toDec(incidentBlock),
                ". Does this transaction confirm an active exploit?"
            )
        );
        string[] memory allowed = new string[](3);
        allowed[0] = VERDICT_CONFIRMED;
        allowed[1] = VERDICT_UNCONFIRMED;
        allowed[2] = VERDICT_INCONCLUSIVE;
        return abi.encodeCall(
            ILLMInference.inferString, (prompt, warningSystemPrompt, false, allowed)
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
        return "SentinelRegistry";
    }
}
