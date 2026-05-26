// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Events {
    event RiskScoreRequested(
        uint256 indexed requestId, address indexed coveredContract, address indexed caller
    );
    event RiskScoreReceived(
        address indexed coveredContract, uint16 score, uint8 tier, uint64 expiresAtBlock
    );
    event PolicyIssued(
        uint256 indexed policyId,
        address indexed policyholder,
        address indexed coveredContract,
        uint8 riskTier,
        uint256 coverageAmount,
        uint256 premium,
        uint64 endBlock
    );
    event PolicyExpired(uint256 indexed policyId);
    event PolicyPaidOut(uint256 indexed policyId, uint256 amount);

    event ClaimFiled(
        uint256 indexed claimId,
        uint256 indexed policyId,
        address indexed filer,
        bytes32 exploitTx,
        uint256 incidentBlock,
        uint256 requestId
    );
    event ClaimResolved(uint256 indexed claimId, uint8 classification, uint8 confidence);
    event ClaimEscalated(uint256 indexed claimId, uint256 newRequestId);
    event ClaimPaid(uint256 indexed claimId, uint256 amount);
    event ClaimRejected(uint256 indexed claimId);

    event WarningSubmitted(
        uint256 indexed warningId,
        address indexed sentinel,
        address indexed coveredContract,
        bytes32 evidenceTx
    );
    event WarningResolved(uint256 indexed warningId, uint8 classification, uint8 confidence);
    event WarningBountyPaid(uint256 indexed warningId, address indexed sentinel, uint256 amount);
    event WarningForfeited(uint256 indexed warningId, address indexed sentinel, uint256 amount);
    event CoveragePaused(address indexed coveredContract);

    event PremiumReceived(uint256 amount);
    event PremiumDistributed(uint256 tierA, uint256 tierB, uint256 tierC, uint256 reserve);

    event CapitalDeposited(address indexed who, uint8 tier, uint256 assets, uint256 shares);
    event CapitalWithdrawn(address indexed who, uint8 tier, uint256 assets, uint256 shares);
    event CapitalLocked(uint8 tier, uint256 amount);
    event CapitalUnlocked(uint8 tier, uint256 amount);
    event CapitalAbsorbed(uint8 tier, uint256 amount);

    event CircuitTripped(string component);
    event CircuitReset(string component);

    event GovernorChanged(address indexed previous, address indexed next);
    event ConfidenceFloorChanged(uint8 previous, uint8 next);
    event PerAgentBudgetChanged(string indexed key, uint256 previous, uint256 next);
}
