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
