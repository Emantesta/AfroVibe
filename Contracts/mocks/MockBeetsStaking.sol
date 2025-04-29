contract MockBeetsStaking is IBeetsStaking {
    mapping(address => uint256) public rewards;
    function stake(address user, uint256 amount) external override {}
    function withdraw(address user, uint256 amount) external override {}
    function getReward(address user) external override returns (uint256) {
        uint256 reward = rewards[user];
        rewards[user] = 0;
        return reward;
    }
    function balanceOf(address user) external view override returns (uint256) {
        return 0;
    }
    function setReward(address user, uint256 amount) external {
        rewards[user] = amount;
    }
}
