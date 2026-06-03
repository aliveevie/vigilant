// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Response, ResponseStatus, Request} from "./IAgentRequester.sol";

/// @notice Callback shape the Somnia platform invokes on a requester contract.
/// @dev The platform passes the structs as `memory`, not `calldata` — match
///      that exactly or the selector will not register with the platform.
interface IAgentResponder {
    function handleResponse(
        uint256 requestId,
        Response[] memory responses,
        ResponseStatus status,
        Request memory details
    ) external;
}
