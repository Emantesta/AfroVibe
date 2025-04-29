contract MockSonicGateway is ISonicGateway {
    function bridge(address token, uint256 amount, address recipient, bool toEthereum) external override {}
    function receiveTokens(address token, uint256 amount, address recipient) external override {}
    function setBridgeLimits(uint256 maxAmount, uint256 userLimit) external override {}
    function isBridgingPaused() external view override returns (bool) {
        return false;
    }
}
