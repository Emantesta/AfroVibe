// utils/AfroVibePaymaster.js
const { ethers } = require("ethers"); // Use ethers directly for compatibility

// Contract ABI (loaded from Hardhat artifacts for development, or hardcoded for frontend)
let contractAbi;
try {
  // For Hardhat environment
  contractAbi = require("../artifacts/contracts/AfroVibePaymaster.sol/AfroVibePaymaster.json").abi;
} catch (error) {
  // Fallback for frontend (ensure ABI is included or fetched separately)
  console.warn("Hardhat artifacts not found. Provide ABI manually for frontend use.");
  contractAbi = []; // Replace with actual ABI in production
}

class AfroVibePaymaster {
  /**
   * Initialize the AfroVibePaymaster instance
   * @param {string} contractAddress - Deployed contract address
   * @param {ethers.Signer | ethers.Provider} signerOrProvider - Ethers signer (for tx) or provider (for queries)
   */
  constructor(contractAddress, signerOrProvider) {
    if (!ethers.utils.isAddress(contractAddress)) {
      throw new Error("Invalid contract address");
    }
    this.contract = new ethers.Contract(contractAddress, contractAbi, signerOrProvider);
    this.signerOrProvider = signerOrProvider;
  }

  // --- Transaction Functions ---

  /**
   * Deposit S tokens to the paymaster
   * @param {string} amount - Amount in S tokens (in wei)
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async deposit(amount) {
    if (!ethers.BigNumber.isBigNumberish(amount) || ethers.BigNumber.from(amount).lte(0)) {
      throw new Error("Invalid deposit amount");
    }
    const tx = await this.contract.deposit({ value: amount });
    return await tx.wait();
  }

  /**
   * Deposit ERC-20 tokens (e.g., wETH, USDC) to the paymaster
   * @param {string} tokenAddress - ERC-20 token address
   * @param {string} amount - Amount in token units (in wei)
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async depositToken(tokenAddress, amount) {
    if (!ethers.utils.isAddress(tokenAddress)) {
      throw new Error("Invalid token address");
    }
    if (!ethers.BigNumber.isBigNumberish(amount) || ethers.BigNumber.from(amount).lte(0)) {
      throw new Error("Invalid token amount");
    }
    const tx = await this.contract.depositToken(tokenAddress, amount);
    return await tx.wait();
  }

  /**
   * Propose adding/removing a valid target contract
   * @param {string} target - Target contract address
   * @param {boolean} isAdd - True to add, false to remove
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async proposeTargetUpdate(target, isAdd) {
    if (!ethers.utils.isAddress(target)) {
      throw new Error("Invalid target address");
    }
    const tx = await this.contract.proposeTargetUpdate(target, isAdd);
    return await tx.wait();
  }

  /**
   * Propose adding/removing a valid action type (e.g., POST, LIKE)
   * @param {string} actionType - Action type (keccak256 hash)
   * @param {boolean} isAdd - True to add, false to remove
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async proposeActionTypeUpdate(actionType, isAdd) {
    if (!ethers.utils.isHexString(actionType, 32)) {
      throw new Error("Invalid action type (must be 32-byte hex)");
    }
    const tx = await this.contract.proposeActionTypeUpdate(actionType, isAdd);
    return await tx.wait();
  }

  /**
   * Propose adding/removing a valid function selector
   * @param {string} selector - Function selector (4-byte hex)
   * @param {boolean} isAdd - True to add, false to remove
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async proposeSelectorUpdate(selector, isAdd) {
    if (!ethers.utils.isHexString(selector, 4)) {
      throw new Error("Invalid selector (must be 4-byte hex)");
    }
    const tx = await this.contract.proposeSelectorUpdate(selector, isAdd);
    return await tx.wait();
  }

  /**
   * Propose adding/removing a valid ERC-20 token
   * @param {string} token - Token address
   * @param {boolean} isAdd - True to add, false to remove
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async proposeTokenUpdate(token, isAdd) {
    if (!ethers.utils.isAddress(token)) {
      throw new Error("Invalid token address");
    }
    const tx = await this.contract.proposeTokenUpdate(token, isAdd);
    return await tx.wait();
  }

  /**
   * Update authorized funder status
   * @param {string} funderAddress - Funder address
   * @param {boolean} isAdd - True to add, false to remove
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async updateAuthorizedFunder(funderAddress, isAdd) {
    if (!ethers.utils.isAddress(funderAddress)) {
      throw new Error("Invalid funder address");
    }
    const tx = await this.contract.updateAuthorizedFunder(funderAddress, isAdd);
    return await tx.wait();
  }

  /**
   * Update maximum gas cost for sponsorship
   * @param {string} newMaxGasCost - New max gas cost (in wei)
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async updateMaxGasCost(newMaxGasCost) {
    if (!ethers.BigNumber.isBigNumberish(newMaxGasCost) || ethers.BigNumber.from(newMaxGasCost).lte(0)) {
      throw new Error("Invalid max gas cost");
    }
    const tx = await this.contract.updateMaxGasCost(newMaxGasCost);
    return await tx.wait();
  }

  /**
   * Update minimum deposit threshold
   * @param {string} newThreshold - New threshold (in wei)
   * @returns {Promise<ethers.ContractTransaction>} Transaction receipt
   */
  async updateMinDepositThreshold(newThreshold) {
    if (!ethers.BigNumber.isBigNumberish(newThreshold) || ethers.BigNumber.from(newThreshold).lte(0)) {
      throw new Error("Invalid threshold");
    }
    const tx = await this.contract.updateMinDepositThreshold(newThreshold);
    return await tx.wait();
  }

