// scripts/deployPaymasterFunder.js
require("dotenv").config();
const { ethers, upgrades } = require("hardhat");

async function deployPaymasterFunder() {
  try {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying with account:", deployer.address);

    const paymaster = process.env.PAYMASTER_ADDRESS;
    const sonicSToken = process.env.SONIC_S_TOKEN_ADDRESS;
    const multiSigWallet = process.env.MULTI_SIG_WALLET_ADDRESS;
    const minFundingAmount = ethers.utils.parseEther("1");
    const maxFundingAmount = ethers.utils.parseEther("1000");
    const maxContractBalance = ethers.utils.parseEther("10000");

    if (!paymaster || !sonicSToken || !multiSigWallet) {
      throw new Error("Missing environment variables");
    }

    console.log("Deploying PaymasterFunder proxy...");
    const PaymasterFunder = await ethers.getContractFactory("PaymasterFunder");
    const funderProxy = await upgrades.deployProxy(
      PaymasterFunder,
      [paymaster, sonicSToken, multiSigWallet, minFundingAmount, maxFundingAmount, maxContractBalance],
      { initializer: "initialize" }
    );
    await funderProxy.deployed();
    console.log("PaymasterFunder proxy deployed at:", funderProxy.address);

    return funderProxy;
  } catch (error) {
    console.error("Deployment error:", error.message);
    process.exit(1);
  }
}

deployPaymasterFunder()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });
