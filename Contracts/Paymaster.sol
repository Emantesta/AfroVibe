// Gas sponsorship for USDC transactions
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Paymaster {
    address public owner;
    IERC20 public sToken;

    constructor(address _sToken) {
        owner = msg.sender;
        sToken = IERC20(_sToken);
    }

    function validatePaymasterUserOp(UserOperation calldata userOp, uint256 maxCost) external returns (bool) {
        // Validate UserOperation and sponsor gas with S tokens
        require(sToken.balanceOf(address(this)) >= maxCost, "Insufficient S tokens");
        return true;
    }

    function fundPaymaster(uint256 amount) external {
        // Fund Paymaster with S tokens from treasury
        require(msg.sender == owner, "Only owner");
        sToken.transferFrom(msg.sender, address(this), amount);
    }
}
