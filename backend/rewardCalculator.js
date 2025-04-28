// backend/rewardCalculator.js
const ethers = require('ethers');
const fetch = require('node-fetch');
require('dotenv').config();

// Environment variables
const SONIC_RPC_URL = process.env.SONIC_RPC_URL || 'https://rpc.sonic.network';
const S_TOKEN_ADDRESS = process.env.S_TOKEN_ADDRESS;
const BEETS_STAKING_ADDRESS = process.env.BEETS_STAKING_ADDRESS;
const STAKING_CONTRACT_ADDRESS = '0x...'; // Deployed Staking.sol address

// Initialize provider
const provider = new ethers.providers.JsonRpcProvider(SONIC_RPC_URL);

// Staking.sol ABI (simplified)
const stakingAbi = [
  'function calculateAfrovibeRewards(address user, uint256 stakeIndex) view returns (uint256)',
  'function stakes(address user, uint256 stakeIndex) view returns (uint256 stSAmount, uint256 lockPeriod, uint256 startTime, uint256 accumulatedAfrovibeRewards)'
];
const stakingContract = new ethers.Contract(STAKING_CONTRACT_ADDRESS, stakingAbi, provider);

// Beets API (hypothetical)
const BEETS_API_URL = 'https://api.beets.finance/sonic/apr';

// Calculate rewards
async function calculateRewards(userAddress, stakeIndex, stakedAmount, lockPeriod, elapsedDays) {
  try {
    // Fetch Beets APR (3.5-7%)
    const response = await fetch(BEETS_API_URL);
    const { apr } = await response.json(); // Example: { apr: 0.05 } (5%)
    if (apr < 0.035 || apr > 0.07) throw new Error('Invalid Beets APR');

    // Get stake details from Staking.sol
    const stake = await stakingContract.stakes(userAddress, stakeIndex);
    if (stake.stSAmount.eq(0)) throw new Error('No stake found');

    // Beets Rewards (auto-compounded)
    const dailyBeetsRate = apr / 365;
    const beetsEffectiveBalance = stakedAmount * Math.pow(1 + dailyBeetsRate, elapsedDays);
    const beetsRewards = beetsEffectiveBalance - stakedAmount;

    // AfroVibe Rewards (claimable)
    const afrovibeAPY = 0.05; // 5% APY
    const afrovibeRewards = await stakingContract.calculateAfrovibeRewards(userAddress, stakeIndex);
    const afrovibeRewardsFormatted = ethers.utils.formatUnits(afrovibeRewards, 18); // Assuming 18 decimals

    // Total Effective Yield
    const totalRewards = beetsRewards + parseFloat(afrovibeRewardsFormatted);
    const totalYieldPercent = (totalRewards / stakedAmount) * 100;

    return {
      beets: {
        apr: (apr * 100).toFixed(2) + '%',
        rewards: beetsRewards.toFixed(2) + ' S',
        effectiveBalance: beetsEffectiveBalance.toFixed(2) + ' stS'
      },
      afrovibe: {
        apy: '5.00%',
        rewards: afrovibeRewardsFormatted + ' S'
      },
      total: {
        rewards: totalRewards.toFixed(2) + ' S',
        yield: totalYieldPercent.toFixed(2) + '%'
      }
    };
  } catch (error) {
    console.error('Error calculating rewards:', error.message);
    return null;
  }
}

// Example usage
async function main() {
  const userAddress = '0x123...';
  const stakeIndex = 0;
  const stakedAmount = 1000; // 1,000 S
  const lockPeriod = 365; // 365 days
  const elapsedDays = 90; // 90 days elapsed

  const rewards = await calculateRewards(userAddress, stakeIndex, stakedAmount, lockPeriod, elapsedDays);
  if (rewards) {
    console.log('Staking Rewards:');
    console.log(`Beets: ${rewards.beets.rewards} (${rewards.beets.apr}, compounded)`);
    console.log(`AfroVibe: ${rewards.afrovibe.rewards} (${rewards.afrovibe.apy}, claimable)`);
    console.log(`Total: ${rewards.total.rewards} (${rewards.total.yield})`);
  }
}

main();
