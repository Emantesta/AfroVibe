// Virtual events and ticket sales; 30-90% event ticket sales
// Host virtual concerts, cultural festivals, and networking events in a metaverse-like environment (Metaverse.js),
// with USDC ticket sales (Event.sol) and NFT collectibles.
// Users attend via mobile AR/VR or 2D interfaces,
// celebrating Afrobeats, Nollywood, or ethnic festivals (e.g., Durbar).

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./NFT.sol";

contract Event {
    IERC20 public usdc;
    NFT public nft;
    struct VirtualEvent {
        address organizer;
        uint256 ticketPrice;
        uint256 totalTickets;
        uint256 sold;
    }
    mapping(uint256 => VirtualEvent) public events;

    event TicketPurchased(uint256 eventId, address buyer, uint256 nftId);

    constructor(address _usdc, address _nft) {
        usdc = IERC20(_usdc);
        nft = NFT(_nft);
    }

    function createEvent(uint256 eventId, uint256 ticketPrice, uint256 totalTickets) external {
        events[eventId] = VirtualEvent(msg.sender, ticketPrice, totalTickets, 0);
    }

    function buyTicket(uint256 eventId) external {
        VirtualEvent storage evt = events[eventId];
        require(evt.sold < evt.totalTickets, "Sold out");
        usdc.transferFrom(msg.sender, address(this), evt.ticketPrice);
        usdc.transfer(evt.organizer, evt.ticketPrice * 90 / 100); // 10% fee
        evt.sold++;
        uint256 nftId = nft.mint(msg.sender, "Event_NFT");
        emit TicketPurchased(eventId, msg.sender, nftId);
    }
}
