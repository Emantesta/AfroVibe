// scripts/deployTimelock.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const Timelock = await ethers.getContractFactory("TimelockControllerUpgradeable");
  const minDelay = 86400; // 1 day
  const proposers = ["<DAO_ADDRESS>"];
  const executors = ["<DAO_ADDRESS>"];
  const admin = "<ADMIN_ADDRESS>";

  const timelock = await upgrades.deployProxy(
    Timelock,
    [minDelay, proposers, executors, admin],
    { initializer: "initialize" }
  );
  await timelock.deployed();
  console.log("Timelock deployed to:", timelock.address);
}

main();
