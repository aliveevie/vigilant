// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Numeric agentIds of the Phase-1 base agents on the Somnia Agents
///         platform. Discovered from https://agents.testnet.somnia.network.
library AgentIds {
    /// @dev LLM Inference base agent (deterministic on-chain Qwen3-30B).
    uint256 internal constant LLM_INFERENCE_ID = 12847293847561029384;
    /// @dev LLM Parse Website base agent.
    uint256 internal constant LLM_PARSE_WEBSITE_ID = 12875401142070969085;
    /// @dev JSON API Request base agent.
    uint256 internal constant JSON_API_REQUEST_ID = 13174292974160097713;
}

/// @notice Per-agent reward costs (paid to each subcommittee member, default size = 3).
library AgentPricing {
    uint256 internal constant DEFAULT_SUBCOMMITTEE_SIZE = 3;
    uint256 internal constant LLM_INFERENCE_COST_PER_AGENT = 0.07 ether;
    uint256 internal constant LLM_PARSE_WEBSITE_COST_PER_AGENT = 0.10 ether;
    uint256 internal constant JSON_API_REQUEST_COST_PER_AGENT = 0.03 ether;
}

/// @notice ABI of the LLM Inference base agent. Encode a call with
///         `abi.encodeCall(ILLMInference.inferX, (...))` and pass it as
///         the `payload` argument to `IAgentRequester.createRequest`.
interface ILLMInference {
    /// @notice Deterministic string completion. If `allowedValues` is non-empty
    ///         the response is constrained to one of those literal strings.
    function inferString(
        string calldata prompt,
        string calldata system,
        bool chainOfThought,
        string[] calldata allowedValues
    ) external returns (string memory response);

    /// @notice Deterministic integer in [minValue, maxValue].
    function inferNumber(
        string calldata prompt,
        string calldata system,
        int256 minValue,
        int256 maxValue,
        bool chainOfThought
    ) external returns (int256 response);
}
