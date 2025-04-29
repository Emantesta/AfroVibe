contract MockSonicValidator is ISonicValidator {
    function delegate(address user, uint256 amount) external override {}
    function undelegate(address user, uint256 amount) external override {}
    function getValidatorInfo(address validator) external view override returns (uint256 stake, uint256 rewards) {
        return (0, 0);
    }
    function maxDelegation() external view override returns (uint256) {
        return 1_000_000 ether;
    }
}
