// scripts/grantFunderRole.js
require("dotenv").config();
const { ethers } = require("hardhat");

async function grantFunderRole() {
  const paymasterFunderAddress = process.env.PAYMASTER_FUNDER_ADDRESS;
  const adminPrivateKey = process.env.ADMIN_PRIVATE_KEY;
  const newFunderAddress = process.env.NEW_FUNDER_ADDRESS;

  if (!paymasterFunderAddress || !adminPrivateKey || !newFunderAddress) {
    throw new Error("Missing environment variables");
  }

  const provider = ethers.provider;
  const admin = new ethers.Wallet(adminPrivateKey, provider);
  const PaymasterFunder = await ethers.getContractAt("PaymasterFunder", paymasterFunderAddress, admin);

  console.log(`Granting FUNDER_ROLE to ${newFunderAddress}...`);
  const tx = await PaymasterFunder.grantFunderRole(newFunderAddress);
  await tx.wait();
  console.log("FUNDER_ROLE granted, tx hash:", tx.hash);
}

grantFunderRole().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
