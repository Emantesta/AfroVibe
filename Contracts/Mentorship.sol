// Skill-sharing marketplace; 40-90% mentorship fees
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./NFT.sol";

contract Mentorship {
    IERC20 public usdc;
    NFT public nft;
    struct Session {
        address mentor;
        uint256 price;
        bool booked;
    }
    mapping(uint256 => Session) public sessions;

    event SessionBooked(uint256 sessionId, address mentee, uint256 price);

    constructor(address _usdc, address _nft) {
        usdc = IERC20(_usdc);
        nft = NFT(_nft);
    }

    function createSession(uint256 sessionId, uint256 price) external {
        sessions[sessionId] = Session(msg.sender, price, false);
    }

    function bookSession(uint256 sessionId) external {
        Session storage session = sessions[sessionId];
        require(!session.booked, "Session booked");
        usdc.transferFrom(msg.sender, address(this), session.price);
        usdc.transfer(session.mentor, session.price * 85 / 100); // 15% fee
        session.booked = true;
        nft.mint(msg.sender, "Certification_NFT");
        emit SessionBooked(sessionId, msg.sender, session.price);
    }
}
