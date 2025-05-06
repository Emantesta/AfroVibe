// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IStakeManager {
    struct StakeInfo {
        uint256 stake;
        uint256 unstakeDelaySec;
        uint256 withdrawTime;
        uint256 deposit;
    }

    function depositTo(address account) external payable;
    function withdrawTo(address payable withdrawAddress, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function addStake(uint32 unstakeDelaySec) external payable;
    function unlockStake() external;
    function withdrawStake(address payable withdrawAddress) external;
    function getDepositInfo(address account) external view returns (StakeInfo memory);
}
