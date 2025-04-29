// Beets staking UI; Staking UI with Beets reward
import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, Button, Alert, StyleSheet, ActivityIndicator, TouchableOpacity, Linking, Switch } from 'react-native';
import { ethers } from 'ethers';
import { ZeroDevSigner, getZeroDevSigner } from '@zerodev/sdk';
import { Web3Auth } from '@web3auth/react-native-sdk';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as WebBrowser from 'expo-web-browser';
import * as Linking from 'expo-linking';
import StakingABI from '../abis/Staking.json';
import { SONIC_RPC_URL, STAKING_CONTRACT_ADDRESS, S_TOKEN_ADDRESS } from '@env';

// Minimal ERC20 ABI for balance checks
const ERC20ABI = [
  'function balanceOf(address account) view returns (uint256)',
];

// Web3Auth configuration
const web3auth = new Web3Auth({
  clientId: 'YOUR_WEB3AUTH_CLIENT_ID', // Replace with your Web3Auth clientId
  network: 'testnet', // Use 'mainnet' for production
  redirectUrl: Linking.createURL('/'),
});

// Block explorer base URL (replace with actual Sonic testnet explorer, e.g., https://testnet.sonicscan.io/tx/)
const BLOCK_EXPLORER_URL = 'https://testnet.sonic.explorer/tx/';

/**
 * Staking component for interacting with the Sonic staking contract
 * @returns {JSX.Element}
 */
