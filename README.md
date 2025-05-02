# AfroVibe - Decentralized Social Media Platform on Sonic Blockchain

AfroVibe is a Web3 social media platform built on the Sonic Blockchain, empowering creators and communities with decentralized tools for connection, monetization, and cultural expression. Designed for Nigeria’s vibrant digital landscape and global audiences, AfroVibe offers creator subscriptions, decentralized music streaming, social commerce, GameFi, offline access, cultural hubs, and community governance, all powered by Sonic native USDC for stable, inclusive transactions.

## Features

- **Creator Subscriptions**: Monetize exclusive content via tiered subscriptions, including private posts, live streams, and personalized interactions, paid in USDC.
- **Decentralized Music Streaming**: Artists upload tracks, earn USDC per stream, and release NFT-based limited editions, celebrating Nigeria’s Afrobeats culture.
- **Social Commerce Marketplace**: Sell products through shoppable posts and profiles, with USDC payments and fiat-to-crypto on-ramps for accessibility.
- **GameFi Rewards**: Earn USDC and NFTs through play-to-earn mini-games, like AR scavenger hunts and cultural quizzes.
- **Fan Clubs**: AI-driven fan experiences with USDC subscriptions (`FanClub.sol`).
- **Offline-First Sync**: Create and consume content offline, syncing when connected, ideal for Nigeria’s connectivity challenges.
- **Cultural Hubs**: Join communities celebrating Nigeria’s ethnic diversity (e.g., Yoruba, Igbo) and global diaspora, with curated feeds and events.
- **Virtual Events**: Metaverse concerts with USDC tickets (`Event.sol`).
- **Artist DAOs**: Fans join artist-led DAOs to fund projects and vote on decisions, fostering engagement.
- **Platform DAO**: Users vote on platform policies, reinforcing Web3 ownership.
- **Local Payments**: Buy USDC using mobile money (e.g., MTN MoMo, Flutterwave), inclusive for unbanked users; Fiat-to-USDC via Onramper (MTN MoMo, Flutterwave) (`MobilePayment.js`).
- **AI Personalization**: Tailored feeds and music recommendations via AI, with robust content moderation; NSFW, music, commerce, fan club recommendations (`recommendation.py`).
- **Music Streaming**: 8-90% of revenue (`MusicStreaming.sol`).
- **Age Verification**: Self-attestation for restricted content (`AgeVerification.sol`).
- **Gamification**: Earn points, badges, and USDC rewards for engagement.
- **Frontend**: React Native (`mobile/`), feature-phone optimized.
- **Backend**: GraphQL (`schema.graphql`), Node.js (`backend/server.js`).
- **AI**: Python-based recommendations (`recommendation.py`).
- **Mentorship Marketplace**: Skill-sharing with USDC payments (`Mentorship.sol`).
- **Streaming**: Low-latency server for events (`streaming-server/`).
- **P2P Payments**: USDC remittances and transfers (`Payments.sol`).
- **Blockchain**: Sonic Blockchain (10,000 TPS, EVM-compatible).
- **Engagement Rewards**: USDC for likes/comments (`Reward.sol`).
- **Voice Interaction**: Multilingual voice commands (`VoiceInteraction.js`).
- **Referrals**: 10% of referred creators’ revenue (`ReferralProgram.sol`).
- **Curation**: USDC bounties for trending posts (`Reward.sol`).
- **AR Filters**: Create and sell AI-generated augmented reality filters as NFTs.
- **Decentralized Ads**: Opt-in ads with USDC revenue sharing.
- **Crowdfunding**: USDC funding for creators/projects (`Crowdfunding.sol`).
- **Private Messaging**: End-to-end encrypted chats and paid content requests.
- **Cross-Platform Sharing**: Post to X, Instagram, YouTube, TikTok, and LinkedIn.
- **Accessibility**: Offline caching, text-to-speech, high-contrast themes, multilingual voice commands.
- **Web3 Integration**: Wallet logins (MetaMask, Phantom, TrustWallet, Rabby) and NFT marketplaces.
- **Low-bandwidth streaming**: (`StreamView.js`).
- **Privacy Controls**: Post/profile/message privacy (`PrivacySettings.sol`).

