// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Response, ResponseStatus, Request} from "./IAgentRequester.sol";

/// @notice Callback interface implemented by any contract that invokes a Somnia Agent.
interface IAgentResponder {
    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata details
    ) external;
}