const Staking = () => {
  // State variables with JSDoc types
  /** @type {[ethers.providers.JsonRpcProvider | null, React.Dispatch<React.SetStateAction<ethers.providers.JsonRpcProvider | null>>]} */
  const [provider, setProvider] = useState(null);
  /** @type {[ZeroDevSigner | null, React.Dispatch<React.SetStateAction<ZeroDevSigner | null>>]} */
  const [signer, setSigner] = useState(null);
  /** @type {[ethers.Contract | null, React.Dispatch<React.SetStateAction<ethers.Contract | null>>]} */
  const [contract, setContract] = useState(null);
  /** @type {[string, React.Dispatch<React.SetStateAction<string>>]} */
  const [account, setAccount] = useState('');
  const [stakeAmount, setStakeAmount] = useState('');
  const [delegateAmount, setDelegateAmount] = useState('');
  const [lockPeriod, setLockPeriod] = useState('');
  const [stakeIndex, setStakeIndex] = useState('');
  const [pointsToUse, setPointsToUse] = useState('');
  const [bridgeAmount, setBridgeAmount] = useState('');
  const [recipient, setRecipient] = useState('');
  const [toEthereum, setToEthereum] = useState(false);
  const [validator, setValidator] = useState('');
  const [descriptionHash, setDescriptionHash] = useState('');
  const [merkleRoot, setMerkleRoot] = useState('');
  const [snapshotTimestamp, setSnapshotTimestamp] = useState('');
  const [proposalId, setProposalId] = useState('');
  const [merkleProof, setMerkleProof] = useState('');
  const [newImplementation, setNewImplementation] = useState('');
  const [sonicPoints, setSonicPoints] = useState('0');
  const [stakedAmount, setStakedAmount] = useState('0');
  /** @type {[Array<{index: number, amount: string, lockPeriod: string, endTime: string}>, React.Dispatch<React.SetStateAction<Array<{index: number, amount: string, lockPeriod: string, endTime: string}>>>]} */
  const [stakes, setStakes] = useState([]);
  /** @type {[Array<{hash: string, type: string, timestamp: string, status: string, amount?: string, gasUsed?: string}>, React.Dispatch<React.SetStateAction<Array<{hash: string, type: string, timestamp: string, status: string, amount?: string, gasUsed?: string}>>>]} */
  const [transactions, setTransactions] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [txHash, setTxHash] = useState('');
  const [isWalletConnected, setIsWalletConnected] = useState(false);
  /** @type {[number, React.Dispatch<React.SetStateAction<number>>]} */
  const [lastClick, setLastClick] = useState(0);
  /** @type {[boolean, React.Dispatch<React.SetStateAction<boolean>>]} */
  const [hasGetTotalStaked, setHasGetTotalStaked] = useState(false);
  /** @type {[boolean, React.Dispatch<React.SetStateAction<boolean>>]} */
  const [isDarkMode, setIsDarkMode] = useState(false);

  // Common lock periods for UI toggle
  const lockPeriodOptions = [30, 90, 180, 365];

  // Load theme preference from AsyncStorage
  useEffect(() => {
    const loadTheme = async () => {
      try {
        const theme = await AsyncStorage.getItem('theme');
        if (theme !== null) {
          setIsDarkMode(theme === 'dark');
        }
      } catch (error) {
        console.error('Error loading theme:', error);
      }
    };
    loadTheme();
  }, []);

  // Save theme preference to AsyncStorage
  const toggleDarkMode = async () => {
    const newTheme = !isDarkMode;
    setIsDarkMode(newTheme);
    try {
      await AsyncStorage.setItem('theme', newTheme ? 'dark' : 'light');
    } catch (error) {
      console.error('Error saving theme:', error);
    }
  };

  // Truncate address for display
  const truncateAddress = (address) => {
    if (!address) return '';
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  // Reset all input fields
  const resetInputs = () => {
    setStakeAmount('');
    setDelegateAmount('');
    setLockPeriod('');
    setStakeIndex('');
    setPointsToUse('');
    setBridgeAmount('');
    setRecipient('');
    setValidator('');
    setDescriptionHash('');
    setMerkleRoot('');
    setSnapshotTimestamp('');
    setProposalId('');
    setMerkleProof('');
    setNewImplementation('');
    setTxHash('');
  };

  // Validate Ethereum/Sonic address
  const isValidAddress = (address) => {
    return ethers.utils.isAddress(address);
  };

  // Map common contract errors to user-friendly messages
  const getFriendlyErrorMessage = (error) => {
    if (error.reason?.includes('insufficient balance')) {
      return 'Insufficient balance to complete this transaction';
    } else if (error.reason?.includes('lock period not expired')) {
      return 'Stake lock period has not yet expired';
    } else if (error.reason?.includes('invalid stake index')) {
      return 'Invalid stake index provided';
    } else if (error.reason?.includes('invalid merkle proof')) {
      return 'Invalid Merkle proof provided';
    } else if (error.reason?.includes('invalid proposal id')) {
      return 'Invalid proposal ID provided';
    } else if (error.reason?.includes('invalid implementation')) {
      return 'Invalid new implementation address';
    }
    return error.reason || error.message || 'An unexpected error occurred';
  };

  // Custom retry utility for contract calls
  const retry = async (fn, defaultRetries = 3) => {
    let lastError;
    let maxRetries = defaultRetries;
    let baseDelay = 500;

    const isNetworkError = (error) => {
      const networkErrorCodes = ['NETWORK_ERROR', 'TIMEOUT', 'SERVER_ERROR'];
      return networkErrorCodes.includes(error.code) || error.message.includes('network') || error.message.includes('timeout');
    };

    for (let i = 0; i < maxRetries; i++) {
      try {
        return await fn();
      } catch (error) {
        lastError = error;
        if (isNetworkError(error)) {
          maxRetries = 5; // More retries for network errors
          baseDelay = 1000; // Longer delay
        } else {
          maxRetries = 2; // Fewer retries for contract errors
          baseDelay = 300; // Shorter delay
        }
        const delay = baseDelay * Math.pow(2, i);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
    throw lastError;
  };

  // Simple debounce for button clicks (1000ms)
  const debounce = (func) => {
    return (...args) => {
      const now = Date.now();
      if (now - lastClick < 1000) return;
      setLastClick(now);
      func(...args);
    };
  };

  // Verify contract method availability
  const verifyContractMethods = async (contract) => {
    try {
      const requiredMethods = ['sonicPoints', 'stakeCount', 'stakes', 'verifyProposalVoter', 'proposeUpgrade', 'confirmUpgrade'];
      for (const method of requiredMethods) {
        if (typeof contract[method] !== 'function') {
          throw new Error(`Contract method ${method} is not available`);
        }
      }
      const hasGetTotalStaked = typeof contract.getTotalStaked === 'function';
      setHasGetTotalStaked(hasGetTotalStaked);
      if (!hasGetTotalStaked) {
        console.warn('getTotalStaked not available; falling back to loop-based calculation');
      }
    } catch (error) {
      console.error('Contract verification error:', error);
      Alert.alert('Error', 'Invalid staking contract. Missing required methods.');
      return false;
    }
    return true;
  };

  // Add transaction to history with initial pending status
  const addTransaction = (hash, type, amount = '0') => {
    const timestamp = new Date().toLocaleString();
    setTransactions((prev) => [
      { hash, type, timestamp, status: 'Pending', amount },
      ...prev.slice(0, 4), // Keep last 5 transactions
    ]);
    updateTransactionStatus(hash);
  };

  // Update transaction status and details
  const updateTransactionStatus = async (hash) => {
    try {
      const receipt = await provider.getTransactionReceipt(hash);
      setTransactions((prev) =>
        prev.map((tx) => {
          if (tx.hash !== hash) return tx;
          if (!receipt) {
            return { ...tx, status: 'Pending' };
          }
          const status = receipt.status === 1 ? 'Confirmed' : 'Failed';
          let gasUsed = ethers.utils.formatUnits(receipt.gasUsed, 'gwei');
          let amount = tx.amount;

          // Parse events for additional details
          if (tx.type === 'Stake' && status === 'Confirmed') {
            const stakedEvent = receipt.logs
              .map((log) => {
                try {
                  return contract.interface.parseLog(log);
                } catch {
                  return null;
                }
              })
              .find((event) => event?.name === 'Staked');
            if (stakedEvent) {
              amount = ethers.utils.formatEther(stakedEvent.args.amount);
            }
          } else if (tx.type === 'Bridge' && status === 'Confirmed') {
            const bridgedEvent = receipt.logs
              .map((log) => {
                try {
                  return contract.interface.parseLog(log);
                } catch {
                  return null;
                }
              })
              .find((event) => event?.name === 'Bridged');
            if (bridgedEvent) {
              amount = ethers.utils.formatEther(bridgedEvent.args.amount);
            }
          }

          return { ...tx, status, gasUsed, amount };
        })
      );

      // Continue polling if pending
      if (!receipt) {
        setTimeout(() => updateTransactionStatus(hash), 5000);
      }
    } catch (error) {
      console.error('Error updating transaction status:', error);
    }
  };

  // Initialize provider and check wallet connection
  useEffect(() => {
    const init = async () => {
      try {
        if (!SONIC_RPC_URL || !STAKING_CONTRACT_ADDRESS || !S_TOKEN_ADDRESS) {
          Alert.alert('Configuration Error', 'Please check environment variables.');
          return;
        }
        const provider = new ethers.providers.JsonRpcProvider(SONIC_RPC_URL);
        setProvider(provider);
        const web3authProvider = await web3auth.init();
        if (web3authProvider) {
          await connectWallet();
        }
        provider.on('network', (newNetwork, oldNetwork) => {
          if (oldNetwork) {
            Alert.alert('Network Changed', 'Please reconnect wallet.', [
              { text: 'Reconnect', onPress: connectWallet },
            ]);
          }
        });
      } catch (error) {
        console.error('Initialization error:', error);
        Alert.alert('Error', 'Failed to initialize provider');
      }
    };
    init();
    return () => {
      provider?.removeAllListeners();
    };
  }, []);

  // Connect wallet using Web3Auth and ZeroDev
  const connectWallet = async () => {
    try {
      setIsLoading(true);
      const web3authProvider = await web3auth.login({ loginProvider: 'google' });
      if (!web3authProvider) {
        throw new Error('Failed to login with Web3Auth');
      }
      const signer = await getZeroDevSigner({
        projectId: 'YOUR_ZERODEV_PROJECT_ID',
        chainId: 12345,
        rpcUrl: SONIC_RPC_URL,
        entryPointAddress: '0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789',
        factoryAddress: 'YOUR_SIMPLE_ACCOUNT_FACTORY_ADDRESS',
        web3authProvider,
      });
      const contract = new ethers.Contract(STAKING_CONTRACT_ADDRESS, StakingABI.abi, signer);
      const address = await signer.getAddress();
      const isValidContract = await verifyContractMethods(contract);
      if (!isValidContract) {
        throw new Error('Invalid contract configuration');
      }
      setSigner(signer);
      setContract(contract);
      setAccount(address);
      setIsWalletConnected(true);
      await updateUserData(address, contract);
    } catch (error) {
      console.error('Wallet connection error:', error);
      Alert.alert('Error', 'Failed to connect wallet');
    } finally {
      setIsLoading(false);
    }
  };

  // Disconnect wallet
  const disconnectWallet = async () => {
    try {
      await web3auth.logout();
      setSigner(null);
      setContract(null);
      setAccount('');
      setIsWalletConnected(false);
      setSonicPoints('0');
      setStakedAmount('0');
      setStakes([]);
      setTransactions([]);
      resetInputs();
    } catch (error) {
      console.error('Wallet disconnection error:', error);
      Alert.alert('Error', 'Failed to disconnect wallet');
    }
  };

  // Update user data (Sonic Points, staked amount, stakes)
  const updateUserData = async (userAddress, contract) => {
    try {
      const points = await retry(() => contract.sonicPoints(userAddress));
      let totalStaked;
      const stakeList = [];
      if (hasGetTotalStaked) {
        totalStaked = await retry(() => contract.getTotalStaked(userAddress));
      } else {
        const stakeCount = await retry(() => contract.stakeCount(userAddress));
        totalStaked = ethers.BigNumber.from(0);
        for (let i = 0; i < stakeCount; i++) {
          const stake = await retry(() => contract.stakes(userAddress, i));
          totalStaked = totalStaked.add(stake.amount);
          stakeList.push({
            index: i,
            amount: ethers.utils.formatEther(stake.amount),
            lockPeriod: stake.lockPeriod.toString(),
            endTime: new Date(stake.endTime * 1000).toLocaleDateString(),
          });
        }
      }
      setSonicPoints(ethers.utils.formatEther(points));
      setStakedAmount(ethers.utils.formatEther(totalStaked));
      setStakes(stakeList);
    } catch (error) {
      console.error('Error fetching user data:', error);
      Alert.alert('Error', 'Failed to fetch user data after multiple attempts');
    }
  };

  // Check token balance
  const checkBalance = async (amount) => {
    const tokenContract = new ethers.Contract(S_TOKEN_ADDRESS, ERC20ABI, signer);
    const balance = await tokenContract.balanceOf(account);
    return ethers.utils.parseEther(amount).lte(balance);
  };

  /**
   * Stake tokens with specified amount and lock period
   */
  const stakeTokens = async () => {
    if (!stakeAmount || isNaN(stakeAmount) || parseFloat(stakeAmount) <= 0) {
      Alert.alert('Error', 'Please enter a valid stake amount');
      return;
    }
    const lockPeriodNum = parseInt(lockPeriod);
    if (!lockPeriod || isNaN(lockPeriod) || lockPeriodNum <= 0 || lockPeriodNum > 365) {
      Alert.alert('Error', 'Lock period must be between 1 and 365 days');
      return;
    }
    if (!(await checkBalance(stakeAmount))) {
      Alert.alert('Error', 'Insufficient S token balance');
      return;
    }
    setIsLoading(true);
    try {
      const parsedAmount = ethers.utils.parseEther(stakeAmount);
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.stake(parsedAmount, lockPeriodNum);
      const tx = await contract.stake(parsedAmount, lockPeriodNum, {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Stake', stakeAmount);
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Staked ${stakeAmount} tokens for ${lockPeriod} days\nTx: ${truncateAddress(tx.hash)}`);
      await updateUserData(account, contract);
      resetInputs();
    } catch (error) {
      console.error('Stake error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Unstake tokens from a specific stake index
   */
  const unstakeTokens = async () => {
    if (!stakeIndex || isNaN(stakeIndex) || parseInt(stakeIndex) < 0) {
      Alert.alert('Error', 'Please enter a valid stake index');
      return;
    }
    if (!pointsToUse || isNaN(pointsToUse) || parseInt(pointsToUse) < 0) {
      Alert.alert('Error', 'Please enter valid Sonic Points to use');
      return;
    }
    setIsLoading(true);
    try {
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.unstake(parseInt(stakeIndex), parseInt(pointsToUse));
      const tx = await contract.unstake(parseInt(stakeIndex), parseInt(pointsToUse), {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Unstake');
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Unstaked tokens from stake index ${stakeIndex}\nTx: ${truncateAddress(tx.hash)}`);
      await updateUserData(account, contract);
      resetInputs();
    } catch (error) {
      console.error('Unstake error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Claim accumulated rewards
   */
  const claimRewards = async () => {
    setIsLoading(true);
    try {
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.claimRewards();
      const tx = await contract.claimRewards({
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Claim Rewards');
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Rewards claimed\nTx: ${truncateAddress(tx.hash)}`);
      await updateUserData(account, contract);
    } catch (error) {
      console.error('Claim rewards error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Bridge tokens between Sonic and Ethereum
   */
  const bridgeTokens = async () => {
    if (!bridgeAmount || isNaN(bridgeAmount) || parseFloat(bridgeAmount) <= 0) {
      Alert.alert('Error', 'Please enter a valid bridge amount');
      return;
    }
    if (!recipient || !isValidAddress(recipient)) {
      Alert.alert('Error', 'Please enter a valid recipient address');
      return;
    }
    if (!S_TOKEN_ADDRESS) {
      Alert.alert('Error', 'Missing token address configuration');
      return;
    }
    if (!(await checkBalance(bridgeAmount))) {
      Alert.alert('Error', 'Insufficient S token balance');
      return;
    }
    setIsLoading(true);
    try {
      const parsedAmount = ethers.utils.parseEther(bridgeAmount);
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.bridgeTokens(S_TOKEN_ADDRESS, parsedAmount, recipient, toEthereum);
      const tx = await contract.bridgeTokens(S_TOKEN_ADDRESS, parsedAmount, recipient, toEthereum, {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Bridge', bridgeAmount);
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Bridged ${bridgeAmount} tokens to ${truncateAddress(recipient)}\nTx: ${truncateAddress(tx.hash)}`);
      resetInputs();
    } catch (error) {
      console.error('Bridge error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Delegate tokens to a validator
   */
  const delegateToValidator = async () => {
    if (!delegateAmount || isNaN(delegateAmount) || parseFloat(delegateAmount) <= 0) {
      Alert.alert('Error', 'Please enter a valid delegate amount');
      return;
    }
    if (!validator || !isValidAddress(validator)) {
      Alert.alert('Error', 'Please enter a valid validator address');
      return;
    }
    if (!(await checkBalance(delegateAmount))) {
      Alert.alert('Error', 'Insufficient S token balance');
      return;
    }
    setIsLoading(true);
    try {
      const parsedAmount = ethers.utils.parseEther(delegateAmount);
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.delegateToValidator(validator, parsedAmount);
      const tx = await contract.delegateToValidator(validator, parsedAmount, {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Delegate', delegateAmount);
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Delegated ${delegateAmount} tokens to validator ${truncateAddress(validator)}\nTx: ${truncateAddress(tx.hash)}`);
      resetInputs();
    } catch (error) {
      console.error('Delegate error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Create a governance proposal
   */
  const createProposal = async () => {
    if (!descriptionHash) {
      Alert.alert('Error', 'Please enter a valid description hash');
      return;
    }
    if (!merkleRoot || !ethers.utils.isHexString(merkleRoot, 32)) {
      Alert.alert('Error', 'Please enter a valid Merkle root (32 bytes hex)');
      return;
    }
    if (!snapshotTimestamp || isNaN(snapshotTimestamp) || parseInt(snapshotTimestamp) <= 0) {
      Alert.alert('Error', 'Please enter a valid snapshot timestamp');
      return;
    }
    setIsLoading(true);
    try {
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.createProposal(ethers.utils.id(descriptionHash), merkleRoot, parseInt(snapshotTimestamp));
      const tx = await contract.createProposal(ethers.utils.id(descriptionHash), merkleRoot, parseInt(snapshotTimestamp), {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Create Proposal');
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Proposal created\nTx: ${truncateAddress(tx.hash)}`);
      resetInputs();
    } catch (error) {
      console.error('Proposal error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Verify voter eligibility for a proposal
   */
  const verifyProposalVoter = async () => {
    if (!proposalId || isNaN(proposalId) || parseInt(proposalId) < 0) {
      Alert.alert('Error', 'Please enter a valid proposal ID');
      return;
    }
    if (!merkleProof) {
      Alert.alert('Error', 'Please enter a valid Merkle proof');
      return;
    }
    setIsLoading(true);
    try {
      const proofArray = merkleProof.split(',').map(item => item.trim()).filter(item => ethers.utils.isHexString(item));
      if (proofArray.length === 0) {
        throw new Error('Invalid Merkle proof format');
      }
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.verifyProposalVoter(parseInt(proposalId), proofArray);
      const tx = await contract.verifyProposalVoter(parseInt(proposalId), proofArray, {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Verify Voter');
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Voter verified for proposal ${proposalId}\nTx: ${truncateAddress(tx.hash)}`);
      resetInputs();
    } catch (error) {
      console.error('Verify voter error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Propose a contract upgrade
   */
  const proposeUpgrade = async () => {
    if (!newImplementation || !isValidAddress(newImplementation)) {
      Alert.alert('Error', 'Please enter a valid new implementation address');
      return;
    }
    if (!descriptionHash) {
      Alert.alert('Error', 'Please enter a valid description hash');
      return;
    }
    setIsLoading(true);
    try {
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.proposeUpgrade(newImplementation, ethers.utils.id(descriptionHash));
      const tx = await contract.proposeUpgrade(newImplementation, ethers.utils.id(descriptionHash), {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Propose Upgrade');
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Upgrade proposed\nTx: ${truncateAddress(tx.hash)}`);
      resetInputs();
    } catch (error) {
      console.error('Propose upgrade error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  /**
   * Confirm a proposed upgrade
   */
  const confirmUpgrade = async () => {
    if (!proposalId || isNaN(proposalId) || parseInt(proposalId) < 0) {
      Alert.alert('Error', 'Please enter a valid proposal ID');
      return;
    }
    setIsLoading(true);
    try {
      const feeData = await provider.getFeeData();
      const gasEstimate = await contract.estimateGas.confirmUpgrade(parseInt(proposalId));
      const tx = await contract.confirmUpgrade(parseInt(proposalId), {
        gasLimit: gasEstimate.mul(120).div(100),
        maxFeePerGas: feeData.maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
      });
      addTransaction(tx.hash, 'Confirm Upgrade');
      await tx.wait();
      setTxHash(tx.hash);
      Alert.alert('Success', `Upgrade confirmed for proposal ${proposalId}\nTx: ${truncateAddress(tx.hash)}`);
      resetInputs();
    } catch (error) {
      console.error('Confirm upgrade error:', error);
      Alert.alert('Error', getFriendlyErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  // Confirmation dialogs
  const confirmStake = () => {
    Alert.alert('Confirm Stake', `Stake ${stakeAmount} S tokens for ${lockPeriod} days?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: stakeTokens },
    ]);
  };

  const confirmUnstake = () => {
    Alert.alert('Confirm Unstake', `Unstake from stake index ${stakeIndex} using ${pointsToUse} Sonic Points?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: unstakeTokens },
    ]);
  };

  const confirmClaimRewards = () => {
    Alert.alert('Confirm Claim', 'Claim accumulated rewards?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: claimRewards },
    ]);
  };

  const confirmBridge = () => {
    Alert.alert('Confirm Bridge', `Bridge ${bridgeAmount} S tokens to ${truncateAddress(recipient)} (${toEthereum ? 'Sonic to Ethereum' : 'Ethereum to Sonic'})?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: bridgeTokens },
    ]);
  };

  const confirmDelegate = () => {
    Alert.alert('Confirm Delegate', `Delegate ${delegateAmount} S tokens to validator ${truncateAddress(validator)}?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: delegateToValidator },
    ]);
  };

  const confirmProposal = () => {
    Alert.alert('Confirm Proposal', `Create proposal with description hash ${descriptionHash}, Merkle root ${truncateAddress(merkleRoot)}, and snapshot ${snapshotTimestamp}?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: createProposal },
    ]);
  };

  const confirmVerifyVoter = () => {
    Alert.alert('Confirm Verify Voter', `Verify voter for proposal ${proposalId} with Merkle proof?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: verifyProposalVoter },
    ]);
  };

  const confirmProposeUpgrade = () => {
    Alert.alert('Confirm Propose Upgrade', `Propose upgrade to ${truncateAddress(newImplementation)} with description hash ${descriptionHash}?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: proposeUpgrade },
    ]);
  };

  const confirmConfirmUpgrade = () => {
    Alert.alert('Confirm Upgrade', `Confirm upgrade for proposal ${proposalId}?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: confirmUpgrade },
    ]);
  };

  // Debounced functions
  const debouncedStake = debounce(confirmStake);
  const debouncedUnstake = debounce(confirmUnstake);
  const debouncedClaimRewards = debounce(confirmClaimRewards);
  const debouncedBridge = debounce(confirmBridge);
  const debouncedDelegate = debounce(confirmDelegate);
  const debouncedProposal = debounce(confirmProposal);
  const debouncedVerifyVoter = debounce(confirmVerifyVoter);
  const debouncedProposeUpgrade = debounce(confirmProposeUpgrade);
  const debouncedConfirmUpgrade = debounce(confirmConfirmUpgrade);

  // Dynamic styles based on theme
  const styles = StyleSheet.create({
    container: {
      flex: 1,
      padding: 20,
      backgroundColor: isDarkMode ? '#212121' : '#f5f5f5',
    },
    header: {
      fontSize: 24,
      fontWeight: 'bold',
      marginBottom: 20,
      color: isDarkMode ? '#ffffff' : '#212121',
    },
    section: {
      fontSize: 18,
      fontWeight: 'bold',
      marginTop: 20,
      marginBottom: 10,
      color: isDarkMode ? '#ffffff' : '#212121',
    },
    input: {
      borderWidth: 1,
      borderColor: isDarkMode ? '#757575' : '#757575',
      padding: 10,
      marginBottom: 10,
      borderRadius: 5,
      backgroundColor: isDarkMode ? '#424242' : '#ffffff',
      color: isDarkMode ? '#ffffff' : '#212121',
    },
    infoText: {
      fontSize: 16,
      color: isDarkMode ? '#ffffff' : '#212121',
      marginVertical: 2,
    },
    loadingOverlay: {
      position: 'absolute',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      backgroundColor: isDarkMode ? 'rgba(0,0,0,0.8)' : 'rgba(0,0,0,0.7)',
      justifyContent: 'center',
      alignItems: 'center',
      zIndex: 1000,
    },
    loadingText: {
      color: '#ffffff',
      marginTop: 10,
    },
    txHash: {
      fontSize: 14,
      color: isDarkMode ? '#bbbbbb' : '#424242',
      marginTop: 10,
    },
    stakeItem: {
      padding: 10,
      borderBottomWidth: 1,
      borderBottomColor: isDarkMode ? '#616161' : '#bdbdbd',
      backgroundColor: isDarkMode ? '#424242' : '#ffffff',
      borderRadius: 5,
      marginBottom: 5,
    },
    transactionItem: {
      padding: 10,
      borderBottomWidth: 1,
      borderBottomColor: isDarkMode ? '#616161' : '#bdbdbd',
      backgroundColor: isDarkMode ? '#424242' : '#ffffff',
      borderRadius: 5,
      marginBottom: 5,
    },
    transactionText: {
      color: isDarkMode ? '#bbdefb' : '#1a73e8',
      fontSize: 14,
    },
    lockPeriodOptions: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      marginBottom: 10,
    },
    themeToggleContainer: {
      flexDirection: 'row',
      alignItems: 'center',
      marginBottom: 20,
    },
    themeToggleText: {
      color: isDarkMode ? '#ffffff' : '#212121',
      marginRight: 10,
    },
  });

  return (
    <View style={styles.container} accessible accessibilityLabel="Staking Interface">
      {isLoading && (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="large" color="#ffffff" />
          <Text style={styles.loadingText}>Processing Transaction...</Text>
        </View>
      )}
      <View style={styles.themeToggleContainer}>
        <Text style={styles.themeToggleText}>Dark Mode</Text>
        <Switch
          value={isDarkMode}
          onValueChange={toggleDarkMode}
          accessibilityLabel="Toggle Dark Mode"
          accessibilityHint="Switch between light and dark theme"
        />
      </View>
      <Text style={styles.header} accessibilityLabel="AfroVibe Staking Title">
        AfroVibe Staking
      </Text>
      {!isWalletConnected ? (
        <Button
          title="Connect Wallet"
          onPress={connectWallet}
          disabled={isLoading}
          color={isDarkMode ? '#bbdefb' : '#1a73e8'}
          accessibilityLabel="Connect Wallet"
          accessibilityHint="Connect your wallet using Web3Auth"
        />
      ) : (
        <>
          <Button
            title="Disconnect Wallet"
            onPress={disconnectWallet}
            disabled={isLoading}
            color={isDarkMode ? '#ef5350' : '#d32f2f'}
            accessibilityLabel="Disconnect Wallet"
            accessibilityHint="Disconnect your wallet and clear session"
          />
          <Text style={styles.infoText} accessibilityLabel={`Account Address: ${truncateAddress(account)}`}>
            Account: {truncateAddress(account)}
          </Text>
          <Text style={styles.infoText} accessibilityLabel={`Sonic Points: ${sonicPoints}`}>
            Sonic Points: {sonicPoints}
          </Text>
          <Text style={styles.infoText} accessibilityLabel={`Total Staked: ${stakedAmount} S tokens`}>
            Total Staked: {stakedAmount} S
          </Text>
          {txHash && (
            <Text style={styles.txHash} accessibilityLabel={`Last Transaction: ${truncateAddress(txHash)}`}>
              Last Tx: {truncateAddress(txHash)}
            </Text>
          )}

          {transactions.length > 0 && (
            <>
              <Text style={styles.section} accessibilityLabel="Recent Transactions">
                Recent Transactions
              </Text>
              {transactions.map((tx, index) => (
                <TouchableOpacity
                  key={index}
                  onPress={() => Linking.openURL(`${BLOCK_EXPLORER_URL}${tx.hash}`)}
                  style={styles.transactionItem}
                  accessibilityLabel={`Transaction ${tx.type}: ${truncateAddress(tx.hash)}`}
                  accessibilityHint="Open transaction in block explorer"
                >
                  <Text style={styles.transactionText}>
                    {tx.type}: {truncateAddress(tx.hash)} ({tx.timestamp})
                  </Text>
                  <Text style={styles.transactionText}>
                    Status: {tx.status}
                  </Text>
                  {tx.amount && (
                    <Text style={styles.transactionText}>
                      Amount: {tx.amount} S
                    </Text>
                  )}
                  {tx.gasUsed && (
                    <Text style={styles.transactionText}>
                      Gas Used: {parseFloat(tx.gasUsed).toFixed(2)} Gwei
                    </Text>
                  )}
                </TouchableOpacity>
              ))}
            </>
          )}

          {stakes.length > 0 && (
            <>
              <Text style={styles.section} accessibilityLabel="Active Stakes">
                Active Stakes
              </Text>
              {stakes.map((stake) => (
                <View
                  key={stake.index}
                  style={styles.stakeItem}
                  accessibilityLabel={`Stake Index ${stake.index}`}
                >
                  <Text style={styles.infoText}>Index: {stake.index}</Text>
                  <Text style={styles.infoText}>Amount: {stake.amount} S</Text>
                  <Text style={styles.infoText}>Lock Period: {stake.lockPeriod} days</Text>
                  <Text style={styles.infoText}>Ends: {stake.endTime}</Text>
                </View>
              ))}
            </>
          )}

          <Text style={styles.section} accessibilityLabel="Stake Tokens Section">
            Stake Tokens
          </Text>
          <TextInput
            style={styles.input}
            placeholder="Amount (S)"
            value={stakeAmount}
            onChangeText={setStakeAmount}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Stake Amount Input"
            accessibilityHint="Enter the amount of S tokens to stake"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Lock Period (days)"
            value={lockPeriod}
            onChangeText={setLockPeriod}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Lock Period Input"
            accessibilityHint="Enter the lock period in days (1 to 365)"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <View style={styles.lockPeriodOptions}>
            {lockPeriodOptions.map((days) => (
              <Button
                key={days}
                title={`${days} days`}
                onPress={() => setLockPeriod(days.toString())}
                disabled={isLoading}
                color={isDarkMode ? '#bbdefb' : '#1a73e8'}
                accessibilityLabel={`Set Lock Period to ${days} days`}
                accessibilityHint={`Set the lock period to ${days} days`}
              />
            ))}
          </View>
          <Button
            title="Stake"
            onPress={debouncedStake}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Stake Tokens"
            accessibilityHint="Stake the specified amount of S tokens"
          />

          <Text style={styles.section} accessibilityLabel="Unstake Tokens Section">
            Unstake Tokens
          </Text>
          <TextInput
            style={styles.input}
            placeholder="Stake Index"
            value={stakeIndex}
            onChangeText={setStakeIndex}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Stake Index Input"
            accessibilityHint="Enter the stake index to unstake"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Sonic Points to Use"
            value={pointsToUse}
            onChangeText={setPointsToUse}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Sonic Points Input"
            accessibilityHint="Enter the amount of Sonic Points to use for unstaking"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <Button
            title="Unstake"
            onPress={debouncedUnstake}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Unstake Tokens"
            accessibilityHint="Unstake tokens from the specified stake index"
          />

          <Text style={styles.section} accessibilityLabel="Claim Rewards Section">
            Claim Rewards
          </Text>
          <Button
            title="Claim Rewards"
            onPress={debouncedClaimRewards}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Claim Rewards"
            accessibilityHint="Claim accumulated staking rewards"
          />

          <Text style={styles.section} accessibilityLabel="Bridge Tokens Section">
            Bridge Tokens
          </Text>
          <Text style={styles.infoText} accessibilityLabel={`Bridge Direction: ${toEthereum ? 'Sonic to Ethereum' : 'Ethereum to Sonic'}`}>
            Bridge Direction: {toEthereum ? 'Sonic to Ethereum' : 'Ethereum to Sonic'}
          </Text>
          <Button
            title={toEthereum ? 'Switch to Sonic' : 'Switch to Ethereum'}
            onPress={() => setToEthereum(!toEthereum)}
            disabled={isLoading}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Switch Bridge Direction"
            accessibilityHint="Toggle between bridging to Sonic or Ethereum"
          />
          <TextInput
            style={styles.input}
            placeholder="Amount (S)"
            value={bridgeAmount}
            onChangeText={setBridgeAmount}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Bridge Amount Input"
            accessibilityHint="Enter the amount of S tokens to bridge"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Recipient Address"
            value={recipient}
            onChangeText={setRecipient}
            editable={!isLoading}
            accessibilityLabel="Recipient Address Input"
            accessibilityHint="Enter the recipient address for bridging"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <Button
            title="Bridge"
            onPress={debouncedBridge}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Bridge Tokens"
            accessibilityHint="Bridge the specified amount of S tokens"
          />

          <Text style={styles.section} accessibilityLabel="Delegate to Validator Section">
            Delegate to Validator
          </Text>
          <TextInput
            style={styles.input}
            placeholder="Validator Address"
            value={validator}
            onChangeText={setValidator}
            editable={!isLoading}
            accessibilityLabel="Validator Address Input"
            accessibilityHint="Enter the validator address for delegation"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Amount (S)"
            value={delegateAmount}
            onChangeText={setDelegateAmount}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Delegate Amount Input"
            accessibilityHint="Enter the amount of S tokens to delegate"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <Button
            title="Delegate"
            onPress={debouncedDelegate}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Delegate Tokens"
            accessibilityHint="Delegate the specified amount of S tokens to a validator"
          />

          <Text style={styles.section} accessibilityLabel="Create Proposal Section">
            Create Proposal
          </Text>
          <TextInput
            style={styles.input}
            placeholder="Description Hash"
            value={descriptionHash}
            onChangeText={setDescriptionHash}
            editable={!isLoading}
            accessibilityLabel="Description Hash Input"
            accessibilityHint="Enter the description hash for the governance proposal"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Merkle Root"
            value={merkleRoot}
            onChangeText={setMerkleRoot}
            editable={!isLoading}
            accessibilityLabel="Merkle Root Input"
            accessibilityHint="Enter the Merkle root for the proposal"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Snapshot Timestamp"
            value={snapshotTimestamp}
            onChangeText={setSnapshotTimestamp}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Snapshot Timestamp Input"
            accessibilityHint="Enter the snapshot timestamp for the proposal"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <Button
            title="Create Proposal"
            onPress={debouncedProposal}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Create Proposal"
            accessibilityHint="Create a governance proposal with the specified details"
          />

          <Text style={styles.section} accessibilityLabel="Verify Proposal Voter Section">
            Verify Proposal Voter
          </Text>
          <TextInput
            style={styles.input}
            placeholder="Proposal ID"
            value={proposalId}
            onChangeText={setProposalId}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Proposal ID Input"
            accessibilityHint="Enter the proposal ID to verify voter eligibility"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Merkle Proof (comma-separated)"
            value={merkleProof}
            onChangeText={setMerkleProof}
            editable={!isLoading}
            accessibilityLabel="Merkle Proof Input"
            accessibilityHint="Enter the comma-separated Merkle proof for voter verification"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <Button
            title="Verify Voter"
            onPress={debouncedVerifyVoter}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Verify Voter"
            accessibilityHint="Verify voter eligibility for the specified proposal"
          />

          <Text style={styles.section} accessibilityLabel="Propose Upgrade Section">
            Propose Upgrade
          </Text>
          <TextInput
            style={styles.input}
            placeholder="New Implementation Address"
            value={newImplementation}
            onChangeText={setNewImplementation}
            editable={!isLoading}
            accessibilityLabel="New Implementation Address Input"
            accessibilityHint="Enter the new implementation contract address"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <TextInput
            style={styles.input}
            placeholder="Description Hash"
            value={descriptionHash}
            onChangeText={setDescriptionHash}
            editable={!isLoading}
            accessibilityLabel="Description Hash Input"
            accessibilityHint="Enter the description hash for the upgrade proposal"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <Button
            title="Propose Upgrade"
            onPress={debouncedProposeUpgrade}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Propose Upgrade"
            accessibilityHint="Propose a contract upgrade with the specified details"
          />

          <Text style={styles.section} accessibilityLabel="Confirm Upgrade Section">
            Confirm Upgrade
          </Text>
          <TextInput
            style={styles.input}
            placeholder="Proposal ID"
            value={proposalId}
            onChangeText={setProposalId}
            keyboardType="numeric"
            editable={!isLoading}
            accessibilityLabel="Proposal ID Input"
            accessibilityHint="Enter the proposal ID to confirm the upgrade"
            placeholderTextColor={isDarkMode ? '#bbbbbb' : '#757575'}
          />
          <Button
            title="Confirm Upgrade"
            onPress={debouncedConfirmUpgrade}
            disabled={isLoading || !isWalletConnected}
            color={isDarkMode ? '#bbdefb' : '#1a73e8'}
            accessibilityLabel="Confirm Upgrade"
            accessibilityHint="Confirm the upgrade for the specified proposal"
          />
        </>
      )}
    </View>
  );
};

export default Staking;
