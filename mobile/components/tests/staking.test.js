const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("Staking", () => {
  let Staking, staking, sToken, beetsStaking, governance, sonicGateway, sonicValidator, timelock;
  let owner, user, dao;

  beforeEach(async () => {
    [owner, user, dao] = await ethers.getSigners();

    // Deploy mock S token
    const ERC20 = await ethers.getContractFactory("MockERC20");
    sToken = await ERC20.deploy("S Token", "S", ethers.utils.parseEther("1000000"));
    await sToken.deployed();

    // Deploy mock interfaces
    const MockBeetsStaking = await ethers.getContractFactory("MockBeetsStaking");
    beetsStaking = await MockBeetsStaking.deploy();
    await beetsStaking.deployed();

    const MockGovernance = await ethers.getContractFactory("MockGovernance");
    governance = await MockGovernance.deploy();
    await governance.deployed();

    const MockSonicGateway = await ethers.getContractFactory("MockSonicGateway");
    sonicGateway = await MockSonicGateway.deploy();
    await sonicGateway.deployed();

    const MockSonicValidator = await ethers.getContractFactory("MockSonicValidator");
    sonicValidator = await MockSonicValidator.deploy();
    await sonicValidator.deployed();

    const Timelock = await ethers.getContractFactory("TimelockControllerUpgradeable");
    timelock = await upgrades.deployProxy(
      Timelock,
      [86400, [dao.address], [dao.address], owner.address],
      { initializer: "initialize" }
    );
    await timelock.deployed();

    // Deploy Staking
    Staking = await ethers.getContractFactory("Staking");
    staking = await upgrades.deployProxy(Staking, [
      sToken.address,
      beetsStaking.address,
      governance.address,
      dao.address,
      owner.address, // Mock paymaster
      timelock.address,
      sonicGateway.address,
      sonicValidator.address,
      owner.address // Fee recipient
    ], { initializer: "initialize" });
    await staking.deployed();

    // Fund user with S tokens
    await sToken.transfer(user.address, ethers.utils.parseEther("1000"));
    await sToken.connect(user).approve(staking.address, ethers.utils.parseEther("1000"));
  });

  it("should allow staking and emit Staked event", async () => {
    const amount = ethers.utils.parseEther("100");
    const lockPeriod = 30;

    await expect(staking.connect(user).stake(amount, lockPeriod))
      .to.emit(staking, "Staked")
      .withArgs(user.address, amount, lockPeriod);

    const stake = await staking.stakes(user.address, 0);
    expect(stake.amount).to.equal(amount);
    expect(stake.lockEnd).to.be.closeTo(
      (await ethers.provider.getBlock("latest")).timestamp + lockPeriod * 86400,
      100
    );
    expect(await staking.sonicPoints(user.address)).to.equal(amount.div(1e18));
  });

  it("should allow unstaking with penalty and use Sonic Points", async () => {
    const amount = ethers.utils.parseEther("100");
    await staking.connect(user).stake(amount, 30);

    const pointsToUse = 1000;
    await expect(staking.connect(user).unstake(0, pointsToUse))
      .to.emit(staking, "Unstaked")
      .to.emit(staking, "SonicPointsRedeemed")
      .withArgs(user.address, pointsToUse);

    const expectedPenalty = amount.mul(1000).div(10000); // 10%
    const expectedAmount = amount.sub(expectedPenalty);
    expect(await sToken.balanceOf(user.address)).to.be.closeTo(
      ethers.utils.parseEther("900").add(expectedAmount),
      ethers.utils.parseEther("1")
    );
    expect(await staking.sonicPoints(user.address)).to.equal(0);
  });

  it("should claim rewards", async () => {
    await staking.connect(user).stake(ethers.utils.parseEther("100"), 30);
    await beetsStaking.setReward(user.address, ethers.utils.parseEther("10"));

    await expect(staking.connect(user).claimRewards())
      .to.emit(staking, "RewardsClaimed")
      .withArgs(user.address, ethers.utils.parseEther("10"));

    expect(await sToken.balanceOf(user.address)).to.be.closeTo(
      ethers.utils.parseEther("910"),
      ethers.utils.parseEther("1")
    );
  });

  it("should bridge tokens", async () => {
    const amount = ethers.utils.parseEther("100");
    await expect(staking.connect(user).bridgeTokens(sToken.address, amount, user.address, true))
      .to.emit(staking, "TokensBridged")
      .withArgs(user.address, amount);
  });

  it("should delegate to validator", async () => {
    const amount = ethers.utils.parseEther("100");
    const validator = owner.address;

    await expect(staking.connect(user).delegateToValidator(validator, amount))
      .to.emit(staking, "ValidatorDelegated")
      .withArgs(user.address, validator, amount);

    expect(await staking.delegatedAmounts(user.address, validator)).to.equal(amount);
  });

  it("should create a proposal", async () => {
    const descriptionHash = ethers.utils.id("Test proposal");
    await expect(staking.connect(dao).createProposal(descriptionHash))
      .to.emit(staking, "ProposalCreated")
      .withArgs(1, descriptionHash);
  });

  it("should verify proposal voter", async () => {
  const merkleRoot = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test"));
  const leaf = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["address"], [user.address]));
  const proof = []; // Simplified for test
  await staking.connect(dao).createProposal(ethers.utils.id("test"), merkleRoot, 0);
  await expect(staking.connect(user).verifyProposalVoter(1, proof))
    .to.emit(staking, "ProposalVerified")
    .withArgs(1, user.address, leaf);
});

it("should propose and confirm upgrade", async () => {
  const newImplementation = ethers.Wallet.createRandom().address;
  await expect(staking.connect(dao).proposeUpgrade(newImplementation, ethers.utils.id("upgrade")))
    .to.emit(staking, "UpgradeProposalCreated");
  await ethers.provider.send("evm_increaseTime", [86400]); // Simulate timelock
  await staking.connect(dao).confirmUpgrade(1);
  const proposal = await staking.upgradeProposals(1);
  expect(proposal.validated).to.be.true;
});
});