  // --- Query Functions ---

  /**
   * Get the maximum gas cost for sponsorship
   * @returns {Promise<ethers.BigNumber>} Max gas cost (in wei)
   */
  async getMaxGasCost() {
    return await this.contract.maxGasCost();
  }

  /**
   * Get the minimum deposit threshold
   * @returns {Promise<ethers.BigNumber>} Min deposit threshold (in wei)
   */
  async getMinDepositThreshold() {
    return await this.contract.minDepositThreshold();
  }

  /**
   * Check if a target contract is valid
   * @param {string} target - Target contract address
   * @returns {Promise<boolean>} True if valid
   */
  async isValidTarget(target) {
    if (!ethers.utils.isAddress(target)) {
      throw new Error("Invalid target address");
    }
    return await this.contract.validTargets(target);
  }

  /**
   * Check if an action type is valid
   * @param {string} actionType - Action type (keccak256 hash)
   * @returns {Promise<boolean>} True if valid
   */
  async isValidActionType(actionType) {
    if (!ethers.utils.isHexString(actionType, 32)) {
      throw new Error("Invalid action type (must be 32-byte hex)");
    }
    return await this.contract.validActionTypes(actionType);
  }

  /**
   * Check if a function selector is valid
   * @param {string} selector - Function selector (4-byte hex)
   * @returns {Promise<boolean>} True if valid
   */
  async isValidSelector(selector) {
    if (!ethers.utils.isHexString(selector, 4)) {
      throw new Error("Invalid selector (must be 4-byte hex)");
    }
    return await this.contract.validSelectors(selector);
  }

  /**
   * Check if an ERC-20 token is valid
   * @param {string} token - Token address
   * @returns {Promise<boolean>} True if valid
   */
  async isValidToken(token) {
    if (!ethers.utils.isAddress(token)) {
      throw new Error("Invalid token address");
    }
    return await this.contract.validTokens(token);
  }

  /**
   * Check if an address is an authorized funder
   * @param {string} funder - Funder address
   * @returns {Promise<boolean>} True if authorized
   */
  async isAuthorizedFunder(funder) {
    if (!ethers.utils.isAddress(funder)) {
      throw new Error("Invalid funder address");
    }
    return await this.contract.authorizedFunders(funder);
  }

  // --- Event Handling ---

  /**
   * Listen for GasSponsored events
   * @param {Function} callback - Callback function (user, nonce, gasUsed, target, actionType)
   */
  onGasSponsored(callback) {
    this.contract.on("GasSponsored", (user, nonce, gasUsed, target, actionType) => {
      callback(user, nonce, gasUsed, target, actionType);
    });
  }

  /**
   * Listen for DepositFunded events
   * @param {Function} callback - Callback function (funder, amount)
   */
  onDepositFunded(callback) {
    this.contract.on("DepositFunded", (funder, amount) => {
      callback(funder, amount);
    });
  }

  /**
   * Listen for TokenDepositFunded events
   * @param {Function} callback - Callback function (funder, token, amount)
   */
  onTokenDepositFunded(callback) {
    this.contract.on("TokenDepositFunded", (funder, token, amount) => {
      callback(funder, token, amount);
    });
  }

  /**
   * Listen for TargetUpdated events
   * @param {Function} callback - Callback function (target, isAdd)
   */
  onTargetUpdated(callback) {
    this.contract.on("TargetUpdated", (target, isAdd) => {
      callback(target, isAdd);
    });
  }

  // --- Utility Functions ---

  /**
   * Get the contract instance for direct interaction
   * @returns {ethers.Contract} Ethers contract instance
   */
  getContract() {
    return this.contract;
  }

  /**
   * Helper to compute action type hash
   * @param {string} action - Action string (e.g., "POST", "LIKE")
   * @returns {string} keccak256 hash
   */
  static computeActionTypeHash(action) {
    return ethers.utils.id(action);
  }

  /**
   * Helper to compute function selector
   * @param {string} signature - Function signature (e.g., "swap(address,uint256)")
   * @returns {string} 4-byte selector
   */
  static computeSelector(signature) {
    return ethers.utils.id(signature).slice(0, 10); // First 4 bytes
  }
}

module.exports = AfroVibePaymaster;
