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

    // Validate Ethereum addresses
    const isValidAddress = (address) => ethers.utils.isAddress(address);
    const addressVars = [
      entryPoint,
      simpleAccountFactory,
      timelock,
      funder,
      dexAddress,
      stakingAddress,
      wethAddress,
      usdcAddress,
      otherFunderAddress,
      defaultAdmin,
    ];
    if (addressVars.some((addr) => !isValidAddress(addr))) {
      throw new Error("One or more environment variables contain invalid Ethereum addresses.");
    }

    // Validate code hash format
    if (!ethers.utils.isHexString(simpleAccountCodeHash, 32)) {
      throw new Error("SIMPLE_ACCOUNT_CODE_HASH must be a valid 32-byte hex string.");
    }

    // Log the deployer's address and balance
    const [deployer] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Deployer balance:", ethers.utils.formatEther(balance), "S tokens");

    // Deploy the Paymaster implementation contract
    console.log("Deploying AfroVibePaymaster implementation...");
    const Paymaster = await ethers.getContractFactory("AfroVibePaymaster");
    const paymasterImpl = await Paymaster.deploy(
      entryPoint,
      simpleAccountFactory,
      timelock,
      simpleAccountCodeHash,
      funder
    );
    await paymasterImpl.deployed();
    console.log("AfroVibePaymaster implementation deployed at:", paymasterImpl.address);

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
    console.log("Deploying AfroVibePaymaster proxy...");
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
      {
        initializer: "initialize",
        unsafeAllow: ["constructor"], // Required due to contract's constructor
      }
    );
    await paymasterProxy.deployed();
    console.log("AfroVibePaymaster proxy deployed at:", paymasterProxy.address);

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
    console.error("Deployment failed:", error);
    process.exit(1);
  });
