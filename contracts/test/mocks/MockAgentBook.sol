// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Test double for the World AgentBook registry.
///      Deployed (etched) at the AGENT_BOOK constant address in BaseTest.
///      Call setRegistered(agent, true) to simulate a human-backed agent.
contract MockAgentBook {
    mapping(address => uint256) private _humanIds;

    /// @notice Mirrors IAgentBook.lookupHuman — returns 0 if not registered.
    function lookupHuman(address agent) external view returns (uint256) {
        return _humanIds[agent];
    }

    /// @notice Toggle an address as a registered human-backed agent.
    ///         humanId=1 means registered; 0 means not registered.
    function setRegistered(address agent, bool registered) external {
        _humanIds[agent] = registered ? 1 : 0;
    }
}
