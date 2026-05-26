// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";

/// @title Governor
/// @notice Minimal timelocked executor — queues a target+calldata, waits `delay`, then executes.
contract Governor {
    struct Op {
        address target;
        uint256 value;
        bytes data;
        uint64 eta;
        bool executed;
        bool cancelled;
    }

    address public admin;
    uint64 public delay;
    uint256 public nextOpId = 1;
    mapping(uint256 => Op) public ops;

    event OpQueued(uint256 indexed id, address target, uint256 value, bytes data, uint64 eta);
    event OpExecuted(uint256 indexed id);
    event OpCancelled(uint256 indexed id);
    event AdminTransferred(address indexed previous, address indexed next);
    event DelayChanged(uint64 previous, uint64 next);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Errors.NotGovernor();
        _;
    }

    constructor(address admin_, uint64 delay_) {
        if (admin_ == address(0)) revert Errors.ZeroAddress();
        admin = admin_;
        delay = delay_;
    }

    function setAdmin(address a) external onlyAdmin {
        emit AdminTransferred(admin, a);
        admin = a;
    }

    function setDelay(uint64 d) external onlyAdmin {
        emit DelayChanged(delay, d);
        delay = d;
    }

    function queue(address target, uint256 value, bytes calldata data) external onlyAdmin returns (uint256 id) {
        if (target == address(0)) revert Errors.ZeroAddress();
        id = nextOpId++;
        ops[id] = Op({
            target: target,
            value: value,
            data: data,
            eta: uint64(block.timestamp) + delay,
            executed: false,
            cancelled: false
        });
        emit OpQueued(id, target, value, data, ops[id].eta);
    }

    function execute(uint256 id) external payable onlyAdmin returns (bytes memory result) {
        Op storage op = ops[id];
        if (op.target == address(0)) revert Errors.UnknownRequest();
        if (op.executed || op.cancelled) revert Errors.UnknownRequest();
        if (block.timestamp < op.eta) revert Errors.PolicyNotExpired();
        op.executed = true;
        bool ok;
        (ok, result) = op.target.call{value: op.value}(op.data);
        if (!ok) revert Errors.TransferFailed();
        emit OpExecuted(id);
    }

    function cancel(uint256 id) external onlyAdmin {
        Op storage op = ops[id];
        if (op.target == address(0)) revert Errors.UnknownRequest();
        if (op.executed || op.cancelled) revert Errors.UnknownRequest();
        op.cancelled = true;
        emit OpCancelled(id);
    }

    /// @notice Direct passthrough for parameter changes (admin-only, no timelock — for ops not gated by `onlyGovernor` on target).
    function call(address target, uint256 value, bytes calldata data)
        external
        payable
        onlyAdmin
        returns (bytes memory)
    {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) revert Errors.TransferFailed();
        return ret;
    }

    receive() external payable {}
}
