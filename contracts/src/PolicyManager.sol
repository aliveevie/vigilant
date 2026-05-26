// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentClient} from "./agents/AgentClient.sol";
import {CoverageVault} from "./vault/CoverageVault.sol";
import {IAgentRequester, Response, ResponseStatus, Request} from "./interfaces/IAgentRequester.sol";
import {PolicyLib} from "./libraries/PolicyLib.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {
    RiskPolicy,
    Policy,
    PolicyState,
    CachedTier
} from "./libraries/Types.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title PolicyManager
/// @notice Issues, holds, and retires Vigilant parametric exploit policies.
///         Invokes the RiskScoringAgent to seal risk tier into each EIP-712 envelope.
contract PolicyManager is AgentClient {
    using PolicyLib for RiskPolicy;
    using ECDSA for bytes32;

    string public constant NAME = "Vigilant";
    string public constant VERSION = "1";

    bytes32 internal immutable _domainSeparator;

    CoverageVault public immutable vault;

    uint256 public riskScoringAgentId;
    uint256 public riskScoreCostPerAgent;
    uint8 public riskScoreSubcommitteeSize;
    uint64 public tierCacheTTLBlocks;

    uint256 public nextPolicyId = 1;

    mapping(uint256 => Policy) public policies;
    mapping(uint256 => uint256) public requestToCoveredContract; // requestId => uint160(coveredContract)
    mapping(address => uint256[]) internal _policiesByHolder;
    mapping(address => CachedTier) public coveredContractTier;
    mapping(address => uint256) public usedNonces; // policyholder => nonce bitmap pointer (monotonic)

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
        riskScoringAgentId = riskScoringAgentId_;
        riskScoreCostPerAgent = riskScoreCostPerAgent_;
        riskScoreSubcommitteeSize = riskScoreSubcommitteeSize_;
        tierCacheTTLBlocks = tierCacheTTLBlocks_;

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

    // ---- Risk scoring ----

    function quoteRiskScoreDeposit() public view returns (uint256) {
        return _quoteDeposit(riskScoreSubcommitteeSize, riskScoreCostPerAgent);
    }

    /// @notice Request a fresh risk tier for `coveredContract`.
    function requestRiskScore(address coveredContract)
        external
        payable
        whenCircuitClosed
        returns (uint256 requestId)
    {
        if (coveredContract == address(0)) revert Errors.ZeroAddress();
        uint256 needed = quoteRiskScoreDeposit();
        if (msg.value < needed) revert Errors.InsufficientDeposit();

        bytes memory payload = abi.encode(coveredContract, _contextUri(coveredContract));
        requestId = platform.createRequest{value: msg.value}(riskScoringAgentId, payload);
        requestToCoveredContract[requestId] = uint256(uint160(coveredContract));

        emit Events.RiskScoreRequested(requestId, coveredContract, msg.sender);
    }

    /// @notice Platform callback for the RiskScoringAgent.
    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata /*details*/
    ) external override onlyPlatform {
        uint256 raw = requestToCoveredContract[requestId];
        if (raw == 0) revert Errors.UnknownRequest();
        address coveredContract = address(uint160(raw));
        delete requestToCoveredContract[requestId];

        if (status != ResponseStatus.Success || responses.length == 0) {
            _onFailure();
            return;
        }

        (uint16 score, uint8 tier, bytes32 rationaleHash) =
            abi.decode(responses[0].result, (uint16, uint8, bytes32));

        if (tier > 2) revert Errors.InvalidTier();

        CachedTier storage c = coveredContractTier[coveredContract];
        c.score = score;
        c.tier = tier;
        c.cachedAtBlock = uint64(block.number);
        c.expiresAtBlock = uint64(block.number) + tierCacheTTLBlocks;
        c.rationaleHash = rationaleHash;

        _onSuccess();
        emit Events.RiskScoreReceived(coveredContract, score, tier, c.expiresAtBlock);
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

        // Replay protection: nonce must be strictly increasing per holder.
        if (p.nonce <= usedNonces[p.policyholder]) revert Errors.InvalidSignature();
        usedNonces[p.policyholder] = p.nonce;

        // Verify EIP-712 signature.
        bytes32 digest = PolicyLib.digest(_domainSeparator, p.structHash());
        address signer = digest.recover(signature);
        if (signer != p.policyholder) revert Errors.InvalidSignature();

        if (msg.value < p.premium) revert Errors.InsufficientPremium();

        // Lock capital in the matching tranche.
        vault.lock(p.riskTier, p.coverageAmount);

        // Forward premium to vault (premium accounting + distribution).
        vault.receivePremium{value: p.premium}();

        // Refund overpayment.
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

    /// @notice Called only by IncidentResolver after a confirmed exploit verdict.
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

    function _contextUri(address c) internal pure returns (string memory) {
        // Pinned to the Somnia explorer contract page. Validators dereference offchain.
        return string(abi.encodePacked("somnia://contract/", _toHex(c)));
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
