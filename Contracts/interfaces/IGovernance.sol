// Check AfroVibe’s governance contract for additional methods if needed.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IGovernance
 * @dev Interface for governance contract, handling proposal creation and voting.
 */
interface IGovernance {
    /**
     * @dev Creates a new governance proposal.
     * @param descriptionHash The hash of the proposal description.
     * @return proposalId The ID of the created proposal.
     */
    function propose(bytes32 descriptionHash) external returns (uint256 proposalId);

    /**
     * @dev Casts a vote on a proposal.
     * @param proposalId The ID of the proposal.
     * @param support Whether the vote supports the proposal (true) or opposes (false).
     */
    function vote(uint256 proposalId, bool support) external;

    /**
     * @dev Executes an approved proposal.
     * @param proposalId The ID of the proposal.
     */
    function execute(uint256 proposalId) external;

    /**
     * @dev Queries the state of a proposal.
     * @param proposalId The ID of the proposal.
     * @return The state (e.g., 0=Pending, 1=Active, 2=Succeeded, etc.).
     */
    function getProposalState(uint256 proposalId) external view returns (uint8);
}
