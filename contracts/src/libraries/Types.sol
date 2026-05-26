// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

enum RiskTier {
    A,
    B,
    C
}

enum PolicyState {
    None,
    Active,
    Expired,
    PaidOut
}

enum ClaimState {
    None,
    Pending,
    Confirmed,
    Rejected,
    Escalated
}

enum Classification {
    Legitimate,
    Exploit,
    Inconclusive
}

enum SentinelKind {
    UnderwriterClean,
    UnderwriterLoss,
    WatcherCorrect,
    WatcherIncorrect
}

struct RiskPolicy {
    address policyholder;
    address coveredContract;
    uint256 coverageAmount;
    uint8 riskTier;
    uint256 premium;
    uint64 startBlock;
    uint64 endBlock;
    uint256 nonce;
}

struct Policy {
    bytes32 policyHash;
    PolicyState state;
    uint256 paidOutAmount;
    address policyholder;
    address coveredContract;
    uint256 coverageAmount;
    uint8 riskTier;
    uint64 startBlock;
    uint64 endBlock;
}

struct Claim {
    uint256 policyId;
    bytes32 exploitTx;
    uint256 incidentBlock;
    address filer;
    ClaimState state;
    uint256 platformRequestId;
    uint8 classification;
    uint8 confidence;
}

struct SentinelEvent {
    SentinelKind kind;
    uint256 blockNumber;
    int256 scoreDelta;
}

struct CachedTier {
    uint8 tier;
    uint16 score;
    uint64 cachedAtBlock;
    uint64 expiresAtBlock;
    bytes32 rationaleHash;
}
