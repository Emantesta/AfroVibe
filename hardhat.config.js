// Hardhat config
require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-waffle");
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    sonic: {
      url: process.env.SONIC_RPC_URL || "https://rpc.sonic.network",
      accounts: [process.env.PRIVATE_KEY]
    },
    hardhat: {
      chainId: 1337,
      gas: 12000000,
      blockGasLimit: 12000000
    },
    paths: {
    sources: "./contracts",
    tests: "./tests",
    cache: "./cache",
    artifacts: "./artifacts"
   },
   etherscan: {
   apiKey: process.env.SONICSCAN_API_KEY || "",
   customChains: [
    {
      network: "sonic",
      chainId: parseInt(process.env.SONIC_CHAIN_ID) || 64165,
      urls: {
        apiURL: "https://api.sonicscan.org/api",
        browserURL: "https://sonicscan.org",
      },
    },
  ],
 };
