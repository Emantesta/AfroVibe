// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface INonceManager {
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
    function incrementNonce(uint192 key) external;
}
