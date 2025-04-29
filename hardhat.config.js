// Hardhat config
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");

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
    }
  }
};
