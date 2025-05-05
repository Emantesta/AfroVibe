// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./AfroVibePaymaster.sol";

contract PaymasterFunder is AccessControl {
    bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");
    AfroVibePaymaster public immutable paymaster;
    uint256 public maxFundingAmount; // Max ETH to fund per upkeep

    event Funded(address indexed paymaster, uint256 amount);

    constructor(address _paymaster, address _admin, uint256 _maxFundingAmount) {
        require(_paymaster != address(0), "Invalid paymaster");
        require(_admin != address(0), "Invalid admin");
        require(_maxFundingAmount > 0, "Invalid funding amount");
        paymaster = AfroVibePaymaster(_paymaster);
        maxFundingAmount = _maxFundingAmount;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(FUNDER_ROLE, _admin);
    }

    // Fund the paymaster
    function fund(uint256 amount) external onlyRole(FUNDER_ROLE) {
        require(amount <= maxFundingAmount, "Exceeds max funding");
        require(amount <= address(this).balance, "Insufficient balance");
        paymaster.deposit{value: amount}();
        emit Funded(address(paymaster), amount);
    }

    // Update max funding amount
    function updateMaxFundingAmount(uint256 newAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAmount > 0, "Invalid amount");
        maxFundingAmount = newAmount;
    }

    // Receive ETH
    receive() external payable {}

    // Emergency withdraw
    function emergencyWithdraw(address payable to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Withdraw failed");
    }
}
