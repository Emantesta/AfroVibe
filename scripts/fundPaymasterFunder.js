// scripts/fundPaymasterFunder.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function fundPaymasterFunder() {
  try {
    // Load environment variables
    const paymasterFunderAddress = process.env.PAYMASTER_FUNDER_ADDRESS;
    const sonicSTokenAddress = process.env.SONIC_S_TOKEN_ADDRESS;
    const funderPrivateKey = process.env.FUNDER_PRIVATE_KEY; // Private key of account with FUNDER_ROLE
    const fundingAmount = process.env.FUNDING_AMOUNT || "10"; // Amount in Sonic S tokens (default: 10)

    // Validate environment variables
    if (!paymasterFunderAddress || !sonicSTokenAddress || !funderPrivateKey) {
      throw new Error("Missing required environment variables: PAYMASTER_FUNDER_ADDRESS, SONIC_S_TOKEN_ADDRESS, or FUNDER_PRIVATE_KEY");
    }
    if (!ethers.utils.isAddress(paymasterFunderAddress) || !ethers.utils.isAddress(sonicSTokenAddress)) {
      throw new Error("Invalid contract or token address");
    }

    // Set up provider and signer
    const provider = ethers.provider; // Uses Hardhat's default provider (configured in hardhat.config.js)
    const funder = new ethers.Wallet(funderPrivateKey, provider);
    console.log("Funder address:", funder.address);

    // Check funder balance
    const funderBalance = await provider.getBalance(funder.address);
    console.log("Funder S balance:", ethers.utils.formatEther(funderBalance), "S tokens");

    // Load PaymasterFunder contract
    const PaymasterFunder = await ethers.getContractAt("PaymasterFunder", paymasterFunderAddress, funder);

    // Check if funder has FUNDER_ROLE
    const funderRole = await PaymasterFunder.FUNDER_ROLE();
    const hasFunderRole = await PaymasterFunder.hasRole(funderRole, funder.address);
    if (!hasFunderRole) {
      throw new Error("Funder does not have FUNDER_ROLE");
    }

    // Check if contract is paused
    const isPaused = await PaymasterFunder.paused();
    if (isPaused) {
      throw new Error("PaymasterFunder contract is paused");
    }

    // Get funding constraints
    const minFundingAmount = await PaymasterFunder.minFundingAmount();
    const maxFundingAmount = await PaymasterFunder.maxFundingAmount();
    const maxContractBalance = await PaymasterFunder.maxContractBalance();
    console.log("Min Funding Amount:", ethers.utils.formatEther(minFundingAmount), "Sonic S");
    console.log("Max Funding Amount:", ethers.utils.formatEther(maxFundingAmount), "Sonic S");
    console.log("Max Contract Balance:", ethers.utils.formatEther(maxContractBalance), "Sonic S");

    // Validate funding amount
    const amount = ethers.utils.parseEther(fundingAmount);
    if (amount.lt(minFundingAmount)) {
      throw new Error(`Funding amount (${fundingAmount} Sonic S) is below minimum (${ethers.utils.formatEther(minFundingAmount)} Sonic S)`);
    }
    if (amount.gt(maxFundingAmount)) {
      throw new Error(`Funding amount (${fundingAmount} Sonic S) exceeds maximum (${ethers.utils.formatEther(maxFundingAmount)} Sonic S)`);
    }

    // Check Sonic S token balance
    const SonicSToken = await ethers.getContractAt("IERC20", sonicSTokenAddress, funder);
    const tokenBalance = await SonicSToken.balanceOf(funder.address);
    console.log("Funder Sonic S balance:", ethers.utils.formatEther(tokenBalance), "Sonic S");
    if (tokenBalance.lt(amount)) {
      throw new Error(`Insufficient Sonic S balance: ${ethers.utils.formatEther(tokenBalance)} < ${fundingAmount}`);
    }

    // Check contract balance
    const currentContractBalance = await SonicSToken.balanceOf(paymasterFunderAddress);
    if (currentContractBalance.add(amount).gt(maxContractBalance)) {
      throw new Error("Funding would exceed max contract balance");
    }

    // Approve Sonic S tokens
    console.log(`Approving ${fundingAmount} Sonic S tokens for PaymasterFunder...`);
    const approveTx = await SonicSToken.approve(paymasterFunderAddress, amount);
    await approveTx.wait();
    console.log("Approval successful, tx hash:", approveTx.hash);

    // Fund PaymasterFunder
    console.log(`Funding PaymasterFunder with ${fundingAmount} Sonic S tokens...`);
    const fundTx = await PaymasterFunder.fund(amount);
    const receipt = await fundTx.wait();
    console.log("Funding successful, tx hash:", receipt.transactionHash);

    // Verify paymaster balance
    const paymasterAddress = await PaymasterFunder.paymaster();
    const paymasterBalance = await SonicSToken.balanceOf(paymasterAddress);
    console.log("Paymaster Sonic S balance:", ethers.utils.formatEther(paymasterBalance), "Sonic S");

  } catch (error) {
    console.error("Error funding PaymasterFunder:", error.message);
    process.exit(1);
  }
}

fundPaymasterFunder()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Funding failed:", error);
    process.exit(1);
  });
