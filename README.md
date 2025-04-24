# AfroVibe - Decentralized Social Media Platform on Sonic Blockchain

AfroVibe is a creator-centric, Web3 social media platform built on the Sonic Blockchain, empowering users to connect, create, and monetize through decentralized tools. With features like creator subscriptions, premium content, gamification, AR filters, and community governance, AfroVibe redefines social networking with privacy, transparency, and user ownership at its core.

## Features

- **Creator Subscriptions**: Monetize exclusive content through tiered subscriptions, offering private posts, live streams, and personalized fan interactions.
- **Premium Content**: Share restricted or pay-per-view (PPV) content, secured with privacy controls and age verification for eligible subscribers.
- **Gamification**: Engage users with points, badges, leaderboards, and prizes for actions like posting, commenting, and tipping.
- **AR Filters**: Create and sell AI-generated augmented reality filters as NFTs, enhancing content creation.
- **Decentralized Ads**: Opt-in ads with revenue sharing, managed on-chain for transparency.
- **Private Messaging**: End-to-end encrypted chats and paid custom content requests.
- **Cross-Platform Sharing**: Post to X, Instagram, YouTube, TikTok, and LinkedIn from one interface.
- **Community Governance**: Vote on platform policies using a decentralized DAO structure.
- **Robust Moderation**: AI-driven content moderation and community reporting ensure a safe environment.
- **Accessibility**: Offline caching, text-to-speech, high-contrast themes, and multilingual voice commands.
- **Web3 Integration**: Seamless wallet logins (MetaMask, Phantom, TrustWallet, Rabby) and NFT marketplaces.

## Project Structure

afrovibe-platform/
├── contracts/               # Solidity smart contracts for blockchain logic
├── src/                     # Web frontend (React)
├── mobile/                  # Mobile app (React Native)
├── backend/                 # GraphQL server and The Graph subgraph
├── streaming-server/        # Live streaming server
├── storage/                 # IPFS and Arweave integration
├── recommendation.py        # AI-based content moderation and recommendations
├── README.md                # This file



### Key Components

- **Smart Contracts** (`contracts/`):
  - `UserProfile.sol`: User profiles, Web3 logins, verification badges.
  - `Content.sol`: Posts, streams, restricted, and PPV content.
  - `Subscription.sol`: Creator subscriptions and tiered access.
  - `AgeVerification.sol`: Self-attestation for restricted content access.
  - `Marketplace.sol`: PPV, tipping, NFT trading.
  - `Governance.sol`: Community voting on policies.

- **Frontend** (`src/components/`, `mobile/components/`):
  - `Subscription.js`: Manage and subscribe to creator tiers.
  - `PPVContent.js`: Purchase pay-per-view content.
  - `AgeVerification.js`: Verify eligibility for premium content.
  - `GamificationConfig.js`: Configure points, badges, and levels.
  - `ARMarketplace.js`: Create and trade AR filter NFTs.

- **Backend** (`backend/`):
  - GraphQL server and subgraph for indexing blockchain events.

- **AI Moderation** (`recommendation.py`):
  - Content moderation with NSFW detection and personalized recommendations.

## Prerequisites

- **Node.js** (>= 16.x)
- **Python** (>= 3.8) for `recommendation.py`
- **Hardhat** or **Foundry** for smart contract development
- **IPFS** and **Arweave** nodes or APIs for decentralized storage
- **Sonic Blockchain** testnet/mainnet access
- **MetaMask** or compatible Web3 wallet

## Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/your-org/afrovibe-platform.git
   cd afrovibe-platform

   Install Dependencies
   npm install
   cd mobile && npm install
   cd ../backend && npm install
   cd ../streaming-server && npm install


Set Up Environment Variables:
Create a .env file in the root and streaming-server/ directories:
# Root .env
SONIC_RPC_URL=https://rpc.sonic.network
IPFS_API_KEY=your-ipfs-key
ARWEAVE_KEY=your-arweave-key
GRAPHQL_ENDPOINT=http://localhost:4000/graphql

# streaming-server/.env
STREAMING_PORT=8080

Compile and Deploy Smart Contracts:
cd contracts
npx hardhat compile
npx hardhat deploy --network sonic

Run the Backend:
cd backend
npm run start

Run the Streaming Server:
cd streaming-server
npm run start

Run the Web Frontend:
cd src
npm run start

Run the Mobile App:
cd mobile
npm run ios  # or npm run android

Set Up AI Moderation:
  Install Python dependencies:
    pip install -r requirements.txt
  
  Run the moderation script:
    python recommendation.py

Usage
Connect Wallet: Use MetaMask or another Web3 wallet to log in via UserProfile.sol.

Create Content: Post, stream, or share to external platforms using CreatePost.js or PostCreation.js.

Monetize: Set up subscription tiers (Subscription.js), sell PPV content (PPVContent.js), or create AR filters (ARMarketplace.js).

Engage: Earn points and badges (GamificationConfig.js), join communities (GroupChat.js), or vote on policies (Governance.js).

Access Premium Content: Subscribe to creators or purchase PPV content, verifying eligibility if required (AgeVerification.js).

Contact
GitHub: Emantest/afrovibe-platform

Email: support@afrovibe.io

Community: Join our Discord or X community


    

  
