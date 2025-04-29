// If AfroVibe uses a specific Beets contract, replace with the actual interface from Beets’ documentation or GitHub (e.g., beethovenxio/beethovenx).

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBeetsStaking
 * @dev Interface for Beets staking contract integration, handling external staking and reward operations.
 */
interface IBeetsStaking {
    /**
     * @dev Stakes tokens for a user in the Beets protocol.
     * @param user The address of the user staking tokens.
     * @param amount The amount of tokens to stake.
     */
    function stake(address user, uint256 amount) external;

    /**
     * @dev Withdraws staked tokens for a user.
     * @param user The address of the user withdrawing tokens.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(address user, uint256 amount) external;

    /**
     * @dev Retrieves the pending rewards for a user.
     * @param user The address of the user.
     * @return The amount of rewards available.
     */
    function getReward(address user) external returns (uint256);

    /**
     * @dev Queries the staked balance of a user.
     * @param user The address of the user.
     * @return The staked balance.
     */
    function balanceOf(address user) external view returns (uint256);
}
