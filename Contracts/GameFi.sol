// Play-to-earn mini-games; 33.33-80% in-game rewards
// Users earn Sonic native USDC, a stablecoin pegged to the US dollar, for completing game tasks (e.g., finding AR collectibles, answering quiz questions).
// Users receive non-fungible tokens (NFTs) via NFT.sol, representing unique in-game items (e.g., AR filter designs, virtual Afrobeats concert tickets, or collectible avatars).

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./NFT.sol";

contract GameFi {
    IERC20 public usdc;
    NFT public nft;
    mapping(address => uint256) public userPoints;

    event RewardDistributed(address user, uint256 usdcAmount, uint256 nftId);

    constructor(address _usdc, address _nft) {
        usdc = IERC20(_usdc);
        nft = NFT(_nft);
    }

    function completeTask(address user, uint256 taskId, uint256 points) external {
        require(isValidTask(taskId), "Invalid task");
        userPoints[user] += points;
        if (points >= 100) { // Example threshold
            usdc.transfer(user, 0.1 * 10**6); // $0.10 USDC (6 decimals)
            uint256 nftId = nft.mint(user, "AR_Collectible");
            emit RewardDistributed(user, 0.1 * 10**6, nftId);
        }
    }
}
