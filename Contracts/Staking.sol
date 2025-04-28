// 5% APY S token staking; Beets integration; dual rewards
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/interfaces/IERC4337.sol";

interface IBeetsStaking {
    function stake(address user, uint256 amount) external returns (uint256 stSAmount);
    function unstake(address user, uint256 stSAmount) external returns (uint256 amount);
    function claimRewards(address user) external returns (uint256 rewards);
}

contract Staking is ReentrancyGuard, Pausable, IERC4337 {
    IERC20 public sToken;
    IBeetsStaking public beetsStaking;
    address public platformDAO;
    address public paymaster; // ERC-4337 paymaster
    uint256 public constant AFROVIBE_APY = 5; // 5% APY
    uint256 public constant DAY_SECONDS = 86400;

    struct Stake {
        uint256 stSAmount;
        uint256 lockPeriod;
        uint256 startTime;
        uint256 accumulatedAfrovibeRewards;
    }

    mapping(address => Stake[]) public stakes;
    mapping(address => uint256) public votingPower;

    event Staked(address indexed user, uint256 amount, uint256 stSAmount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount, uint256 stSAmount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 beetsRewards, uint256 afrovibeRewards);

    constructor(address _sToken, address _beetsStaking, address _platformDAO, address _paymaster) {
        sToken = IERC20(_sToken);
        beetsStaking = IBeetsStaking(_beetsStaking);
        platformDAO = _platformDAO;
        paymaster = _paymaster;
    }

    // ERC-4337 UserOp handler
    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        returns (uint256 validationData)
    {
        require(msg.sender == entryPoint(), "Only EntryPoint");
        // Validate signature (smart wallet logic)
        // Fund gas via paymaster
        if (missingAccountFunds > 0) {
            (bool success, ) = paymaster.call{value: missingAccountFunds}("");
            require(success, "Paymaster failed");
        }
        return 0; // Valid
    }

    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(lockPeriod == 30 || lockPeriod == 90 || lockPeriod == 180 || lockPeriod == 365, "Invalid lock period");

        sToken.transferFrom(msg.sender, address(this), amount);
        uint256 stSAmount = beetsStaking.stake(msg.sender, amount);

        stakes[msg.sender].push(Stake({
            stSAmount: stSAmount,
            lockPeriod: lockPeriod,
            startTime: block.timestamp,
            accumulatedAfrovibeRewards: 0
        }));

        votingPower[msg.sender] += amount * lockPeriod / 365;
        emit Staked(msg.sender, amount, stSAmount, lockPeriod);
    }

    function unstake(uint256 stakeIndex) external nonReentrant whenNotPaused {
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(userStake.stSAmount > 0, "No stake found");
        require(block.timestamp >= userStake.startTime + userStake.lockPeriod * DAY_SECONDS, "Lock period not ended");

        uint256 afrovibeRewards = calculateAfrovibeRewards(msg.sender, stakeIndex);
        uint256 beetsRewards = beetsStaking.claimRewards(msg.sender);
        uint256 amount = beetsStaking.unstake(msg.sender, userStake.stSAmount);

        votingPower[msg.sender] -= (userStake.stSAmount * userStake.lockPeriod) / 365;
        userStake.stSAmount = 0;
        userStake.accumulatedAfrovibeRewards = 0;

        sToken.transfer(msg.sender, amount);
        sToken.transfer(msg.sender, afrovibeRewards);
        emit Unstaked(msg.sender, amount, userStake.stSAmount, afrovibeRewards + beetsRewards);
    }

    function calculateAfrovibeRewards(address user, uint256 stakeIndex) public view returns (uint256) {
        Stake storage userStake = stakes[user][stakeIndex];
        if (userStake.stSAmount == 0) return 0;

        uint256 timeStaked = block.timestamp - userStake.startTime;
        return (userStake.stSAmount * AFROVIBE_APY * timeStaked) / (365 * DAY_SECONDS * 100);
    }

    function claimRewards(uint256 stakeIndex) external nonReentrant whenNotPaused {
        uint256 afrovibeRewards = calculateAfrovibeRewards(msg.sender, stakeIndex);
        uint256 beetsRewards = beetsStaking.claimRewards(msg.sender);
        require(afrovibeRewards + beetsRewards > 0, "No rewards to claim");

        stakes[msg.sender][stakeIndex].accumulatedAfrovibeRewards += afrovibeRewards;
        stakes[msg.sender][stakeIndex].startTime = block.timestamp;
        sToken.transfer(msg.sender, afrovibeRewards);
        emit RewardsClaimed(msg.sender, beetsRewards, afrovibeRewards);
    }
}
