// USDC-to-S token conversion
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Router.sol";

contract SwapHelper {
    address public owner;
    IERC20 public usdc;
    IERC20 public sToken;
    IUniswapV2Router public dexRouter; // Sonic-native DEX (e.g., SonicSwap)

    constructor(address _usdc, address _sToken, address _dexRouter) {
        owner = msg.sender;
        usdc = IERC20(_usdc);
        sToken = IERC20(_sToken);
        dexRouter = IUniswapV2Router(_dexRouter);
    }

    function convertUSDCtoS(uint256 usdcAmount, uint256 minSTokens) external {
        require(msg.sender == owner, "Only owner");
        usdc.approve(address(dexRouter), usdcAmount);
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(sToken);
        dexRouter.swapExactTokensForTokens(
            usdcAmount, // Input USDC
            minSTokens, // Minimum S tokens (slippage protection)
            path,
            address(this), // Recipient
            block.timestamp + 300 // Deadline
        );
    }

    function fundPaymaster(address paymaster, uint256 sTokenAmount) external {
        require(msg.sender == owner, "Only owner");
        sToken.transfer(paymaster, sTokenAmount);
    }
}