## External Contracts
- **IBeetsStaking**: Manages staking operations (see `contracts/interfaces/IBeetsStaking.sol`).
- **IGovernance**: Handles proposals and voting (OpenZeppelin or custom).
- **ISonicGateway**: Enables cross-chain bridging (custom for Sonic).
- **ISonicValidator**: Manages validator delegation (custom for Sonic).
- **TimelockControllerUpgradeable**: Enforces governance timelocks (OpenZeppelin). 

- **Staking contract**: The Staking contract is a secure, upgradeable smart contract optimized for the Sonic network, enabling users to stake S tokens, earn 
  Afrovibe rewards, participate in validator delegation, bridge tokens cross-chain, and engage in governance. Built with OpenZeppelin's upgradeable contracts, 
  it supports ERC-4337 account abstraction, a multi-step upgrade process, and robust security features. The contract is designed for scalability, gas 
  efficiency, and flexibility in a decentralized staking ecosystem.
- **Staking Key Features**:
- **Staking and Unstaking**: Stake S tokens for 1–365 days, earn Afrovibe rewards (5% default APY), and unstake with penalties for early withdrawal (10% 
  default).
- **Sonic Points**: Earn points (1 per 1e18 S tokens staked, max 1M) redeemable for fee discounts (1% per 1000 points) with a 1-year expiry.
- **Validator Delegation**: Delegate staked tokens to multiple Sonic validators with per-validator limits to earn additional rewards.
- **Cross-Chain Bridging**: Bridge S tokens to/from Ethereum via ISonicGateway with per-transaction and per-user limits.
- **Governance**: Participate in proposals with Merkle proof verification and voting power snapshots, decaying at 0.1% per day.
- **Reward System**: Claim Afrovibe, validator, and Beets rewards with a dynamic reserve threshold and 1-day claim cooldown.
- **ERC-4337 Support**: Gasless transactions via trusted paymasters with minimum reliability scores.
- **Security**: Uses ReentrancyGuard, Pausable, AccessControl, and a multi-step UUPS upgrade process with timelock.
- **Gas Optimization**: Cumulative reward index, packed Stake struct, and consolidated batch events reduce gas costs.

- **Staking.sol**: Supports staking, Sonic Points, bridging, delegation, governance, and upgrades using `TimelockControllerUpgradeable` and `MerkleProof`.

### Mobile Components
- **Staking.js**: Handles all contract interactions, including voter verification (`verifyProposalVoter`) and upgrade proposals (`proposeUpgrade`, `confirmUpgrade`).
- **AnalyticsDashboard.js**: Displays stakes, delegations, proposals, and upgrade proposals with timelock status.

### Backend Components
- **subgraph.yaml, schema.graphql, mapping.ts**: Indexes all events, including `ProposalVerified` and `UpgradeProposalCreated`.
- **rewardCalculator.js**: Calculates rewards and tracks governance participation.

