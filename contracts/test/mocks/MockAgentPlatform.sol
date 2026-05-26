// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IAgentRequester,
    Response,
    ResponseStatus,
    Request
} from "../../src/interfaces/IAgentRequester.sol";
import {IAgentResponder} from "../../src/interfaces/IAgentResponder.sol";

/// @notice Mock Somnia Agents platform for Foundry tests.
/// @dev Records each request, lets the test driver dispatch a consensus response back to the caller.
contract MockAgentPlatform is IAgentRequester {
    struct Pending {
        uint256 agentId;
        address requester;
        bytes payload;
        uint8 subcommitteeSize;
        uint8 threshold;
        uint256 deposit;
        uint256 createdAt;
        bool resolved;
    }

    uint256 public deposit_;
    uint256 public nextId = 1;
    mapping(uint256 => Pending) public pending;

    constructor(uint256 depositFloor) {
        deposit_ = depositFloor;
    }

    function setDepositFloor(uint256 v) external {
        deposit_ = v;
    }

    function getRequestDeposit() external view returns (uint256) {
        return deposit_;
    }

    function createRequest(uint256 agentId, bytes calldata payload)
        external
        payable
        returns (uint256 requestId)
    {
        requestId = nextId++;
        pending[requestId] = Pending({
            agentId: agentId,
            requester: msg.sender,
            payload: payload,
            subcommitteeSize: 3,
            threshold: 2,
            deposit: msg.value,
            createdAt: block.timestamp,
            resolved: false
        });
    }

    function createAdvancedRequest(
        uint256 agentId,
        bytes calldata payload,
        uint8 subcommitteeSize,
        uint8 threshold
    ) external payable returns (uint256 requestId) {
        requestId = nextId++;
        pending[requestId] = Pending({
            agentId: agentId,
            requester: msg.sender,
            payload: payload,
            subcommitteeSize: subcommitteeSize,
            threshold: threshold,
            deposit: msg.value,
            createdAt: block.timestamp,
            resolved: false
        });
    }

    /// @notice Simulate consensus and call back into the requester.
    function fulfil(uint256 requestId, bytes memory result, ResponseStatus status) external {
        Pending storage p = pending[requestId];
        require(!p.resolved, "already resolved");
        require(p.requester != address(0), "unknown request");
        p.resolved = true;

        Response[] memory responses = new Response[](p.subcommitteeSize);
        for (uint256 i = 0; i < p.subcommitteeSize; ++i) {
            responses[i] = Response({validator: address(uint160(0xA000 + i)), result: result, timestamp: block.timestamp});
        }

        Request memory details = Request({
            agentId: p.agentId,
            requester: p.requester,
            payload: p.payload,
            subcommitteeSize: p.subcommitteeSize,
            threshold: p.threshold,
            deposit: p.deposit,
            createdAt: p.createdAt
        });

        IAgentResponder(p.requester).handleResponse(requestId, responses, status, details);
    }

    receive() external payable {}
}
