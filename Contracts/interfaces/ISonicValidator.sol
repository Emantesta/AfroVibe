// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISonicValidator
 * @dev Interface for Sonic network validator delegation.
 */
interface ISonicValidator {
    /**
     * @dev Delegates tokens to a validator.
     * @param user The address of the user delegating.
     * @param amount The amount of tokens to delegate.
     */
    function delegate(address user, uint256 amount) external;

    /**
     * @dev Undelegates tokens from a validator.
     * @param user The address of the user undelegating.
     * @param amount The amount of tokens to undelegate.
     */
    function undelegate(address user, uint256 amount) external;

    /**
     * @dev Queries validator information.
     * @param validator The validator address.
     * @return stake The total staked amount, rewards The accumulated rewards.
     */
    function getValidatorInfo(address validator) external view returns (uint256 stake, uint256 rewards);

    /**
     * @dev Returns the maximum delegation limit.
     * @return The maximum delegable amount.
     */
    function maxDelegation() external view returns (uint256);
}
