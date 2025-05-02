// P2P payments and remittances; 60-100% P2P tips/gifts
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Payments {
    IERC20 public usdc;
    event PaymentSent(address sender, address receiver, uint256 amount);

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    function sendPayment(address receiver, uint256 amount) external {
        usdc.transferFrom(msg.sender, address(this), amount);
        usdc.transfer(receiver, amount * 99 / 100); // 1% fee
        emit PaymentSent(msg.sender, receiver, amount);
    }
}
