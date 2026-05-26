// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Status returned by the Somnia Agents platform for a finalised request.
enum ResponseStatus {
    Pending,
    Success,
    Failed,
    TimedOut,
    Inconclusive
}

/// @notice Per-validator response collected during consensus.
struct Response {
    address validator;
    bytes result;
    uint256 timestamp;
}

/// @notice Original request descriptor stored by the platform.
struct Request {
    uint256 agentId;
    address requester;
    bytes payload;
    uint8 subcommitteeSize;
    uint8 threshold;
    uint256 deposit;
    uint256 createdAt;
}

/// @notice Minimum surface of the Somnia Agents platform contract used by Vigilant.
/// @dev Mirrors the public interface documented at
///      https://docs.somnia.network/agents/invoking-agents/from-solidity.
interface IAgentRequester {
    function createRequest(uint256 agentId, bytes calldata payload)
        external
        payable
        returns (uint256 requestId);

    function createAdvancedRequest(
        uint256 agentId,
        bytes calldata payload,
        uint8 subcommitteeSize,
        uint8 threshold
    ) external payable returns (uint256 requestId);

    function getRequestDeposit() external view returns (uint256);
}
