// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IAgentRequester,
    ConsensusType,
    Response,
    ResponseStatus,
    Request
} from "../../src/interfaces/IAgentRequester.sol";

/// @notice Mock Somnia Agents platform that mirrors the real interface.
/// @dev Records each request with its (callbackAddress, callbackSelector); a
///      test driver dispatches a forged consensus response by raw-call to the
///      stored selector — same shape the real platform uses.
contract MockAgentPlatform is IAgentRequester {
    struct Pending {
        uint256 agentId;
        address requester;
        address callbackAddress;
        bytes4 callbackSelector;
        bytes payload;
        uint256 subcommitteeSize;
        uint256 threshold;
        ConsensusType consensusType;
        uint256 deposit;
        uint256 perAgentBudget;
        uint256 createdAt;
        uint256 deadline;
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

    function getAdvancedRequestDeposit(uint256 /*subcommitteeSize*/)
        external
        view
        returns (uint256)
    {
        return deposit_;
    }

    function hasRequest(uint256 id) external view returns (bool) {
        return pending[id].requester != address(0);
    }

    function getRequest(uint256 id) external view returns (Request memory r) {
        Pending storage p = pending[id];
        r.id = id;
        r.requester = p.requester;
        r.callbackAddress = p.callbackAddress;
        r.callbackSelector = p.callbackSelector;
        r.threshold = p.threshold;
        r.createdAt = p.createdAt;
        r.deadline = p.deadline;
        r.consensusType = p.consensusType;
        r.remainingBudget = p.deposit;
        r.perAgentBudget = p.perAgentBudget;
    }

    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable returns (uint256 requestId) {
        requestId = nextId++;
        pending[requestId] = Pending({
            agentId: agentId,
            requester: msg.sender,
            callbackAddress: callbackAddress,
            callbackSelector: callbackSelector,
            payload: payload,
            subcommitteeSize: 3,
            threshold: 2,
            consensusType: ConsensusType.Majority,
            deposit: msg.value,
            perAgentBudget: msg.value / 3,
            createdAt: block.timestamp,
            deadline: block.timestamp + 1 hours,
            resolved: false
        });
    }

    function createAdvancedRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload,
        uint256 subcommitteeSize,
        uint256 threshold,
        ConsensusType consensusType,
        uint256 timeout
    ) external payable returns (uint256 requestId) {
        requestId = nextId++;
        pending[requestId] = Pending({
            agentId: agentId,
            requester: msg.sender,
            callbackAddress: callbackAddress,
            callbackSelector: callbackSelector,
            payload: payload,
            subcommitteeSize: subcommitteeSize,
            threshold: threshold,
            consensusType: consensusType,
            deposit: msg.value,
            perAgentBudget: subcommitteeSize == 0 ? 0 : msg.value / subcommitteeSize,
            createdAt: block.timestamp,
            deadline: block.timestamp + timeout,
            resolved: false
        });
    }

    /// @notice Simulate consensus and call back into the requester via the
    ///         stored callback selector. `result` is the raw bytes the agent
    ///         returns (e.g. `abi.encode(int256(score))` or `abi.encode("Exploit")`).
    function fulfil(uint256 requestId, bytes memory result, ResponseStatus status) external {
        Pending storage p = pending[requestId];
        require(!p.resolved, "already resolved");
        require(p.callbackAddress != address(0), "unknown request");
        p.resolved = true;

        Response[] memory responses = new Response[](p.subcommitteeSize);
        for (uint256 i = 0; i < p.subcommitteeSize; ++i) {
            responses[i] = Response({
                validator: address(uint160(0xA000 + i)),
                result: result,
                status: status,
                receipt: uint256(keccak256(abi.encode(requestId, i))),
                timestamp: block.timestamp,
                executionCost: 0
            });
        }

        address[] memory subcommittee = new address[](p.subcommitteeSize);
        for (uint256 i = 0; i < p.subcommitteeSize; ++i) {
            subcommittee[i] = address(uint160(0xA000 + i));
        }

        Request memory details = Request({
            id: requestId,
            requester: p.requester,
            callbackAddress: p.callbackAddress,
            callbackSelector: p.callbackSelector,
            subcommittee: subcommittee,
            responses: responses,
            responseCount: p.subcommitteeSize,
            failureCount: 0,
            threshold: p.threshold,
            createdAt: p.createdAt,
            deadline: p.deadline,
            status: status,
            consensusType: p.consensusType,
            remainingBudget: 0,
            perAgentBudget: p.perAgentBudget
        });

        (bool ok, bytes memory data) = p.callbackAddress.call(
            abi.encodeWithSelector(p.callbackSelector, requestId, responses, status, details)
        );
        if (!ok) {
            assembly {
                revert(add(data, 0x20), mload(data))
            }
        }
    }

    receive() external payable {}
}
