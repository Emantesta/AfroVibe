// Contact Sonic’s team or check their documentation (e.g., docs.sonic.network) for the exact interface.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISonicGateway
 * @dev Interface for Sonic network cross-chain bridging.
 */
interface ISonicGateway {
    /**
     * @dev Initiates a cross-chain bridge of tokens.
     * @param token The token address to bridge.
     * @param amount The amount of tokens to bridge.
     * @param recipient The recipient address on the destination chain.
     * @param toEthereum True if bridging to Ethereum, false if to Sonic.
     */
    function bridge(address token, uint256 amount, address recipient, bool toEthereum) external;

    /**
     * @dev Receives tokens on the destination chain.
     * @param token The token address.
     * @param amount The amount of tokens received.
     * @param recipient The recipient address.
     */
    function receiveTokens(address token, uint256 amount, address recipient) external;

    /**
     * @dev Sets bridging limits.
     * @param maxAmount The maximum bridgeable amount.
     * @param userLimit The per-user bridging limit.
     */
    function setBridgeLimits(uint256 maxAmount, uint256 userLimit) external;

    /**
     * @dev Checks if bridging is paused.
     * @return True if paused, false otherwise.
     */
    function isBridgingPaused() external view returns (bool);
}
