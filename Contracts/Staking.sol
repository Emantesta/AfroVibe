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
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Sonic-specific state variables
    ISonicGateway public sonicGateway;
    ISonicValidator public sonicValidator;
    address public feeRecipient;
    mapping(address => uint256) public sonicPoints;
    mapping(address => address) public delegatedValidators;
    uint256 public constant MAX_SONIC_POINTS = 1_000_000e18; // Cap to prevent abuse

    // Existing state variables
    IERC20Upgradeable public sToken;
    IBeetsStaking public beetsStaking;
    IGovernance public governance;
    TimelockControllerUpgradeable public timelock;
    address public platformDAO;
    address[] public paymasters;
    mapping(address => bool) public trustedPaymasters;
    mapping(address => uint256) public paymasterReliability;
    uint256 public afrovibeAPY;
    uint256 public minLockDays;
    uint256 public maxLockDays;
    uint256 public constant DAY_SECONDS = 86400;
    uint256 public constant PRECISION = 1e18;
    uint256 public rewardReserve;
    uint256 public reserveThreshold;
    uint256 public claimRateLimit;
    uint256 public penaltyPercentage;
    uint256 public votingPowerDecayRate;
    bool public rewardClaimsPaused;
    uint256 public totalStaked;
    mapping(address => mapping(uint256 => Stake)) public stakes;
    mapping(address => uint256) public stakeCount;
    mapping(address => uint256) public votingPower;
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(address => uint256) public proposedUpgrades;

    struct Stake {
        uint128 stSAmount;
        uint128 accumulatedAfrovibeRewards;
        uint64 lockPeriod;
        uint64 startTime;
        bool active;
    }

    struct Proposal {
        bytes32 merkleRoot;
        uint256 proposalId;
        bool executed;
    }

    // Events
    event Staked(address indexed user, uint256 amount, uint256 stSAmount, uint256 lockPeriod, uint256 stakeIndex);
    event Unstaked(address indexed user, uint256 amount, uint256 stSAmount, uint256 afrovibeRewards, uint256 beetsRewards, uint256 stakeIndex, bool early);
    event PartialUnstaked(address indexed user, uint256 amount, uint256 stSAmount, uint256 stakeIndex);
    event RewardsClaimed(address indexed user, uint256 beetsRewards, uint256 afrovibeRewards, uint256 stakeIndex);
    event BatchStaked(address indexed user, uint256[] amounts, uint256[] lockPeriods, uint256[] stakeIndices);
    event BatchUnstaked(address indexed user, uint256[] stakeIndices, uint256[] amounts, uint256[] afrovibeRewards, uint256[] beetsRewards);
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
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 stSAmount, uint256 stakeIndex, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 afrovibeRewards, uint256 validatorRewards);
    event BatchUnstaked(address indexed user, uint256[] stakeIndices, uint256 totalAmount, uint256 totalPenalty);
    event ProposalVerified(uint256 indexed proposalId, address indexed voter, bytes32 leaf);
    event PaymasterUpdated(address indexed paymaster, bool trusted, uint256 reliability);

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
    /// @param _feeRecipient Address to receive fee monetization
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
        require(_sToken != address(0) && _beetsStaking != address(0) && _governance != address(0), "Invalid addresses");
        require(_platformDAO != address(0) && _paymaster != address(0) && _timelock != address(0), "Invalid addresses");
        require(_sonicGateway != address(0) && _sonicValidator != address(0) && _feeRecipient != address(0), "Invalid addresses");

        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DAO_ROLE, _platformDAO);
        _grantRole(ADMIN_ROLE, msg.sender);

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
        afrovibeAPY = 350; // 3.5% APY
        minLockDays = 1; // 24-hour withdrawal period
        maxLockDays = 365;
        rewardReserve = 0;
        reserveThreshold = 1e18;
        claimRateLimit = 1000e18;
        penaltyPercentage = 1000; // 10%
        votingPowerDecayRate = 10; // 0.1% per day
        rewardClaimsPaused = false;
        totalStaked = 0;

        emit PaymasterUpdated(_paymaster, true, 100);
    }

    /// @notice Calculates dynamic reserve threshold based on total staked amount
    /// @return threshold The minimum reserve required
    function getDynamicReserveThreshold() public view returns (uint256) {
        return (totalStaked * afrovibeAPY * maxLockDays * DAY_SECONDS) / (365 * 100 * PRECISION);
    }

    /// @notice Unstakes a specific stake and applies penalties if applicable
    /// @param stakeIndex Index of the stake to unstake
    function unstake(uint256 stakeIndex) external nonReentrant whenNotPaused {
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(userStake.active && userStake.stSAmount > 0, "Invalid stake");
        require(!beetsStaking.isPaused(), "BeetsStaking paused");

        uint256 elapsedTime = block.timestamp - userStake.startTime;
        bool isLockExpired = elapsedTime >= userStake.lockPeriod * DAY_SECONDS;
        uint256 penalty = isLockExpired ? 0 : (userStake.stSAmount * penaltyPercentage) / 10000;

        address validator = delegatedValidators[msg.sender];
        if (validator != address(0)) {
            sonicValidator.undelegate(validator, userStake.stSAmount);
            delete delegatedValidators[msg.sender];
            emit ValidatorUndelegated(msg.sender, validator, userStake.stSAmount);
        }

        uint256 amount = beetsStaking.unstake(msg.sender, userStake.stSAmount);
        require(amount > 0, "Zero amount returned");

        if (penalty > 0) {
            sToken.safeTransfer(platformDAO, penalty);
            amount -= penalty;
        }
        sToken.safeTransfer(msg.sender, amount);

        totalStaked -= userStake.stSAmount;
        votingPower[msg.sender] -= (userStake.stSAmount * userStake.lockPeriod) / maxLockDays;
        userStake.active = false;

        emit Unstaked(msg.sender, amount, userStake.stSAmount, stakeIndex, penalty);
    }

    /// @notice Batch unstakes multiple stakes to optimize gas
    /// @param stakeIndices Indices of stakes to unstake
    function batchUnstake(uint256[] calldata stakeIndices) external nonReentrant whenNotPaused {
        require(stakeIndices.length > 0, "Empty indices");
        require(!beetsStaking.isPaused(), "BeetsStaking paused");

        uint256 totalAmount;
        uint256 totalPenalty;
        uint256 totalStSAmount;
        uint256 userVotingPower = votingPower[msg.sender];
        address validator = delegatedValidators[msg.sender];

        for (uint256 i = 0; i < stakeIndices.length; ++i) {
            Stake storage userStake = stakes[msg.sender][stakeIndices[i]];
            require(userStake.active && userStake.stSAmount > 0, "Invalid stake");

            uint256 elapsedTime = block.timestamp - userStake.startTime;
            bool isLockExpired = elapsedTime >= userStake.lockPeriod * DAY_SECONDS;
            uint256 penalty = isLockExpired ? 0 : (userStake.stSAmount * penaltyPercentage) / 10000;

            uint256 amount = beetsStaking.unstake(msg.sender, userStake.stSAmount);
            require(amount > 0, "Zero amount returned");

            totalAmount += amount;
            totalPenalty += penalty;
            totalStSAmount += userStake.stSAmount;
            userVotingPower -= (userStake.stSAmount * userStake.lockPeriod) / maxLockDays;
            userStake.active = false;
        }

        if (validator != address(0)) {
            sonicValidator.undelegate(validator, totalStSAmount);
            delete delegatedValidators[msg.sender];
            emit ValidatorUndelegated(msg.sender, validator, totalStSAmount);
        }

        if (totalPenalty > 0) {
            sToken.safeTransfer(platformDAO, totalPenalty);
            totalAmount -= totalPenalty;
        }
        sToken.safeTransfer(msg.sender, totalAmount);

        totalStaked -= totalStSAmount;
        votingPower[msg.sender] = userVotingPower;

        emit BatchUnstaked(msg.sender, stakeIndices, totalAmount, totalPenalty);
    }

    /// @notice Claims Afrovibe and validator rewards for a user
    /// @return totalRewards Total rewards claimed (Afrovibe + validator)
    function claimRewards() external nonReentrant whenNotPaused returns (uint256 totalRewards) {
        require(!rewardClaimsPaused, "Reward claims paused");
        require(rewardReserve >= reserveThreshold, "Insufficient reward reserve");

        uint256 afrovibeRewards;
        uint256 stakeCount_ = stakeCount[msg.sender];

        for (uint256 i = 0; i < stakeCount_; ++i) {
            Stake storage userStake = stakes[msg.sender][i];
            if (!userStake.active || userStake.stSAmount == 0) continue;

            uint256 elapsedTime = block.timestamp - userStake.startTime;
            uint256 reward = (userStake.stSAmount * afrovibeAPY * elapsedTime) / (365 * DAY_SECONDS * 100);
            userStake.accumulatedAfrovibeRewards += uint128(reward);
            afrovibeRewards += reward;
        }

        require(afrovibeRewards <= claimRateLimit, "Exceeds claim rate limit");
        address validator = delegatedValidators[msg.sender];
        uint256 validatorRewards = validator != address(0) ? sonicValidator.claimValidatorRewards(validator) : 0;

        totalRewards = afrovibeRewards + validatorRewards;
        require(totalRewards > 0, "No rewards to claim");
        require(rewardReserve >= totalRewards, "Insufficient reward reserve");

        rewardReserve -= totalRewards;
        sToken.safeTransfer(msg.sender, totalRewards);

        emit RewardsClaimed(msg.sender, afrovibeRewards, validatorRewards);
    }

    /// @notice Verifies a voter's eligibility for a proposal using Merkle proof
    /// @param proposalId ID of the proposal
    /// @param merkleProof Merkle proof for the voter's leaf
    /// @return bool True if the voter is eligible
    function verifyProposalVoter(uint256 proposalId, bytes32[] calldata merkleProof) external returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.proposalId == proposalId && !proposal.executed, "Invalid proposal");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, proposal.merkleRoot, leaf), "Invalid proof");

        emit ProposalVerified(proposalId, msg.sender, leaf);
        return true;
    }

    /// @notice Updates paymaster trust status and reliability
    /// @param paymaster Paymaster address
    /// @param trusted Whether the paymaster is trusted
    /// @param reliability Reliability score (0-100)
    function updatePaymaster(address paymaster, bool trusted, uint256 reliability) external onlyRole(DAO_ROLE) {
        require(paymaster != address(0), "Invalid paymaster");
        require(reliability <= 100, "Invalid reliability");

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

    /// @notice Applies voting power decay based on time elapsed
    /// @param user Address of the user
    /// @return decayedPower The updated voting power
    function getDecayedVotingPower(address user) public view returns (uint256) {
        uint256 power = votingPower[user];
        uint256 lastUpdate = block.timestamp; // Assume voting power updated at stake/unstake
        uint256 daysElapsed = (lastUpdate - stakes[user][0].startTime) / DAY_SECONDS;
        uint256 decay = (power * votingPowerDecayRate * daysElapsed) / 10000;
        return power > decay ? power - decay : 0;
    }

    /// @notice Overrides stake function to award capped Sonic Points
    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(lockPeriod >= minLockDays && lockPeriod <= maxLockDays, "Invalid lock period");
        require(!beetsStaking.isPaused(), "BeetsStaking paused");

        uint256 initialBalance = sToken.balanceOf(address(this));
        sToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 stSAmount = beetsStaking.stake(msg.sender, amount);
        require(stSAmount > 0, "Zero stSAmount returned");
        require(sToken.balanceOf(address(this)) == initialBalance + amount, "Balance mismatch");

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
            emit SonicPointsEarned(msg.sender, points);
        }

        emit Staked(msg.sender, amount, stSAmount, lockPeriod, stakeIndex);
    }

    /// @notice Overrides batchStake for gas optimization
    function batchStake(uint256[] calldata amounts, uint256[] calldata lockPeriods) external nonReentrant whenNotPaused {
        require(amounts.length == lockPeriods.length && amounts.length > 0, "Invalid inputs");
        require(!beetsStaking.isPaused(), "BeetsStaking paused");

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
            require(amount > 0 && lockPeriod >= minLockDays && lockPeriod <= maxLockDays, "Invalid stake params");

            totalAmount += amount;
            sToken.safeTransferFrom(msg.sender, address(this), amount);
            uint256 stSAmount = beetsStaking.stake(msg.sender, amount);
            require(stSAmount > 0, "Zero stSAmount");

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

        require(sToken.balanceOf(address(this)) == initialBalance + totalAmount, "Balance mismatch");
        stakeCount[msg.sender] = userStakeCount;
        votingPower[msg.sender] = userVotingPower;
        totalStaked += totalStSAmount;
        if (sonicPoints[msg.sender] + totalPoints <= MAX_SONIC_POINTS) {
            sonicPoints[msg.sender] += totalPoints;
            emit SonicPointsEarned(msg.sender, totalPoints);
        }

        emit BatchStaked(msg.sender, amounts, lockPeriods, stakeIndices);
    }

    receive() external payable {}
}
