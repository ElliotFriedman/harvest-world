// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal interface for the World AgentBook registry.
/// @dev Deployed on World Chain at 0xA23aB2712eA7BBa896930544C7d6636a96b944dA
interface IAgentBook {
    /// @notice Returns the anonymous human identifier (nullifierHash) bound to `agent`.
    /// @dev Returns 0 if the agent has not registered. Non-zero means the wallet is
    ///      linked to an Orb-verified human via a World ID proof.
    function lookupHuman(address agent) external view returns (uint256);
}
