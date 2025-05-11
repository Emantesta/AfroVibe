// frontend/src/utils/PaymasterFunder.js
const { ethers } = require("ethers");

// Contract ABI (loaded from Hardhat artifacts or frontend)
let contractAbi;
try {
  contractAbi = require("../abis/PaymasterFunder.json").abi; // Adjust for frontend
} catch (error) {
  console.warn("Hardhat artifacts not found. Provide ABI manually.");
  contractAbi = []; // Replace with actual ABI in production
}

class PaymasterFunder {
  constructor(contractAddress, signerOrProvider) {
    if (!ethers.utils.isAddress(contractAddress)) {
      throw new Error("Invalid contract address");
    }
    this.contract = new ethers.Contract(contractAddress, contractAbi, signerOrProvider);
    this.signerOrProvider = signerOrProvider;
  }

  // --- Transaction Functions ---

  async fund(amount) {
    if (!ethers.BigNumber.isBigNumberish(amount) || ethers.BigNumber.from(amount).lte(0)) {
      throw new Error("Invalid funding amount");
    }
    const tx = await this.contract.fund(amount);
    return await tx.wait();
  }

  async approveSonicSToken(spender, amount) {
    const sonicSTokenAddress = await this.contract.sonicSToken();
    const tokenContract = new ethers.Contract(
      sonicSTokenAddress,
      ["function approve(address spender, uint256 amount) external returns (bool)"],
      this.signerOrProvider
    );
    const tx = await tokenContract.approve(spender, amount);
    return await tx.wait();
  }

  async initiateUpdateMaxFundingAmount(newAmount) {
    if (!ethers.BigNumber.isBigNumberish(newAmount) || ethers.BigNumber.from(newAmount).lte(0)) {
      throw new Error("Invalid amount");
    }
    const tx = await this.contract.initiateUpdateMaxFundingAmount(newAmount);
    return await tx.wait();
  }

  async executeUpdateMaxFundingAmount(actionId) {
    if (!ethers.utils.isHexString(actionId, 32)) {
      throw new Error("Invalid action ID");
    }
    const tx = await this.contract.executeUpdateMaxFundingAmount(actionId);
    return await tx.wait();
  }

  async initiateEmergencyWithdraw(to, amount) {
    if (!ethers.utils.isAddress(to)) {
      throw new Error("Invalid recipient address");
    }
    if (!ethers.BigNumber.isBigNumberish(amount) || ethers.BigNumber.from(amount).lte(0)) {
      throw new Error("Invalid amount");
    }
    const tx = await this.contract.initiateEmergencyWithdraw(to, amount);
    return await tx.wait();
  }

  async executeEmergencyWithdraw(actionId, to) {
    if (!ethers.utils.isHexString(actionId, 32)) {
      throw new Error("Invalid action ID");
    }
    if (!ethers.utils.isAddress(to)) {
      throw new Error("Invalid recipient address");
    }
    const tx = await this.contract.executeEmergencyWithdraw(actionId, to);
    return await tx.wait();
  }

  async grantFunderRole(account) {
    if (!ethers.utils.isAddress(account)) {
      throw new Error("Invalid account address");
    }
    const tx = await this.contract.grantFunderRole(account);
    return await tx.wait();
  }

  async revokeFunderRole(account) {
    if (!ethers.utils.isAddress(account)) {
      throw new Error("Invalid account address");
    }
    const tx = await this.contract.revokeFunderRole(account);
    return await tx.wait();
  }

  async pause() {
    const tx = await this.contract.pause();
    return await tx.wait();
  }

  async unpause() {
    const tx = await this.contract.unpause();
    return await tx.wait();
  }

  // --- Query Functions ---

  async isFunder(address) {
    if (!ethers.utils.isAddress(address)) {
      throw new Error("Invalid address");
    }
    const funderRole = await this.contract.FUNDER_ROLE();
    return await this.contract.hasRole(funderRole, address);
  }

  async isAdmin(address) {
    if (!ethers.utils.isAddress(address)) {
      throw new Error("Invalid address");
    }
    const adminRole = await this.contract.DEFAULT_ADMIN_ROLE();
    return await this.contract.hasRole(adminRole, address);
  }

  async isPauser(address) {
    if (!ethers.utils.isAddress(address)) {
      throw new Error("Invalid address");
    }
    const pauserRole = await this.contract.PAUSER_ROLE();
    return await this.contract.hasRole(pauserRole, address);
  }

  async getMinFundingAmount() {
    return await this.contract.minFundingAmount();
  }

  async getMaxFundingAmount() {
    return await this.contract.maxFundingAmount();
  }

  async getMaxContractBalance() {
    return await this.contract.maxContractBalance();
  }

  async getPaymasterBalance() {
    return await this.contract.getPaymasterBalance();
  }

  async getFundingHistoryLength() {
    return await this.contract.getFundingHistoryLength();
  }

  async getFundingHistory(index) {
    return await this.contract.fundingHistory(index);
  }

  async isPaused() {
    return await this.contract.paused();
  }

  async getTimelockAction(actionId) {
    return await this.contract.timelockActions(actionId);
  }

  // --- Event Handling ---

  onFunded(callback) {
    this.contract.on("Funded", (paymaster, funder, amount) => {
      callback(paymaster, funder, amount);
    });
  }

  onTimelockInitiated(callback) {
    this.contract.on("TimelockInitiated", (actionId, action, amount, timestamp) => {
      callback(actionId, action, amount, timestamp);
    });
  }

  onTimelockExecuted(callback) {
    this.contract.on("TimelockExecuted", (actionId, action, amount) => {
      callback(actionId, action, amount);
    });
  }

  // --- Utility ---

  getContract() {
    return this.contract;
  }

  static computeActionId(action, amount, timestamp) {
    return ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(["string", "uint256", "uint256"], [action, amount, timestamp])
    );
  }
}

module.exports = PaymasterFunder;
