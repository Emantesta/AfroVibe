// scripts/deployPaymaster.js
require('dotenv').config(); // Load environment variables from .env file
const { ethers, upgrades } = require("hardhat");

async function deployPaymaster() {
  try {
    // Load configuration from environment variables
    const entryPoint = process.env.ENTRY_POINT_ADDRESS;
    const simpleAccountFactory = process.env.SIMPLE_ACCOUNT_FACTORY_ADDRESS;
    const timelock = process.env.TIMELOCK_CONTROLLER_ADDRESS;
    const funder = process.env.PAYMASTER_FUNDER_ADDRESS;
    const simpleAccountCodeHash = process.env.SIMPLE_ACCOUNT_CODE_HASH;
    const dexAddress = process.env.DEX_ADDRESS;
    const stakingAddress = process.env.STAKING_ADDRESS;
    const wethAddress = process.env.WETH_ADDRESS;
    const usdcAddress = process.env.USDC_ADDRESS;
    const otherFunderAddress = process.env.OTHER_FUNDER_ADDRESS;
    const defaultAdmin = process.env.DEFAULT_ADMIN_ADDRESS;

    // Validate environment variables
    const requiredEnvVars = [
      entryPoint,
      simpleAccountFactory,
      timelock,
      funder,
      simpleAccountCodeHash,
      dexAddress,
      stakingAddress,
      wethAddress,
      usdcAddress,
      otherFunderAddress,
      defaultAdmin,
    ];
    if (requiredEnvVars.some((envVar) => !envVar)) {
      throw new Error("One or more required environment variables are missing. Check your .env file.");
    }

    // Log the deployer's address
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);

    // Deploy the Paymaster implementation contract
    console.log("Deploying Paymaster implementation...");
    const Paymaster = await ethers.getContractFactory("AfroVibePaymaster");
    const paymasterImpl = await Paymaster.deploy(
      entryPoint,
      simpleAccountFactory,
      timelock,
      simpleAccountCodeHash,
      funder
    );
    await paymasterImpl.deployed();
    console.log("Paymaster implementation deployed at:", paymasterImpl.address);

    // Configuration for the proxy initialization
    const validTargets = [dexAddress, stakingAddress];
    const maxGasCost = ethers.utils.parseUnits("0.1", "ether"); // 0.1 S tokens
    const minDepositThreshold = ethers.utils.parseUnits("1", "ether"); // 1 S token
    const validActionTypes = [ethers.utils.id("POST"), ethers.utils.id("LIKE")];
    const validSelectors = [
      ethers.utils.id("swap(address,uint256)"),
      ethers.utils.id("stake(uint256)"),
    ];
    const validTokens = [wethAddress, usdcAddress];
    const authorizedFunders = [funder, otherFunderAddress];
    const admin = defaultAdmin;

    // Deploy the Paymaster proxy contract
    console.log("Deploying Paymaster proxy...");
    const paymasterProxy = await upgrades.deployProxy(
      Paymaster,
      [
        validTargets,
        maxGasCost,
        minDepositThreshold,
        validActionTypes,
        validSelectors,
        validTokens,
        authorizedFunders,
        admin,
      ],
      { initializer: "initialize" } // Removed unsafeAllow for safety
    );
    await paymasterProxy.deployed();
    console.log("Paymaster proxy deployed at:", paymasterProxy.address);

    // Log completion
    console.log("Deployment completed successfully!");
    return { paymasterImpl, paymasterProxy };
  } catch (error) {
    console.error("Error during deployment:", error.message);
    process.exit(1);
  }
}

// Execute the deployment and handle errors
deployPaymaster()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
