contract MockGovernance is IGovernance {
    uint256 public proposalCount;
    function propose(bytes32 descriptionHash) external override returns (uint256) {
        return ++proposalCount;
    }
    function vote(uint256 proposalId, bool support) external override {}
    function execute(uint256 proposalId) external override {}
    function getProposalState(uint256 proposalId) external view override returns (uint8) {
        return 1; // Active
    }
}
