// Event handlers

export function handleStaked(event: Staked): void {
  let stake = new Stake(event.transaction.hash.toHex());
  stake.user = event.params.user;
  stake.amount = event.params.amount;
  stake.lockPeriod = event.params.lockPeriod;
  stake.save();
}