### Setup
1. Install dependencies:
   ```bash
   npm install ethers graphql-request graphql react-native @openzeppelin/contracts@4.9.3 @openzeppelin/contracts-upgradeable@4.9.3

- **Prerequisites**
- Solidity Version: ^0.8.20
- **Dependencies**:
- **OpenZeppelin Contracts Upgradeable (@openzeppelin/contracts-upgradeable@4.9.3)
- Hardhat or Foundry for development and testing
- Node.js and npm for package management
- **Network**: Deployable on Sonic network or Ethereum-compatible chains
- **External Contracts**:
- **IBeetsStaking**: For staking operations
- **IGovernance**: For proposal and voting
- **ISonicGateway**: For cross-chain bridging
- **ISonicValidator**: For validator delegation
- **TimelockControllerUpgradeable**: For governance timelocks

## Project Structure

afrovibe-platform/
├── contracts/               # Solidity smart contracts
├── src/                     # Web frontend (React)
├── mobile/                  # Mobile app (React Native)
├── backend/                 # GraphQL server and The Graph subgraph
├── streaming-server/        # Live streaming server
├── storage/                 # IPFS and Arweave integration
├── recommendation.py        # AI moderation and recommendations
├── README.md                # This file


afrovibe-platform/
├── contracts/
│   ├── UserProfile.sol              # Updated: Smart wallet integration
│   ├── Content.sol                  # Restricted, PPV, queued content, music
│   ├── Messaging.sol                # Custom content requests, encryption
│   ├── Reward.sol                   # Rewards for subscriptions, GameFi, music
│   ├── Marketplace.sol              # Updated: USDC payments, smart wallet support
│   ├── PrivacySettings.sol          # Privacy for posts, profiles, messages
│   ├── NFT.sol                      # NFTs for posts, filters, music, GameFi
│   ├── Subscription.sol             # Updated: USDC subscriptions, smart wallets
│   ├── AdManager.sol                # Decentralized opt-in ads
│   ├── Governance.sol               # Platform-wide governance
│   ├── AgeVerification.sol          # Self-attestation for restricted content
│   ├── GroupChat.sol                # Cultural hubs, communities
│   ├── Commerce.sol                 # Social commerce marketplace
│   ├── GameFi.sol                   # Play-to-earn mini-games
│   ├── MusicStreaming.sol           # Decentralized music streaming, NFT releases
│   ├── ArtistDAO.sol                # Artist DAOs for fan engagement
│   ├── PlatformDAO.sol              # Platform-wide DAO
│   ├── SimpleAccountFactory.sol     # New: Factory for smart contract wallets
│   ├── SimpleAccount.sol            # New: Smart wallet implementation
│   ├── Paymaster.sol                # New: Gas sponsorship for USDC transactions
├── src/
│   ├── components/
│   │   ├── CreatePost.js            # Shoppable tags, queued posts
│   │   ├── Messaging.js             # Custom content, priority chats
│   │   ├── Marketplace.js           # PPV, NFT, commerce, USDC payments
│   │   ├── Profile.js               # Updated: Smart wallet setup, DAO memberships
│   │   ├── ForYouFeed.js            # Community, hub, music feeds
│   │   ├── Search.js                # Hubs, products, music, NFTs
│   │   ├── PostCreation.js          # Cross-platform posting
│   │   ├── ARMarketplace.js         # AR filter NFTs
│   │   ├── GamificationConfig.js    # Points, badges, levels
│   │   ├── Leaderboard.js           # Rankings for games, engagement
│   │   ├── VoiceInteraction.js      # Multilingual voice commands
│   │   ├── PrizeConfig.js           # Gamification prizes
│   │   ├── StreamScheduler.js       # Live stream scheduling
│   │   ├── StreamView.js            # Low-bandwidth streaming
│   │   ├── PrivacySettings.js       # Privacy controls
│   │   ├── NFTMarketplace.js        # NFT trading
│   │   ├── Connections.js           # Followers, suggested friends
│   │   ├── GroupChat.js             # Interest and cultural hubs
│   │   ├── AnalyticsDashboard.js    # Subscription, PPV, commerce, music analytics
│   │   ├── Subscription.js          # Creator subscriptions
│   │   ├── AdManager.js             # Opt-in ads
│   │   ├── ReportContent.js         # Content reporting
│   │   ├── Governance.js            # Platform DAO voting
│   │   ├── AgeVerification.js       # Self-attestation UI
│   │   ├── PPVContent.js            # PPV purchases
│   │   ├── OfflineSync.js           # Offline content creation, caching
│   │   ├── Commerce.js              # Social commerce UI
│   │   ├── GameFi.js                # GameFi mini-games
│   │   ├── CulturalHub.js           # Cultural community hubs
│   │   ├── MobilePayment.js         # Fiat-to-USDC on-ramps
│   │   ├── MusicStreaming.js        # Music streaming, NFT purchases
│   │   ├── ArtistDAO.js             # Artist DAO participation
│   │   ├── PlatformDAO.js           # Platform DAO participation
│   ├── abis/
│   │   ├── UserProfile.json
│   │   ├── Content.json
│   │   ├── Messaging.json
│   │   ├── Reward.json
│   │   ├── Marketplace.json
│   │   ├── PrivacySettings.json
│   │   ├── NFT.json
│   │   ├── Subscription.json
│   │   ├── AdManager.json
│   │   ├── Governance.json
│   │   ├── AgeVerification.json
│   │   ├── GroupChat.json
│   │   ├── Commerce.json
│   │   ├── GameFi.json
│   │   ├── MusicStreaming.json
│   │   ├── ArtistDAO.json
│   │   ├── PlatformDAO.json
│   │   ├── SimpleAccountFactory.json # New: Factory ABI
│   │   ├── SimpleAccount.json       # New: Smart wallet ABI
│   │   ├── Paymaster.json           # New: Paymaster ABI
│   ├── App.js                       # Updated: Smart wallet onboarding
│   ├── index.js
│   ├── App.css                     # High-contrast themes
├── mobile/
│   ├── components/
│   │   ├── CreatePost.js
│   │   ├── Messaging.js
│   │   ├── Marketplace.js
│   │   ├── Profile.js
│   │   ├── ForYouFeed.js
│   │   ├── CommentSection.js
│   │   ├── GroupChat.js
│   │   ├── EventCreator.js
│   │   ├── FollowButton.js
│   │   ├── StoryViewer.js
│   │   ├── SearchBar.js
│   │   ├── LiveStream.js
│   │   ├── TipButton.js
│   │   ├── AnalyticsDashboard.js
│   │   ├── ARStreamUnity.js
│   │   ├── PrivacySettings.js
│   │   ├── NFTMarketplace.js
│   │   ├── Connections.js
│   │   ├── Subscription.js
│   │   ├── AdManager.js
│   │   ├── ReportContent.js
│   │   ├── Governance.js
│   │   ├── AgeVerification.js
│   │   ├── PPVContent.js
│   │   ├── OfflineSync.js
│   │   ├── Commerce.js
│   │   ├── GameFi.js
│   │   ├── CulturalHub.js
│   │   ├── MobilePayment.js
│   │   ├── MusicStreaming.js
│   │   ├── ArtistDAO.js
│   │   ├── PlatformDAO.js
│   ├── App.js                      # Updated: Smart wallet onboarding
│   ├── package.json
├── backend/
│   ├── server.js                   # Updated: Smart wallet, USDC queries
│   ├── schema.graphql              # Updated: Smart wallet events
│   ├── subgraph.yaml               # Updated: Indexes new contracts
│   ├── src/
│   │   ├── mapping.ts              # Updated: Event handlers
├── streaming-server/
│   ├── index.js
│   ├── package.json
│   ├── .env
├── storage/
│   ├── ipfs.js                    # Content storage
│   ├── arweave.js                 # Permanent storage
├── recommendation.py              # Updated: NSFW, music, commerce recommendations
├── README.md                      # Updated: Simple Account Factory
├── package.json
├── .env

### Key Components

- **Smart Contracts** (`contracts/`):
  - `UserProfile.sol`: Profiles, Web3 logins, DAO memberships.
  - `Content.sol`: Posts, streams, restricted, PPV, music, queued content.
  - `Subscription.sol`: Creator subscriptions with USDC payments.
  - `Commerce.sol`: Social commerce marketplace.
  - `MusicStreaming.sol`: Decentralized music streaming and NFT releases.
  - `GameFi.sol`: Play-to-earn mini-games.
  - `ArtistDAO.sol`: Artist-led DAOs for fan engagement.
  - `PlatformDAO.sol`: Platform-wide user governance.
  - `AgeVerification.sol`: Self-attestation for restricted content.
  - `Marketplace.sol`: PPV, tipping, commerce, USDC payments.

- **Frontend** (`src/components/`, `mobile/components/`):
  - `Subscription.js`: Manage subscriptions.
  - `MusicStreaming.js`: Stream music, buy NFT tracks.
  - `Commerce.js`: Shoppable posts and checkout.
  - `GameFi.js`: Mini-games for USDC rewards.
  - `OfflineSync.js`: Offline content creation and caching.
  - `CulturalHub.js`: Cultural community hubs.
  - `ArtistDAO.js`: Artist DAO participation.
  - `PlatformDAO.js`: Platform DAO voting.
  - `MobilePayment.js`: Fiat-to-USDC payments.

- **Backend** (`backend/`):
  - GraphQL server and subgraph for blockchain events.

- **AI Moderation** (`recommendation.py`):
  - NSFW detection, personalized music and commerce recommendations.

## Prerequisites

- **Node.js** (>= 16.x)
- **Python** (>= 3.8) for `recommendation.py`
- **Hardhat** or **Foundry** for smart contracts
- **IPFS** and **Arweave** nodes or APIs
- **Sonic Blockchain** testnet/mainnet access
- **MetaMask** or compatible Web3 wallet
- **Fiat-to-Crypto On-Ramp APIs** (e.g., MoonPay, Transak, Flutterwave)

## Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/your-org/afrovibe-platform.git
   cd afrovibe-platform

Install Dependencies:
npm install
cd mobile && npm install
cd ../backend && npm install
cd ../streaming-server && npm install   

Set Up Environment Variables:
Create .env files in root/ and streaming-server/:

# Root .env
SONIC_RPC_URL=https://rpc.sonic.network
IPFS_API_KEY=your-ipfs-key
ARWEAVE_KEY=your-arweave-key
GRAPHQL_ENDPOINT=http://localhost:4000/graphql
MOONPAY_API_KEY=your-moonpay-key
TRANSAK_API_KEY=your-transak-key
FLUTTERWAVE_API_KEY=your-flutterwave-key

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
pip install -r requirements.txt
python recommendation.py

Usage
Connect Wallet: Log in via MetaMask or other wallets using UserProfile.sol.

Acquire USDC: Buy Sonic native USDC with mobile money via MobilePayment.js.

Create Content: Post, stream, or sell products using CreatePost.js, MusicStreaming.js, Commerce.js.

Monetize: Set up subscriptions (Subscription.js), PPV (PPVContent.js), music NFTs (MusicStreaming.js), or sell AR filters (ARMarketplace.js).

Engage: Earn USDC via GameFi (GameFi.js), join cultural hubs (CulturalHub.js), participate in DAOs (ArtistDAO.js, PlatformDAO.js), or vote (Governance.js).

Offline Access: Draft posts or view feeds offline (OfflineSync.js).

AfroVibe: Empowering creators, celebrating culture, and connecting the world with Web3.


---

### Integration with Sonic Native USDC

#### Why USDC?
Using Sonic native USDC, a stablecoin pegged to the US dollar, ensures price stability, mitigating volatility concerns associated with S tokens. This is critical for Nigeria, where users prioritize predictable costs, and globally, where stablecoins are increasingly adopted for DeFi and payments.

#### Technical Adjustments
1. **Smart Contracts**:
   - **Marketplace.sol**, **Subscription.sol**, **Commerce.sol**, **Reward.sol**, **MusicStreaming.sol**, **GameFi.sol**: Updated to handle USDC transactions (e.g., `payWithUSDC(address user, uint256 amount)`), interacting with Sonic’s USDC contract (assumed deployed).
   - **MobilePayment.js**: Integrates fiat-to-USDC on-ramps (e.g., MoonPay, Transak, Flutterwave) via APIs, allowing users to buy USDC with mobile money or bank transfers. Example:
     ```jsx
     const buyUSDC = async (amount, paymentMethod) => {
       const response = await fetch('https://api.moonpay.com/v3/purchase', {
         method: 'POST',
         headers: { 'Authorization': `Bearer ${process.env.MOONPAY_API_KEY}` },
         body: JSON.stringify({
           amount,
           currency: 'USDC',
           paymentMethod,
           walletAddress: userWallet
         })
       });
       const data = await response.json();
       return data.transactionId;
     };
     ```
   - **UserProfile.sol**: Ensures wallets support USDC on Sonic, using standards like ERC-20.

2. **Backend**:
   - **schema.graphql**, **mapping.ts**: Indexes USDC transactions (e.g., `USDCPayment(address user, uint256 amount)`).
   - **server.js**: Handles on-ramp callbacks, updating balances via The Graph.

3. **Frontend**:
   - **MobilePayment.js**: Displays USDC balance and purchase options, guiding users through on-ramp flows.
   - **AnalyticsDashboard.js**: Tracks USDC revenue with stable value reporting.
   - **All payment components** (`Subscription.js`, `PPVContent.js`, `Commerce.js`, `TipButton.js`, `MusicStreaming.js`, `GameFi.js`): Updated to display and process USDC amounts.

4. **Compliance**:
   - On-ramp partners handle KYC/AML, but AfroVibe must comply with Nigerian regulations (e.g., CBN guidelines) via terms in `MobilePayment.js`.

#### User Experience
- **Nigeria**: A user buys USDC with MTN MoMo via `MobilePayment.js`, pays 500 NGN (~$0.30) for 0.30 USDC, and subscribes to a creator for 0.10 USDC/month. The stablecoin ensures predictable costs.
- **Global**: Users in the US or EU buy USDC with credit cards or PayPal, using the same on-ramp, and engage in music streaming or GameFi, benefiting from low Sonic transaction fees.

---

### Benefits for Adoption

1. **Nigeria**:
   - **USDC Stability**: Ensures predictable pricing, critical for users wary of crypto volatility.
   - **Local Payments**: Fiat-to-USDC on-ramps make AfroVibe accessible to the 60% unbanked, leveraging mobile money.
   - **Cultural Hubs & Music**: Celebrate Nigeria’s diversity and Afrobeats, driving engagement.
   - **Offline Sync**: Reaches rural users, addressing connectivity issues.
   - **GameFi & Commerce**: Monetizes Nigeria’s gaming ($2.39 billion by 2025) and e-commerce markets.

2. **Global**:
   - Competes with Spotify, TikTok, and Instagram via music streaming, GameFi, and commerce, enhanced by Web3 ownership.
   - Appeals to diaspora and emerging markets with cultural hubs and offline access.
   - Attracts crypto-savvy users with DAOs and USDC stability.

3. **Adoption Drivers**:
   - **Inclusivity**: USDC and mobile money lower financial barriers.
   - **Engagement**: Music, GameFi, and hubs drive daily interaction.
   - **Monetization**: Subscriptions, commerce, and music attract creators.
   - **Trust**: Stablecoin and DAOs build user confidence.

---
## AfroVibe Project

### Mobile Components
- **Staking.js**: Handles staking, unstaking, reward claiming, token bridging, validator delegation, and proposal creation. Uses ethers.js to interact with `Staking.sol`.
- **AnalyticsDashboard.js**: Displays user data (Sonic Points, staked amounts, delegated amounts) using on-chain and subgraph data.

### Backend Components
- **subgraph.yaml, schema.graphql, mapping.ts**: Indexes `Staking.sol` events (Staked, Unstaked, etc.) for querying by the mobile app.
- **rewardCalculator.js**: Calculates off-chain rewards based on stakes and Sonic Points.

### Setup
1. Install dependencies:
   ```bash
   npm install ethers graphql-request graphql react-native
   
## Testing
To compile and test the Staking contract:
```bash
npx hardhat compile
npx hardhat test

Tests cover:
Staking and unstaking with Sonic Points
Reward claiming
Cross-chain bridging
Validator delegation
Governance proposals

### Conclusion

The directory structure integrates all game-changing features—music streaming, DAOs, offline sync, social commerce, local payments, cultural hubs, AI personalization, and GameFi—using Sonic native USDC for stable transactions. The README.md reflects these additions, providing a clear roadmap for developers and users. This architecture leverages Sonic’s scalability, ensures cultural relevance, and addresses Nigeria’s unique challenges, positioning AfroVibe as a leading Web3 social platform.

Contact
GitHub: Emantest/afrovibe

Email: support@afrovibe.io

Community: Join our Discord or X community

