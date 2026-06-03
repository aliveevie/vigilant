// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Consensus mode used by the Somnia Agents platform.
enum ConsensusType {
    Majority,
    Threshold
}

/// @notice Lifecycle status of a request / response on the Somnia platform.
/// @dev Note: None == 0 (uninitialized storage), matching the documented spec.
enum ResponseStatus {
    None,
    Pending,
    Success,
    Failed,
    TimedOut
}

/// @notice Per-validator response collected during consensus.
struct Response {
    address validator;
    bytes result;
    ResponseStatus status;
    uint256 receipt;
    uint256 timestamp;
    uint256 executionCost;
}

/// @notice Full state of a request stored by the platform.
struct Request {
    uint256 id;
    address requester;
    address callbackAddress;
    bytes4 callbackSelector;
    address[] subcommittee;
    Response[] responses;
    uint256 responseCount;
    uint256 failureCount;
    uint256 threshold;
    uint256 createdAt;
    uint256 deadline;
    ResponseStatus status;
    ConsensusType consensusType;
    uint256 remainingBudget;
    uint256 perAgentBudget;
}

/// @notice Public surface of the Somnia Agents platform contract.
/// @dev Source: https://docs.somnia.network/agents/invoking-agents/from-solidity
///      Testnet (chain 50312): 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776
///      Mainnet (chain 5031): 0x5E5205CF39E766118C01636bED000A54D93163E6
interface IAgentRequester {
    event RequestCreated(
        uint256 indexed requestId,
        uint256 indexed agentId,
        uint256 perAgentBudget,
        bytes payload,
        address[] subcommittee
    );
    event RequestFinalized(uint256 indexed requestId, ResponseStatus status);
    event SubcommitteePaid(uint256 indexed requestId, uint256 totalPaid, uint256 perMember);
    event CommitteeDepositFailed(uint256 indexed requestId, uint256 attemptedAmount);

    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable returns (uint256 requestId);

    function createAdvancedRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload,
        uint256 subcommitteeSize,
        uint256 threshold,
        ConsensusType consensusType,
        uint256 timeout
    ) external payable returns (uint256 requestId);

    function getRequest(uint256 requestId) external view returns (Request memory);
    function hasRequest(uint256 requestId) external view returns (bool);
    function getRequestDeposit() external view returns (uint256);
    function getAdvancedRequestDeposit(uint256 subcommitteeSize) external view returns (uint256);
}
