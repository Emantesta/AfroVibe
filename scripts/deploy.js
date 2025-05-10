async function main() {
  const Staking = await ethers.getContractFactory("Staking");
  const staking = await upgrades.deployProxy(Staking, [
    process.env.S_TOKEN_ADDRESS,
    process.env.USDC_ADDRESS,
    process.env.DEX_ROUTER_ADDRESS,
    process.env.STAKING_CONTRACT_ADDRESS,
    process.env.SIMPLE_ACCOUNT_FACTORY_ADDRESS,
    process.env.ENTRY_POINT_ADDRESS,
    process.env.BEETS_STAKING_ADDRESS,
    process.env.GOVERNANCE_ADDRESS,
    process.env.PLATFORM_DAO_ADDRESS,
    process.env.PAYMASTER_ADDRESS,
    process.env.TIMELOCK_ADDRESS,
    process.env.SONIC_GATEWAY_ADDRESS,
    process.env.SONIC_VALIDATOR_ADDRESS,
    process.env.FEE_RECIPIENT_ADDRESS
  ], { initializer: "initialize" });
  console.log("Staking deployed to:", staking.address);
}
// script deploying PaymasterFunder and AfroVibe-paymaster
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Load environment variables
  const entryPoint = process.env.ENTRY_POINT_ADDRESS;
  const simpleAccountFactory = process.env.SIMPLE_ACCOUNT_FACTORY_ADDRESS;
  const timelock = process.env.TIMELOCK_ADDRESS;
  const wethAddress = process.env.WETH_ADDRESS;
  const usdcAddress = process.env.USDC_ADDRESS;
  const maxGasCost = process.env.MAX_GAS_COST;
  const minDepositThreshold = process.env.MIN_DEPOSIT_THRESHOLD;
  const validTargets = process.env.VALID_TARGETS.split(",");
  const validActionTypes = process.env.VALID_ACTION_TYPES.split(",").map((type) => ethers.utils.id(type));
  const validSelectors = process.env.VALID_SELECTORS.split(",").map((selector) => ethers.utils.id(selector));
  const validTokens = process.env.VALID_TOKENS.split(",");
  const authorizedFunders = process.env.AUTHORIZED_FUNDERS.split(",");
  const defaultAdmin = process.env.DEFAULT_ADMIN;
  const maxFundingAmount = process.env.MAX_FUNDING_AMOUNT;

  // Validate environment variables
  if (!entryPoint || !simpleAccountFactory || !timelock || !defaultAdmin) {
    throw new Error("Missing required environment variables");
  }

  // Get deployer
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Compute SimpleAccount code hash
  const SimpleAccountFactory = await ethers.getContractFactory("SimpleAccountFactory");
  const factory = await SimpleAccountFactory.attach(simpleAccountFactory);
  const codeHash = ethers.utils.keccak256(factory.interface.encodeDeploy([]));
  console.log("SimpleAccount code hash:", codeHash);

  // Deploy PaymasterFunder
  const PaymasterFunder = await ethers.getContractFactory("PaymasterFunder");
  console.log("Deploying PaymasterFunder...");
  const paymasterFunder = await PaymasterFunder.deploy(ethers.constants.AddressZero, maxFundingAmount);
  await paymasterFunder.deployed();
  console.log("PaymasterFunder deployed to:", paymasterFunder.address);

  // Deploy AfroVibePaymaster
  const AfroVibePaymaster = await ethers.getContractFactory("AfroVibePaymaster");
  const entryPoint = process.env.ENTRY_POINT_ADDRESS;
  console.log("Deploying AfroVibePaymaster implementation...");
  const paymasterImpl = await AfroVibePaymaster.deploy(
    entryPoint,
    simpleAccountFactory,
    timelock,
    codeHash,
    paymasterFunder.address
  );
  await paymasterImpl.deployed();
  console.log("AfroVibePaymaster implementation:", paymasterImpl.address);

  // Deploy AfroVibePaymaster proxy
  console.log("Deploying AfroVibePaymaster proxy...");
  const paymasterProxy = await upgrades.deployProxy(
    AfroVibePaymaster,
    [
      validTargets,
      maxGasCost,
      minDepositThreshold,
      validActionTypes,
      validSelectors,
      validTokens,
      authorizedFunders,
      defaultAdmin,
    ],
    {
      initializer: "initialize",
      unsafeAllow: ["constructor"],
    }
  );
  await paymasterProxy.deployed();
  console.log("AfroVibePaymaster proxy:", paymasterProxy.address);

  // Update PaymasterFunder with paymaster address
  console.log("Updating PaymasterFunder with paymaster address...");
  const PaymasterFunderFactory = await ethers.getContractFactory("PaymasterFunder");
  const newPaymasterFunder = await PaymasterFunderFactory.deploy(paymasterProxy.address, maxFundingAmount);
  await newPaymasterFunder.deployed();
  console.log("New PaymasterFunder deployed to:", newPaymasterFunder.address);

  // Update AfroVibePaymaster with new funder address (via Timelock)
  console.log("Proposing funder update in AfroVibePaymaster...");
  const paymaster = await ethers.getContractAt("AfroVibePaymaster", paymasterProxy.address);
  const updateId = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ["address", "bool", "uint256"],
      [newPaymasterFunder.address, true, Math.floor(Date.now() / 1000)]
    )
  );
  await paymaster.updateAuthorizedFunder(newPaymasterFunder.address, true);
  console.log("Funder update proposed with ID:", updateId);

  // Fund PaymasterFunder with S tokens
  console.log("Funding PaymasterFunder with S tokens...");
  const fundAmount = ethers.utils.parseUnits("10", "ether"); // 10 S tokens
  await deployer.sendTransaction({
    to: newPaymasterFunder.address,
    value: fundAmount,
  });
  console.log("PaymasterFunder funded with:", ethers.utils.formatEther(fundAmount), "S tokens");

  // Verify contracts (if SonicScan is available)
  if (process.env.SONICSCAN_API_KEY) {
    console.log("Verifying contracts...");
    await hre.run("verify:verify", {
      address: paymasterImpl.address,
      constructorArguments: [
        entryPoint,
        simpleAccountFactory,
        timelock,
        codeHash,
        newPaymasterFunder.address,
      ],
    });
    await hre.run("verify:verify", {
      address: newPaymasterFunder.address,
      constructorArguments: [paymasterProxy.address, maxFundingAmount],
    });
  }

  console.log("Deployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
