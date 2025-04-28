// 5% APY S token staking; Beets integration; dual rewards
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC4337.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/governance/TimelockControllerUpgradeable.sol";

interface IBeetsStaking {
    function stake(address user, uint256 amount) external returns (uint256 stSAmount);
    function unstake(address user, uint256 stSAmount) external returns (uint256 amount);
    function claimRewards(address user) external returns (uint256 rewards);
    function isPaused() external view returns (bool);
}

interface IGovernance {
    function propose(bytes calldata proposalData) external returns (uint256 proposalId);
    function vote(uint256 proposalId, bool support) external;
    function execute(uint256 proposalId) external;
    function isActive() external view returns (bool);
}

interface ISonicGateway {
    function bridgeFromEthereum(address token, uint256 amount, address recipient) external returns (bool);
    function bridgeToEthereum(address token, uint256 amount, address recipient) external returns (bool);
}

interface ISonicValidator {
    function delegate(address validator, uint256 amount) external;
    function undelegate(address validator, uint256 amount) external;
    function claimValidatorRewards(address validator) external returns (uint256);
}

/// @title Staking - Sonic-optimized staking contract with governance and ERC-4337 support
/// @notice Allows users to stake S tokens, earn Afrovibe and validator rewards, and participate in Sonic governance
/// @dev Uses OpenZeppelin upgradeable contracts for security and UUPS for upgradability
contract Staking is ReentrancyGuardUpgradeable, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable, IERC4337 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Roles
    /// @notice Role for DAO governance actions
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    /// @notice Role for administrative actions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Sonic-specific state variables
    /// @notice Interface for Sonic Gateway for cross-chain bridging
    ISonicGateway public sonicGateway;
    /// @notice Interface for Sonic Validator for delegation
    ISonicValidator public sonicValidator;
    /// @notice Address to receive penalty fees
    address public feeRecipient;
    /// @notice Mapping of user addresses to their Sonic Points balance
    mapping(address => uint256) public sonicPoints;
    /// @notice Mapping of user addresses to their Sonic Points expiry timestamp
    mapping(address => uint256) public sonicPointsExpiry;
    /// @notice Mapping of user addresses to validator addresses to delegated amounts
    mapping(address => mapping(address => uint256)) public delegatedAmounts;
    /// @notice Maximum Sonic Points a user can hold
    uint256 public constant MAX_SONIC_POINTS = 1_000_000e18;
    /// @notice Discount rate in basis points per 1000 Sonic Points
    uint256 public sonicPointDiscountRate;
    /// @notice Expiry period for Sonic Points (1 year)
    uint256 public constant POINT_EXPIRY = 365 * 86400;
    /// @notice Maximum delegation amount per validator
    uint256 public maxDelegationPerValidator;

    // Existing state variables
    /// @notice S token contract for staking
    IERC20Upgradeable public sToken;
    /// @notice Beets staking contract interface
    IBeetsStaking public beetsStaking;
    /// @notice Governance contract interface
    IGovernance public governance;
    /// @notice Timelock controller for governance actions
    TimelockControllerUpgradeable public timelock;
    /// @notice Address of the platform DAO
    address public platformDAO;
    /// @notice List of paymaster addresses for ERC-4337
    address[] public paymasters;
    /// @notice Mapping of paymaster addresses to their trusted status
    mapping(address => bool) public trustedPaymasters;
    /// @notice Mapping of paymaster addresses to their reliability score (0-100)
    mapping(address => uint256) public paymasterReliability;
    /// @notice Minimum reliability score for trusted paymasters
    uint256 public constant MIN_PAYMASTER_RELIABILITY = 80;
    /// @notice Annual percentage yield for Afrovibe rewards (in basis points)
    uint256 public afrovibeAPY;
    /// @notice Minimum lock period for stakes in days
    uint256 public minLockDays;
    /// @notice Maximum lock period for stakes in days
    uint256 public maxLockDays;
    /// @notice Seconds in a day for time calculations
    uint256 public constant DAY_SECONDS = 86400;
    /// @notice Precision factor for calculations
    uint256 public constant PRECISION = 1e27;
    /// @notice Reserve of S tokens for reward payouts
    uint256 public rewardReserve;
    /// @notice Cached minimum reserve threshold
    uint256 public cachedReserveThreshold;
    /// @notice Last threshold update timestamp
    uint256 public lastThresholdUpdate;
    /// @notice Interval for threshold updates (1 week)
    uint256 public thresholdUpdateInterval;
    /// @notice Maximum rewards claimable per transaction
    uint256 public claimRateLimit;
    /// @notice Claim cooldown period (1 day)
    uint256 public claimCooldown;
    /// @notice Penalty percentage for early unstaking (in basis points)
    uint256 public penaltyPercentage;
    /// @notice Voting power decay rate per day (in basis points)
    uint256 public votingPowerDecayRate;
    /// @notice Flag indicating if reward claims are paused
    bool public rewardClaimsPaused;
    /// @notice Total amount of staked S tokens
    uint256 public totalStaked;
    /// @notice Mapping of user addresses to stake index to stake details
    mapping(address => mapping(uint256 => Stake)) public stakes;
    /// @notice Mapping of user addresses to their number of stakes
    mapping(address => uint256) public stakeCount;
    /// @notice Mapping of user addresses to their voting power
    mapping(address => uint256) public votingPower;
    /// @notice Mapping of proposal IDs to proposal details
    mapping(uint256 => Proposal) public proposals;
    /// @notice Total number of proposals
    uint256 public proposalCount;
    /// @notice Mapping of user addresses to their total accumulated Afrovibe rewards
    mapping(address => uint256) public totalAfrovibeRewards;
    /// @notice Maximum number of stakes per batch operation
    uint256 public constant MAX_BATCH_SIZE = 10;
    /// @notice Cumulative reward index for Afrovibe rewards
    uint256 public rewardIndex;
    /// @notice Last reward index update timestamp
    uint256 public lastRewardUpdate;
    /// @notice Mapping of user addresses to their last reward index
    mapping(address => uint256) public userRewardIndex;
    /// @notice Mapping of user addresses to their pending rewards
    mapping(address => uint256) public userPendingRewards;
    /// @notice Mapping of user addresses to their last claim timestamp
    mapping(address => uint256) public lastClaimTimestamp;

    // Bridging-specific state variables
    /// @notice Maximum amount per bridge transaction
    uint256 public maxBridgeAmount;
    /// @notice Maximum bridge amount per user
    uint256 public userBridgeLimit;
    /// @notice Flag indicating if bridging is paused
    bool public bridgingPaused;
    /// @notice Mapping of user addresses to their current bridge usage
    mapping(address => uint256) public userBridgeLimits;
    /// @notice Maximum bridge limit constant
    uint256 public constant MAX_BRIDGE_LIMIT = 10000e18;

    // Upgrade proposal state
    /// @notice Structure for upgrade proposals
    struct UpgradeProposal {
        address newImplementation; // Proposed implementation contract
        bytes32 descriptionHash; // Hash of upgrade description
        uint256 proposedAt; // Timestamp of proposal
        uint256 timelockEnd; // Timestamp when upgrade can be confirmed
        bool validated; // Whether the proposal has been validated
        bool cancelled; // Whether the proposal has been cancelled
    }
    /// @notice Mapping of proposal IDs to upgrade proposals
    mapping(uint256 => UpgradeProposal) public upgradeProposals;
    /// @notice Total number of upgrade proposals
    uint256 public upgradeProposalCount;

    // Structs
    /// @notice Structure representing a single stake
    struct Stake {
        uint128 stSAmount; // Amount of staked S tokens
        uint128 accumulatedAfrovibeRewards; // Accumulated Afrovibe rewards
        uint64 lockPeriod; // Lock period in days
        uint64 startTime; // Timestamp when stake was created
        bool active; // Whether the stake is active
    }

    /// @notice Structure representing a governance proposal
    struct Proposal {
        bytes32 merkleRoot; // Merkle root for voter eligibility
        bytes32 descriptionHash; // Hash of proposal description
        uint256 proposalId; // Proposal ID
        uint256 snapshotTimestamp; // Voting power snapshot timestamp
        bool executed; // Whether the proposal has been executed
    }

    // Events
    event Staked(address indexed user, uint256 amount, uint256 stSAmount, uint256 lockPeriod, uint256 stakeIndex);
    event Unstaked(address indexed user, uint256 amount, uint256 stSAmount, uint256 stakeIndex, uint256 penalty);
    event PartialUnstaked(address indexed user, uint256 amount, uint256 stSAmount, uint256 stakeIndex);
    event RewardsClaimed(address indexed user, uint256 afrovibeRewards, uint256 validatorRewards, uint256 beetsRewards);
    event BatchStaked(address indexed user, uint256[] amounts, uint256[] lockPeriods, uint256[] stakeIndices);
    event BatchUnstaked(address indexed user, uint256[] stakeIndices, uint256 totalAmount, uint256 totalPenalty);
    event BatchRewardsClaimed(address indexed user, uint256[] stakeIndices, uint256 totalBeetsRewards, uint256 totalAfrovibeRewards);
    event RewardReserveFunded(address indexed funder, uint256 amount);
    event RewardReserveWithdrawn(address indexed dao, uint256 amount);
    event PaymasterUpdated(address indexed paymaster, bool trusted, uint256 reliability);
    event PaymasterFailed(address indexed paymaster, uint256 missingAccountFunds, string reason);
    event APYUpdated(uint256 newAPY);
    event ParameterProposed(uint256 indexed proposalId, bytes32 merkleRoot);
    event ParameterUpdated(uint256 indexed proposalId, string parameter, uint256 value);
    event Paused(address indexed admin);
    event Unpaused(address indexed admin);
    event RewardClaimsPaused(address indexed admin);
    event RewardClaimsUnpaused(address indexed admin);
    event UpgradeProposed(address indexed newImplementation, uint256 timelockEnd);
    event UpgradeProposalCreated(uint256 indexed proposalId, address newImplementation, bytes32 descriptionHash, uint256 timelockEnd);
    event UpgradeProposalValidated(uint256 indexed proposalId, address newImplementation);
    event UpgradeProposalConfirmed(uint256 indexed proposalId, address newImplementation);
    event UpgradeProposalCancelled(uint256 indexed proposalId, address newImplementation);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event SonicPointsEarned(address indexed user, uint256 points);
    event SonicPointsRedeemed(address indexed user, uint256 points, uint256 discount);
    event SonicPointDiscountRateUpdated(uint256 oldRate, uint256 newRate);
    event ValidatorDelegated(address indexed user, address indexed validator, uint256 amount);
    event ValidatorUndelegated(address indexed user, address indexed validator, uint256 amount);
    event TokensBridged(address indexed user, address indexed token, uint256 amount, address recipient, bool toEthereum);
    event ProposalVerified(uint256 indexed proposalId, address indexed voter, bytes32 leaf);
    event ReserveThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event BridgingPaused(address indexed admin);
    event BridgingUnpaused(address indexed admin);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with Sonic-specific parameters
    /// @param _sToken Address of the S token
    /// @param _beetsStaking Address of the Beets staking contract
    /// @param _governance Address of the governance contract
    /// @param _platformDAO Address of the platform DAO
    /// @param _paymaster Initial trusted paymaster
    /// @param _timelock Address of the timelock controller
    /// @param _sonicGateway Address of the Sonic Gateway
    /// @param _sonicValidator Address of the Sonic validator contract
    /// @param _feeRecipient Address to receive penalty fees
    function initialize(
        address _sToken,
        address _beetsStaking,
        address _governance,
        address _platformDAO,
        address _paymaster,
        address _timelock,
        address _sonicGateway,
        address _sonicValidator,
        address _feeRecipient
    ) external initializer {
        require(_sToken != address(0) && _beetsStaking != address(0) && _governance != address(0), "STK-001: Invalid addresses");
        require(_platformDAO != address(0) && _paymaster != address(0) && _timelock != address(0), "STK-002: Invalid addresses");
        require(_sonicGateway != address(0) && _sonicValidator != address(0) && _feeRecipient != address(0), "STK-003: Invalid addresses");

        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DAO_ROLE, _platformDAO);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender); // Revoke immediately

        sToken = IERC20Upgradeable(_sToken);
        beetsStaking = IBeetsStaking(_beetsStaking);
        governance = IGovernance(_governance);
        platformDAO = _platformDAO;
        timelock = TimelockControllerUpgradeable(_timelock);
        sonicGateway = ISonicGateway(_sonicGateway);
        sonicValidator = ISonicValidator(_sonicValidator);
        feeRecipient = _feeRecipient;

        paymasters.push(_paymaster);
        trustedPaymasters[_paymaster] = true;
        paymasterReliability[_paymaster] = 100;

        afrovibeAPY = 500; // 5% APY
        minLockDays = 1;
        maxLockDays = 365;
        rewardReserve = 0;
        cachedReserveThreshold = 1e18;
        lastThresholdUpdate = block.timestamp;
        thresholdUpdateInterval = 7 * DAY_SECONDS;
        claimRateLimit = 1000e18;
        claimCooldown = DAY_SECONDS;
        penaltyPercentage = 1000; // 10%
        votingPowerDecayRate = 10; // 0.1% per day
        rewardClaimsPaused = false;
        totalStaked = 0;
        sonicPointDiscountRate = 100; // 1% discount per 1000 points
        maxDelegationPerValidator = 100000e18;
        maxBridgeAmount = MAX_BRIDGE_LIMIT;
        userBridgeLimit = 5000e18;
        bridgingPaused = false;
        lastRewardUpdate = block.timestamp;

        emit PaymasterUpdated(_paymaster, true, 100);
        emit SonicPointDiscountRateUpdated(0, 100);
        emit ReserveThresholdUpdated(0, cachedReserveThreshold);
    }

    // --- Multi-Step Upgrade Process ---

    /// @notice Proposes a new implementation contract for upgrade
    /// @param newImplementation Address of the new implementation
    /// @param descriptionHash Hash of the upgrade description
    /// @return proposalId The ID of the upgrade proposal
    function proposeUpgrade(address newImplementation, bytes32 descriptionHash) external onlyRole(DAO_ROLE) returns (uint256 proposalId) {
        require(newImplementation != address(0), "STK-004: Invalid implementation");
        uint256 timelockDelay = timelock.getMinDelay();
        proposalId = upgradeProposalCount++;

        upgradeProposals[proposalId] = UpgradeProposal({
            newImplementation: newImplementation,
            descriptionHash: descriptionHash,
            proposedAt: block.timestamp,
            timelockEnd: block.timestamp + timelockDelay,
            validated: false,
            cancelled: false
        });

        emit UpgradeProposalCreated(proposalId, newImplementation, descriptionHash, block.timestamp + timelockDelay);
        emit UpgradeProposed(newImplementation, block.timestamp + timelockDelay);
        return proposalId;
    }

    /// @notice Validates a proposed implementation
    /// @param proposalId The ID of the upgrade proposal
    function validateUpgrade(uint256 proposalId) external onlyRole(DAO_ROLE) {
        UpgradeProposal storage proposal = upgradeProposals[proposalId];
        require(proposal.newImplementation != address(0) && !proposal.cancelled, "STK-005: Invalid proposal");
        require(!proposal.validated, "STK-006: Already validated");
        require(block.timestamp < proposal.timelockEnd, "STK-007: Timelock expired");

        // Check if it's a contract
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(proposal.newImplementation)
        }
        require(codeSize > 0, "STK-008: Not a contract");

        proposal.validated = true;
        emit UpgradeProposalValidated(proposalId, proposal.newImplementation);
    }

    /// @notice Confirms and executes the upgrade
    /// @param proposalId The ID of the upgrade proposal
    function confirmUpgrade(uint256 proposalId) external onlyRole(DAO_ROLE) {
        UpgradeProposal storage proposal = upgradeProposals[proposalId];
        require(proposal.newImplementation != address(0) && !proposal.cancelled, "STK-009: Invalid proposal");
        require(proposal.validated, "STK-010: Not validated");
        require(block.timestamp >= proposal.timelockEnd, "STK-011: Timelock not elapsed");

        _authorizeUpgrade(proposal.newImplementation);
        _upgradeTo(proposal.newImplementation);

        emit UpgradeProposalConfirmed(proposalId, proposal.newImplementation);
        delete upgradeProposals[proposalId];
    }

    /// @notice Cancels a proposed upgrade
    /// @param proposalId The ID of the upgrade proposal
    function cancelUpgrade(uint256 proposalId) external onlyRole(DAO_ROLE) {
        UpgradeProposal storage proposal = upgradeProposals[proposalId];
        require(proposal.newImplementation != address(0) && !proposal.cancelled, "STK-012: Invalid proposal");
        require(block.timestamp < proposal.timelockEnd, "STK-013: Timelock expired");

        proposal.cancelled = true;
        emit UpgradeProposalCancelled(proposalId, proposal.newImplementation);
    }

    /// @notice UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DAO_ROLE) {}

    // --- Reward System ---

    /// @notice Funds the reward reserve
    /// @param amount Amount of S tokens to fund
    function fundRewardReserve(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "STK-014: Amount must be > 0");
        sToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardReserve += amount;
        emit RewardReserveFunded(msg.sender, amount);
    }

    /// @notice Withdraws from the reward reserve (DAO only)
    /// @param amount Amount to withdraw
    function withdrawRewardReserve(uint256 amount) external onlyRole(DAO_ROLE) {
        require(amount <= rewardReserve, "STK-015: Insufficient reserve");
        rewardReserve -= amount;
        sToken.safeTransfer(platformDAO, amount);
        emit RewardReserveWithdrawn(platformDAO, amount);
    }

    /// @notice Updates the global reward index
    function updateRewardIndex() internal {
        if (totalStaked == 0) return;
        uint256 timeElapsed = block.timestamp - lastRewardUpdate;
        if (timeElapsed == 0) return;

        uint256 newRewards = (totalStaked * afrovibeAPY * timeElapsed * PRECISION) / (365 * DAY_SECONDS * 100);
        rewardIndex += newRewards / totalStaked;
        lastRewardUpdate = block.timestamp;
    }

    /// @notice Updates a user's pending rewards
    /// @param user Address of the user
    function updateUserRewards(address user) internal {
        updateRewardIndex();
        uint256 userStaked = 0;
        for (uint256 i = 0; i < stakeCount[user]; ++i) {
            if (stakes[user][i].active) {
                userStaked += stakes[user][i].stSAmount;
            }
        }
        uint256 newRewards = (userStaked * (rewardIndex - userRewardIndex[user])) / PRECISION;
        userPendingRewards[user] += newRewards;
        userRewardIndex[user] = rewardIndex;
        totalAfrovibeRewards[user] = userPendingRewards[user];
    }

    /// @notice Calculates dynamic reserve threshold
    /// @return threshold The minimum reserve required
    function getDynamicReserveThreshold() public returns (uint256) {
        if (block.timestamp >= lastThresholdUpdate + thresholdUpdateInterval) {
            uint256 newThreshold = (totalStaked * afrovibeAPY * maxLockDays * DAY_SECONDS) / (365 * 100 * PRECISION);
            emit ReserveThresholdUpdated(cachedReserveThreshold, newThreshold);
            cachedReserveThreshold = newThreshold;
            lastThresholdUpdate = block.timestamp;
        }
        return cachedReserveThreshold;
    }

    /// @notice Checks and updates reward claim pause status
    function checkRewardReserveStatus() internal {
        bool shouldPause = rewardReserve < getDynamicReserveThreshold();
        if (shouldPause && !rewardClaimsPaused) {
            rewardClaimsPaused = true;
            emit RewardClaimsPaused(msg.sender);
        } else if (!shouldPause && rewardClaimsPaused) {
            rewardClaimsPaused = false;
            emit RewardClaimsUnpaused(msg.sender);
        }
    }

    /// @notice Claims Afrovibe, validator, and Beets rewards
    /// @return totalRewards Total rewards claimed
    function claimRewards() external nonReentrant whenNotPaused returns (uint256 totalRewards) {
        require(block.timestamp >= lastClaimTimestamp[msg.sender] + claimCooldown, "STK-016: Claim cooldown active");
        checkRewardReserveStatus();
        require(!rewardClaimsPaused, "STK-017: Reward claims paused");

        updateUserRewards(msg.sender);
        uint256 afrovibeRewards = userPendingRewards[msg.sender];
        require(afrovibeRewards <= claimRateLimit, "STK-018: Exceeds claim rate limit");

        uint256 beetsRewards;
        try beetsStaking.claimRewards(msg.sender) returns (uint256 _beetsRewards) {
            beetsRewards = _beetsRewards;
        } catch Error(string memory reason) {
            emit PaymasterFailed(address(beetsStaking), 0, string(abi.encodePacked("Beets reward claim failed: ", reason)));
            beetsRewards = 0;
        }

        uint256 validatorRewards;
        for (uint256 i = 0; i < paymasters.length; ++i) {
            address validator = paymasters[i];
            if (delegatedAmounts[msg.sender][validator] > 0) {
                try sonicValidator.claimValidatorRewards(validator) returns (uint256 _validatorRewards) {
                    validatorRewards += _validatorRewards;
                } catch Error(string memory reason) {
                    emit PaymasterFailed(validator, 0, string(abi.encodePacked("Validator reward claim failed: ", reason)));
                }
            }
        }

        totalRewards = afrovibeRewards + validatorRewards + beetsRewards;
        require(totalRewards > 0, "STK-019: No rewards to claim");

        if (rewardReserve < totalRewards) {
            totalRewards = rewardReserve;
            afrovibeRewards = (afrovibeRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
            validatorRewards = (validatorRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
            beetsRewards = (beetsRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
        }

        rewardReserve -= totalRewards;
        userPendingRewards[msg.sender] = 0;
        totalAfrovibeRewards[msg.sender] = 0;
        lastClaimTimestamp[msg.sender] = block.timestamp;

        sToken.safeTransfer(msg.sender, totalRewards);
        emit RewardsClaimed(msg.sender, afrovibeRewards, validatorRewards, beetsRewards);
    }

    /// @notice Claims rewards for a range of stakes
    /// @param startIndex Starting stake index
    /// @param endIndex Ending stake index
    /// @return totalRewards Total rewards claimed
    function claimRewardsRange(uint256 startIndex, uint256 endIndex) external nonReentrant whenNotPaused returns (uint256 totalRewards) {
        require(block.timestamp >= lastClaimTimestamp[msg.sender] + claimCooldown, "STK-020: Claim cooldown active");
        require(startIndex <= endIndex && endIndex < stakeCount[msg.sender], "STK-021: Invalid range");
        checkRewardReserveStatus();
        require(!rewardClaimsPaused, "STK-022: Reward claims paused");

        updateUserRewards(msg.sender);
        uint256 afrovibeRewards = userPendingRewards[msg.sender];
        require(afrovibeRewards <= claimRateLimit, "STK-023: Exceeds claim rate limit");

        uint256 beetsRewards;
        try beetsStaking.claimRewards(msg.sender) returns (uint256 _beetsRewards) {
            beetsRewards = _beetsRewards;
        } catch Error(string memory reason) {
            emit PaymasterFailed(address(beetsStaking), 0, string(abi.encodePacked("Beets reward claim failed: ", reason)));
            beetsRewards = 0;
        }

        uint256 validatorRewards;
        for (uint256 i = startIndex; i <= endIndex; ++i) {
            if (stakes[msg.sender][i].active) {
                for (uint256 j = 0; j < paymasters.length; ++j) {
                    address validator = paymasters[j];
                    if (delegatedAmounts[msg.sender][validator] > 0) {
                        try sonicValidator.claimValidatorRewards(validator) returns (uint256 _validatorRewards) {
                            validatorRewards += _validatorRewards;
                        } catch Error(string memory reason) {
                            emit PaymasterFailed(validator, 0, string(abi.encodePacked("Validator reward claim failed: ", reason)));
                        }
                    }
                }
            }
        }

        totalRewards = afrovibeRewards + validatorRewards + beetsRewards;
        require(totalRewards > 0, "STK-024: No rewards to claim");

        if (rewardReserve < totalRewards) {
            totalRewards = rewardReserve;
            afrovibeRewards = (afrovibeRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
            validatorRewards = (validatorRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
            beetsRewards = (beetsRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
        }

        rewardReserve -= totalRewards;
        userPendingRewards[msg.sender] = 0;
        totalAfrovibeRewards[msg.sender] = 0;
        lastClaimTimestamp[msg.sender] = block.timestamp;

        sToken.safeTransfer(msg.sender, totalRewards);
        emit RewardsClaimed(msg.sender, afrovibeRewards, validatorRewards, beetsRewards);
    }

    // --- Sonic Points ---

    /// @notice Redeems Sonic Points for a discount
    /// @param points Number of points to redeem (multiple of 1000)
    /// @return discount Discount in basis points
    function redeemSonicPoints(uint256 points) public nonReentrant whenNotPaused returns (uint256 discount) {
        require(points > 0 && sonicPoints[msg.sender] >= points, "STK-025: Insufficient points");
        require(points % 1000 == 0, "STK-026: Points must be multiple of 1000");
        require(block.timestamp < sonicPointsExpiry[msg.sender], "STK-027: Points expired");

        discount = (points / 1000) * sonicPointDiscountRate;
        sonicPoints[msg.sender] -= points;
        emit SonicPointsRedeemed(msg.sender, points, discount);
        return discount;
    }

    /// @notice Updates the Sonic Point discount rate
    /// @param newRate New discount rate in basis points
    function updateSonicPointDiscountRate(uint256 newRate) external onlyRole(DAO_ROLE) {
        require(newRate <= 1000, "STK-028: Rate too high");
        require(newRate >= 10, "STK-029: Rate too low");
        uint256 oldRate = sonicPointDiscountRate;
        sonicPointDiscountRate = newRate;
        emit SonicPointDiscountRateUpdated(oldRate, newRate);
    }

    // --- Staking ---

    /// @notice Stakes S tokens and awards Sonic Points
    /// @param amount Amount of S tokens to stake
    /// @param lockPeriod Lock period in days
    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant whenNotPaused {
        require(amount > 0, "STK-030: Amount must be > 0");
        require(lockPeriod >= minLockDays && lockPeriod <= maxLockDays, "STK-031: Invalid lock period");
        require(!beetsStaking.isPaused(), "STK-032: BeetsStaking paused");

        uint256 initialBalance = sToken.balanceOf(address(this));
        sToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 stSAmount;
        try beetsStaking.stake(msg.sender, amount) returns (uint256 _stSAmount) {
            stSAmount = _stSAmount;
            require(stSAmount > 0, "STK-033: Zero stSAmount");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("STK-034: Beets staking failed: ", reason)));
        }

        require(sToken.balanceOf(address(this)) == initialBalance + amount, "STK-035: Balance mismatch");

        uint256 stakeIndex = stakeCount[msg.sender]++;
        stakes[msg.sender][stakeIndex] = Stake({
            stSAmount: uint128(stSAmount),
            lockPeriod: uint64(lockPeriod),
            startTime: uint64(block.timestamp),
            accumulatedAfrovibeRewards: 0,
            active: true
        });

        totalStaked += stSAmount;
        votingPower[msg.sender] += (stSAmount * lockPeriod) / maxLockDays;
        uint256 points = amount / 1e18;
        if (sonicPoints[msg.sender] + points <= MAX_SONIC_POINTS) {
            sonicPoints[msg.sender] += points;
            sonicPointsExpiry[msg.sender] = block.timestamp + POINT_EXPIRY;
            emit SonicPointsEarned(msg.sender, points);
        }

        updateUserRewards(msg.sender);
        emit Staked(msg.sender, amount, stSAmount, lockPeriod, stakeIndex);
    }

    /// @notice Batch stakes multiple amounts
    /// @param amounts Array of S token amounts
    /// @param lockPeriods Array of lock periods
    function batchStake(uint256[] calldata amounts, uint256[] calldata lockPeriods) external nonReentrant whenNotPaused {
        require(amounts.length == lockPeriods.length && amounts.length > 0, "STK-036: Invalid inputs");
        require(amounts.length <= MAX_BATCH_SIZE, "STK-037: Exceeds max batch size");
        require(!beetsStaking.isPaused(), "STK-038: BeetsStaking paused");

        uint256[] memory stakeIndices = new uint256[](amounts.length);
        uint256 initialBalance = sToken.balanceOf(address(this));
        uint256 totalAmount;
        uint256 totalStSAmount;
        uint256 totalPoints;
        uint256 userStakeCount = stakeCount[msg.sender];
        uint256 userVotingPower = votingPower[msg.sender];

        for (uint256 i = 0; i < amounts.length; ++i) {
            uint256 amount = amounts[i];
            uint256 lockPeriod = lockPeriods[i];
            require(amount > 0 && lockPeriod >= minLockDays && lockPeriod <= maxLockDays, "STK-039: Invalid stake params");

            totalAmount += amount;
            sToken.safeTransferFrom(msg.sender, address(this), amount);
            uint256 stSAmount;
            try beetsStaking.stake(msg.sender, amount) returns (uint256 _stSAmount) {
                stSAmount = _stSAmount;
                require(stSAmount > 0, "STK-040: Zero stSAmount");
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("STK-041: Beets staking failed: ", reason)));
            }

            stakes[msg.sender][userStakeCount] = Stake({
                stSAmount: uint128(stSAmount),
                lockPeriod: uint64(lockPeriod),
                startTime: uint64(block.timestamp),
                accumulatedAfrovibeRewards: 0,
                active: true
            });

            totalStSAmount += stSAmount;
            totalPoints += amount / 1e18;
            userVotingPower += (stSAmount * lockPeriod) / maxLockDays;
            stakeIndices[i] = userStakeCount++;
        }

        require(sToken.balanceOf(address(this)) == initialBalance + totalAmount, "STK-042: Balance mismatch");
        stakeCount[msg.sender] = userStakeCount;
        votingPower[msg.sender] = userVotingPower;
        totalStaked += totalStSAmount;
        if (sonicPoints[msg.sender] + totalPoints <= MAX_SONIC_POINTS) {
            sonicPoints[msg.sender] += totalPoints;
            sonicPointsExpiry[msg.sender] = block.timestamp + POINT_EXPIRY;
            emit SonicPointsEarned(msg.sender, totalPoints);
        }

        updateUserRewards(msg.sender);
        emit BatchStaked(msg.sender, amounts, lockPeriods, stakeIndices);
    }

    /// @notice Unstakes a specific stake with optional Sonic Points discount
    /// @param stakeIndex Index of the stake
    /// @param usePoints Number of Sonic Points to redeem for penalty discount
    function unstake(uint256 stakeIndex, uint256 usePoints) external nonReentrant whenNotPaused {
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(userStake.active && userStake.stSAmount > 0, "STK-043: Invalid stake");
        require(!beetsStaking.isPaused(), "STK-044: BeetsStaking paused");

        uint256 penalty = 0;
        if (block.timestamp < userStake.startTime + userStake.lockPeriod * DAY_SECONDS) {
            penalty = (userStake.stSAmount * penaltyPercentage) / 10000;
            if (usePoints > 0) {
                uint256 discount = redeemSonicPoints(usePoints);
                penalty = penalty > (penalty * discount) / 10000 ? penalty - (penalty * discount) / 10000 : 0;
            }
        }

        uint256 totalDelegated;
        for (uint256 i = 0; i < paymasters.length; ++i) {
            address validator = paymasters[i];
            if (delegatedAmounts[msg.sender][validator] > 0) {
                totalDelegated += delegatedAmounts[msg.sender][validator];
                try sonicValidator.undelegate(validator, delegatedAmounts[msg.sender][validator]) {
                    emit ValidatorUndelegated(msg.sender, validator, delegatedAmounts[msg.sender][validator]);
                    delegatedAmounts[msg.sender][validator] = 0;
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("STK-045: Validator undelegation failed: ", reason)));
                }
            }
        }

        uint256 amount;
        try beetsStaking.unstake(msg.sender, userStake.stSAmount) returns (uint256 _amount) {
            amount = _amount;
            require(amount > 0, "STK-046: Zero amount returned");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("STK-047: Beets unstaking failed: ", reason)));
        }

        if (penalty > 0) {
            sToken.safeTransfer(feeRecipient, penalty);
            amount -= penalty;
        }
        sToken.safeTransfer(msg.sender, amount);

        totalAfrovibeRewards[msg.sender] -= userStake.accumulatedAfrovibeRewards;
        totalStaked -= userStake.stSAmount;
        votingPower[msg.sender] -= (userStake.stSAmount * userStake.lockPeriod) / maxLockDays;
        userStake.active = false;

        updateUserRewards(msg.sender);
        emit Unstaked(msg.sender, amount, userStake.stSAmount, stakeIndex, penalty);
    }

    /// @notice Batch unstakes multiple stakes
    /// @param stakeIndices Indices of stakes to unstake
    /// @param usePoints Number of Sonic Points to redeem for penalty discount
    function batchUnstake(uint256[] calldata stakeIndices, uint256 usePoints) external nonReentrant whenNotPaused {
        require(stakeIndices.length > 0 && stakeIndices.length <= MAX_BATCH_SIZE, "STK-048: Invalid indices");
        require(!beetsStaking.isPaused(), "STK-049: BeetsStaking paused");

        uint256 totalAmount;
        uint256 totalPenalty;
        uint256 totalStSAmount;
        uint256 totalRewards;
        uint256 userVotingPower = votingPower[msg.sender];
        uint256 discount = usePoints > 0 ? redeemSonicPoints(usePoints) : 0;

        for (uint256 i = 0; i < stakeIndices.length; ++i) {
            Stake storage userStake = stakes[msg.sender][stakeIndices[i]];
            require(userStake.active && userStake.stSAmount > 0, "STK-050: Invalid stake");

            uint256 penalty = 0;
            if (block.timestamp < userStake.startTime + userStake.lockPeriod * DAY_SECONDS) {
                penalty = (userStake.stSAmount * penaltyPercentage) / 10000;
                if (discount > 0) {
                    penalty = penalty > (penalty * discount) / 10000 ? penalty - (penalty * discount) / 10000 : 0;
                }
            }

            uint256 amount;
            try beetsStaking.unstake(msg.sender, userStake.stSAmount) returns (uint256 _amount) {
                amount = _amount;
                require(amount > 0, "STK-051: Zero amount returned");
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("STK-052: Beets unstaking failed: ", reason)));
            }

            totalAmount += amount;
            totalPenalty += penalty;
            totalStSAmount += userStake.stSAmount;
            totalRewards += userStake.accumulatedAfrovibeRewards;
            userVotingPower -= (userStake.stSAmount * userStake.lockPeriod) / maxLockDays;
            userStake.active = false;
        }

        uint256 totalDelegated;
        for (uint256 i = 0; i < paymasters.length; ++i) {
            address validator = paymasters[i];
            if (delegatedAmounts[msg.sender][validator] > 0) {
                totalDelegated += delegatedAmounts[msg.sender][validator];
                try sonicValidator.undelegate(validator, delegatedAmounts[msg.sender][validator]) {
                    emit ValidatorUndelegated(msg.sender, validator, delegatedAmounts[msg.sender][validator]);
                    delegatedAmounts[msg.sender][validator] = 0;
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("STK-053: Validator undelegation failed: ", reason)));
                }
            }
        }

        if (totalPenalty > 0) {
            sToken.safeTransfer(feeRecipient, totalPenalty);
            totalAmount -= totalPenalty;
        }
        sToken.safeTransfer(msg.sender, totalAmount);

        totalAfrovibeRewards[msg.sender] -= totalRewards;
        totalStaked -= totalStSAmount;
        votingPower[msg.sender] = userVotingPower;

        updateUserRewards(msg.sender);
        emit BatchUnstaked(msg.sender, stakeIndices, totalAmount, totalPenalty);
    }

    /// @notice Batch claims rewards for stakes
    /// @param stakeIndices Indices of stakes to claim rewards for
    function batchClaimRewards(uint256[] calldata stakeIndices) external nonReentrant whenNotPaused {
        require(stakeIndices.length > 0 && stakeIndices.length <= MAX_BATCH_SIZE, "STK-054: Invalid indices");
        require(block.timestamp >= lastClaimTimestamp[msg.sender] + claimCooldown, "STK-055: Claim cooldown active");
        checkRewardReserveStatus();
        require(!rewardClaimsPaused, "STK-056: Reward claims paused");

        updateUserRewards(msg.sender);
        uint256 afrovibeRewards = userPendingRewards[msg.sender];
        require(afrovibeRewards <= claimRateLimit, "STK-057: Exceeds claim rate limit");

        uint256 beetsRewards;
        try beetsStaking.claimRewards(msg.sender) returns (uint256 _beetsRewards) {
            beetsRewards = _beetsRewards;
        } catch Error(string memory reason) {
            emit PaymasterFailed(address(beetsStaking), 0, string(abi.encodePacked("Beets reward claim failed: ", reason)));
            beetsRewards = 0;
        }

        uint256 validatorRewards;
        for (uint256 i = 0; i < stakeIndices.length; ++i) {
            require(stakes[msg.sender][stakeIndices[i]].active, "STK-058: Invalid stake");
            for (uint256 j = 0; j < paymasters.length; ++j) {
                address validator = paymasters[j];
                if (delegatedAmounts[msg.sender][validator] > 0) {
                    try sonicValidator.claimValidatorRewards(validator) returns (uint256 _validatorRewards) {
                        validatorRewards += _validatorRewards;
                    } catch Error(string memory reason) {
                        emit PaymasterFailed(validator, 0, string(abi.encodePacked("Validator reward claim failed: ", reason)));
                    }
                }
            }
        }

        uint256 totalRewards = afrovibeRewards + validatorRewards + beetsRewards;
        require(totalRewards > 0, "STK-059: No rewards to claim");

        if (rewardReserve < totalRewards) {
            totalRewards = rewardReserve;
            afrovibeRewards = (afrovibeRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
            validatorRewards = (validatorRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
            beetsRewards = (beetsRewards * rewardReserve) / (afrovibeRewards + validatorRewards + beetsRewards);
        }

        rewardReserve -= totalRewards;
        userPendingRewards[msg.sender] = 0;
        totalAfrovibeRewards[msg.sender] = 0;
        lastClaimTimestamp[msg.sender] = block.timestamp;

        sToken.safeTransfer(msg.sender, totalRewards);
        emit BatchRewardsClaimed(msg.sender, stakeIndices, beetsRewards, afrovibeRewards);
    }

    // --- Validator Delegation ---

    /// @notice Delegates staked tokens to a Sonic validator
    /// @param validator Address of the validator
    /// @param amount Amount of staked tokens to delegate
    function delegateToValidator(address validator, uint256 amount) external nonReentrant whenNotPaused {
        require(validator != address(0), "STK-060: Invalid validator");
        require(amount > 0, "STK-061: Amount must be > 0");
        require(delegatedAmounts[msg.sender][validator] + amount <= maxDelegationPerValidator, "STK-062: Exceeds validator delegation limit");

        uint256 userStaked = 0;
        for (uint256 i = 0; i < stakeCount[msg.sender]; ++i) {
            if (stakes[msg.sender][i].active) {
                userStaked += stakes[msg.sender][i].stSAmount;
            }
        }
        require(userStaked >= amount, "STK-063: Insufficient staked amount");

        try sonicValidator.delegate(validator, amount) {
            delegatedAmounts[msg.sender][validator] += amount;
            emit ValidatorDelegated(msg.sender, validator, amount);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("STK-064: Validator delegation failed: ", reason)));
        }
    }

    /// @notice Undelegates staked tokens from a validator
    /// @param validator Address of the validator
    /// @param amount Amount to undelegate
    function undelegateFromValidator(address validator, uint256 amount) external nonReentrant whenNotPaused {
        require(validator != address(0), "STK-065: Invalid validator");
        require(amount > 0 && delegatedAmounts[msg.sender][validator] >= amount, "STK-066: Insufficient delegated amount");

        try sonicValidator.undelegate(validator, amount) {
            delegatedAmounts[msg.sender][validator] -= amount;
            emit ValidatorUndelegated(msg.sender, validator, amount);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("STK-067: Validator undelegation failed: ", reason)));
        }
    }

    // --- Bridging ---

    /// @notice Pauses bridging operations
    function pauseBridging() external onlyRole(ADMIN_ROLE) {
        require(!bridgingPaused, "STK-068: Bridging already paused");
        bridgingPaused = true;
        emit BridgingPaused(msg.sender);
    }

    /// @notice Unpauses bridging operations
    function unpauseBridging() external onlyRole(ADMIN_ROLE) {
        require(bridgingPaused, "STK-069: Bridging not paused");
        bridgingPaused = false;
        emit BridgingUnpaused(msg.sender);
    }

    /// @notice Bridges tokens via Sonic Gateway
    /// @param token Address of the token
    /// @param amount Amount to bridge
    /// @param recipient Address to receive tokens
    /// @param toEthereum True if bridging to Ethereum
    function bridgeTokens(address token, uint256 amount, address recipient, bool toEthereum) external nonReentrant whenNotPaused {
        require(!bridgingPaused, "STK-070: Bridging paused");
        require(amount <= maxBridgeAmount, "STK-071: Exceeds bridge limit");
        require(userBridgeLimits[msg.sender] + amount <= userBridgeLimit, "STK-072: Exceeds user bridge limit");
        require(token != address(0) && recipient != address(0), "STK-073: Invalid address");
        require(amount > 0, "STK-074: Amount must be > 0");

        uint256 allowance = IERC20Upgradeable(token).allowance(msg.sender, address(this));
        require(allowance >= amount, "STK-075: Insufficient allowance");

        userBridgeLimits[msg.sender] += amount;

        if (toEthereum) {
            IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
            try sonicGateway.bridgeToEthereum(token, amount, recipient) returns (bool success) {
                require(success, "STK-076: Bridge to Ethereum failed");
                emit TokensBridged(msg.sender, token, amount, recipient, true);
            } catch Error(string memory reason) {
                userBridgeLimits[msg.sender] -= amount;
                IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
                revert(string(abi.encodePacked("STK-077: Bridge to Ethereum failed: ", reason)));
            } catch {
                userBridgeLimits[msg.sender] -= amount;
                IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
                revert("STK-078: Bridge to Ethereum failed: Unknown error");
            }
        } else {
            try sonicGateway.bridgeFromEthereum(token, amount, recipient) returns (bool success) {
                require(success, "STK-079: Bridge from Ethereum failed");
                emit TokensBridged(msg.sender, token, amount, recipient, false);
            } catch Error(string memory reason) {
                userBridgeLimits[msg.sender] -= amount;
                revert(string(abi.encodePacked("STK-080: Bridge from Ethereum failed: ", reason)));
            } catch {
                userBridgeLimits[msg.sender] -= amount;
                revert("STK-081: Bridge from Ethereum failed: Unknown error");
            }
        }
    }

    // --- Governance ---

    /// @notice Creates a new governance proposal
    /// @param merkleRoot Merkle root for voter eligibility
    /// @param descriptionHash Hash of proposal description
    /// @return proposalId The ID of the proposal
    function createProposal(bytes32 merkleRoot, bytes32 descriptionHash) external onlyRole(DAO_ROLE) returns (uint256 proposalId) {
        proposalId = proposalCount++;
        proposals[proposalId] = Proposal({
            merkleRoot: merkleRoot,
            descriptionHash: descriptionHash,
            proposalId: proposalId,
            snapshotTimestamp: block.timestamp,
            executed: false
        });
        emit ParameterProposed(proposalId, merkleRoot);
        return proposalId;
    }

    /// @notice Verifies a voter's eligibility for a proposal
    /// @param proposalId ID of the proposal
    /// @param merkleProof Merkle proof for the voter's leaf
    /// @return bool True if eligible
    function verifyProposalVoter(uint256 proposalId, bytes32[] calldata merkleProof) external returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.proposalId == proposalId && !proposal.executed, "STK-082: Invalid proposal");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, proposal.merkleRoot, leaf), "STK-083: Invalid proof");

        emit ProposalVerified(proposalId, msg.sender, leaf);
        return true;
    }

    /// @notice Updates the Afrovibe APY via governance
    /// @param newAPY New APY in basis points
    function updateAfrovibeAPY(uint256 newAPY) external onlyRole(DAO_ROLE) {
        require(newAPY >= 100 && newAPY <= 2000, "STK-084: Invalid APY"); // 1% to 20%
        afrovibeAPY = newAPY;
        emit APYUpdated(newAPY);
        emit ParameterUpdated(0, "afrovibeAPY", newAPY);
    }

    /// @notice Updates the maximum bridge amount
    /// @param newLimit New maximum bridge amount
    function updateMaxBridgeAmount(uint256 newLimit) external onlyRole(DAO_ROLE) {
        require(newLimit <= MAX_BRIDGE_LIMIT, "STK-085: Limit too high");
        maxBridgeAmount = newLimit;
        emit ParameterUpdated(0, "maxBridgeAmount", newLimit);
    }

    /// @notice Updates the user bridge limit
    /// @param newLimit New user bridge limit
    function updateUserBridgeLimit(uint256 newLimit) external onlyRole(DAO_ROLE) {
        require(newLimit <= MAX_BRIDGE_LIMIT / 2, "STK-086: Limit too high");
        userBridgeLimit = newLimit;
        emit ParameterUpdated(0, "userBridgeLimit", newLimit);
    }

    // --- Paymaster Management ---

    /// @notice Updates paymaster trust status and reliability
    /// @param paymaster Paymaster address
    /// @param trusted Whether the paymaster is trusted
    /// @param reliability Reliability score (0-100)
    function updatePaymaster(address paymaster, bool trusted, uint256 reliability) external onlyRole(DAO_ROLE) {
        require(paymaster != address(0), "STK-087: Invalid paymaster");
        require(reliability <= 100, "STK-088: Invalid reliability");
        if (trusted) {
            require(reliability >= MIN_PAYMASTER_RELIABILITY, "STK-089: Reliability too low");
        }

        if (trusted && !trustedPaymasters[paymaster]) {
            paymasters.push(paymaster);
        } else if (!trusted && trustedPaymasters[paymaster]) {
            for (uint256 i = 0; i < paymasters.length; ++i) {
                if (paymasters[i] == paymaster) {
                    paymasters[i] = paymasters[paymasters.length - 1];
                    paymasters.pop();
                    break;
                }
            }
        }

        trustedPaymasters[paymaster] = trusted;
        paymasterReliability[paymaster] = reliability;
        emit PaymasterUpdated(paymaster, trusted, reliability);
    }

    // --- Utility Functions ---

    /// @notice Applies voting power decay
    /// @param user Address of the user
    /// @return decayedPower The updated voting power
    function getDecayedVotingPower(address user) public view returns (uint256) {
        uint256 power = votingPower[user];
        if (stakeCount[user] == 0) return 0;
        uint256 daysElapsed = (block.timestamp - stakes[user][0].startTime) / DAY_SECONDS;
        uint256 decay = (power * votingPowerDecayRate * daysElapsed) / 10000;
        return power > decay ? power - decay : 0;
    }

    /// @notice Rescues tokens accidentally sent to the contract
    /// @param token Address of the token
    /// @param to Address to send tokens to
    /// @param amount Amount to rescue
    function rescueTokens(address token, address to, uint256 amount) external onlyRole(DAO_ROLE) {
        require(token != address(0) && to != address(0), "STK-090: Invalid address");
        require(amount > 0, "STK-091: Amount must be > 0");
        if (token == address(sToken)) {
            require(amount <= sToken.balanceOf(address(this)) - rewardReserve - totalStaked, "STK-092: Cannot rescue reserved tokens");
        }
        IERC20Upgradeable(token).safeTransfer(to, amount);
        emit TokensRescued(token, to, amount);
    }

    receive() external payable {}
}
