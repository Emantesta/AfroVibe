const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("AfroVibePaymaster", function () {
  it("should deploy and initialize correctly", async function () {
    const Paymaster = await ethers.getContractFactory("AfroVibePaymaster");
    const paymasterImpl = await Paymaster.deploy(
      "0xYourEntryPointAddress",
      "0xYourSimpleAccountFactoryAddress",
      "0xYourTimelockAddress",
      "0xYourCodeHash",
      "0xYourFunderAddress"
    );
    await paymasterImpl.deployed();

    const paymasterProxy = await upgrades.deployProxy(Paymaster, [
      ["0xYourDexAddress", "0xYourStakingAddress"],
      ethers.utils.parseUnits("0.1", "ether"),
      ethers.utils.parseUnits("1", "ether"),
      [ethers.utils.id("POST"), ethers.utils.id("LIKE")],
      [ethers.utils.id("swap(address,uint256)"), ethers.utils.id("stake(uint256)")],
      ["0xYourWethAddress", "0xYourUsdcAddress"],
      ["0xYourFunderAddress", "0xYourOtherFunderAddress"],
      "0xYourAdminAddress",
    ], { initializer: "initialize", unsafeAllow: ["constructor"] });

    expect(await paymasterProxy.maxGasCost()).to.equal(ethers.utils.parseUnits("0.1", "ether"));
  });
});
