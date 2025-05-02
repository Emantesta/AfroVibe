// Crowdfunding for creators/projects; 60-95% crowdfunding funds
// A decentralized crowdfunding platform (Crowdfunding.sol) allowing creators and cultural hubs to raise USDC for projects,
// (e.g., music albums, community events, startups), with backers receiving NFTs or exclusive perks. 
// Users can pledge USDC, and funds are released upon milestones, governed by smart contracts.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./NFT.sol";

contract Crowdfunding {
    IERC20 public usdc;
    NFT public nft;
    struct Campaign {
        address creator;
        uint256 goal;
        uint256 raised;
        bool completed;
    }
    mapping(uint256 => Campaign) public campaigns;

    event CampaignCreated(uint256 campaignId, address creator, uint256 goal);
    event PledgeMade(uint256 campaignId, address backer, uint256 amount);

    constructor(address _usdc, address _nft) {
        usdc = IERC20(_usdc);
        nft = NFT(_nft);
    }

    function createCampaign(uint256 campaignId, uint256 goal) external {
        campaigns[campaignId] = Campaign(msg.sender, goal, 0, false);
        emit CampaignCreated(campaignId, msg.sender, goal);
    }

    function pledge(uint256 campaignId, uint256 amount) external {
        Campaign storage campaign = campaigns[campaignId];
        require(!campaign.completed, "Campaign completed");
        usdc.transferFrom(msg.sender, address(this), amount);
        campaign.raised += amount;
        nft.mint(msg.sender, "Backer_NFT"); // Reward NFT
        emit PledgeMade(campaignId, msg.sender, amount);
        if (campaign.raised >= campaign.goal) {
            usdc.transfer(campaign.creator, campaign.raised * 90 / 100); // 10% fee
            campaign.completed = true;
        }
    }
}
