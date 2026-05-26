// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Errors {
    error NotPlatform();
    error NotGovernor();
    error NotPolicyManager();
    error NotIncidentResolver();
    error UnknownRequest();
    error UnknownPolicy();
    error UnknownClaim();
    error UnknownWarning();
    error InvalidSignature();
    error TierMismatch();
    error TierExpired();
    error TierNotCached();
    error PolicyNotActive();
    error PolicyAlreadyPaid();
    error PolicyNotExpired();
    error ClaimNotPending();
    error ClaimNotEscalatable();
    error InsufficientPremium();
    error InsufficientDeposit();
    error InsufficientCapital();
    error TrancheLocked();
    error CircuitOpen();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidTier();
    error InvalidConfidence();
    error InvalidWindow();
    error InvalidBlockRange();
    error WarningPaused();
    error AlreadyInitialized();
    error TransferFailed();
}
