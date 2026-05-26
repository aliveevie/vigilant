// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAgentRequester} from "../interfaces/IAgentRequester.sol";
import {IAgentResponder} from "../interfaces/IAgentResponder.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";

/// @notice Base for any contract that invokes a Somnia Agent.
///         Handles platform-msg-sender check, circuit breaker, deposit math, and rebate routing.
abstract contract AgentClient is IAgentResponder {
    IAgentRequester public immutable platform;
    address public immutable governor;

    // Circuit breaker — counts Failed/TimedOut in the recent window.
    uint8 public failureCount;
    uint8 public openThreshold;
    uint8 public resetThreshold;
    bool public circuitOpen;

    uint256 public protocolReserve;

    modifier onlyPlatform() {
        if (msg.sender != address(platform)) revert Errors.NotPlatform();
        _;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) revert Errors.NotGovernor();
        _;
    }

    modifier whenCircuitClosed() {
        if (circuitOpen) revert Errors.CircuitOpen();
        _;
    }

    constructor(address platform_, address governor_, uint8 openThreshold_, uint8 resetThreshold_) {
        if (platform_ == address(0) || governor_ == address(0)) revert Errors.ZeroAddress();
        platform = IAgentRequester(platform_);
        governor = governor_;
        openThreshold = openThreshold_;
        resetThreshold = resetThreshold_;
    }

    function _onFailure() internal {
        unchecked {
            if (failureCount < type(uint8).max) failureCount += 1;
        }
        if (!circuitOpen && failureCount >= openThreshold) {
            circuitOpen = true;
            emit Events.CircuitTripped(_circuitTag());
        }
    }

    function _onSuccess() internal {
        if (failureCount > 0) failureCount -= 1;
        if (circuitOpen && failureCount + resetThreshold <= openThreshold) {
            circuitOpen = false;
            emit Events.CircuitReset(_circuitTag());
        }
    }

    function setCircuitThresholds(uint8 openThreshold_, uint8 resetThreshold_)
        external
        onlyGovernor
    {
        openThreshold = openThreshold_;
        resetThreshold = resetThreshold_;
    }

    function manualResetCircuit() external onlyGovernor {
        circuitOpen = false;
        failureCount = 0;
        emit Events.CircuitReset(_circuitTag());
    }

    function _circuitTag() internal pure virtual returns (string memory);

    /// @notice Compute the required deposit for an agent invocation.
    function _quoteDeposit(uint8 subcommitteeSize, uint256 perAgentBudget)
        internal
        view
        returns (uint256)
    {
        return platform.getRequestDeposit() + perAgentBudget * uint256(subcommitteeSize);
    }

    receive() external payable virtual {
        // Platform rebates flow here.
        protocolReserve += msg.value;
    }
}
