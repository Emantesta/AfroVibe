// AI-driven fan clubs; 30-90% fan club fees
// AI-powered fan clubs (FanClub.sol) where fans join creator-led communities for exclusive content, live Q&As, and virtual meet-and-greets, paying USDC subscriptions. 
// AI (recommendation.py) curates personalized fan experiences, and top fans earn “Superfan” NFTs with perks (e.g., backstage access).
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./NFT.sol";

contract FanClub {
    IERC20 public usdc;
    NFT public nft;
    struct Club {
        address creator;
        uint256 subscriptionFee;
        uint256 memberCount;
    }
    mapping(uint256 => Club) public clubs;

    event JoinedClub(uint256 clubId, address fan, uint256 fee);

    constructor(address _usdc, address _nft) {
        usdc = IERC20(_usdc);
        nft = NFT(_nft);
    }

    function createClub(uint256 clubId, uint256 subscriptionFee) external {
        clubs[clubId] = Club(msg.sender, subscriptionFee, 0);
    }

    function joinClub(uint256 clubId) external {
        Club storage club = clubs[clubId];
        usdc.transferFrom(msg.sender, address(this), club.subscriptionFee);
        usdc.transfer(club.creator, club.subscriptionFee * 80 / 100); // 20% fee
        club.memberCount++;
        if (club.memberCount % 100 == 0) { // Superfan every 100th member
            nft.mint(msg.sender, "Superfan_NFT");
        }
        emit JoinedClub(clubId, msg.sender, club.subscriptionFee);
    }
}
