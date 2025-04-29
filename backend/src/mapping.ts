// Event handlers
import {
  Staked,
  Unstaked,
  RewardsClaimed,
  SonicPointsRedeemed,
  TokensBridged,
  ValidatorDelegated,
  ProposalCreated
} from "../generated/Staking/Staking";
import {
  Stake,
  Unstake,
  RewardClaim,
  SonicPointRedemption,
  BridgedToken,
  Delegated,
  Proposal
} from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";

export function handleStaked(event: Staked): void {
  let stake = new Stake(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  stake.user = event.params.user;
  stake.amount = event.params.amount;
  stake.lockPeriod = event.params.lockPeriod;
  stake.timestamp = event.block.timestamp;
  stake.save();
}

export function handleUnstaked(event: Unstaked): void {
  let unstake = new Unstake(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  unstake.user = event.params.user;
  unstake.amount = event.params.amount;
  unstake.penalty = event.params.penalty;
  unstake.timestamp = event.block.timestamp;
  unstake.save();
}

export function handleRewardsClaimed(event: RewardsClaimed): void {
  let claim = new RewardClaim(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  claim.user = event.params.user;
  claim.amount = event.params.amount;
  claim.timestamp = event.block.timestamp;
  claim.save();
}

export function handleSonicPointsRedeemed(event: SonicPointsRedeemed): void {
  let redemption = new SonicPointRedemption(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  redemption.user = event.params.user;
  redemption.points = event.params.points;
  redemption.timestamp = event.block.timestamp;
  redemption.save();
}

export function handleTokensBridged(event: TokensBridged): void {
  let bridge = new BridgedToken(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  bridge.user = event.params.user;
  bridge.amount = event.params.amount;
  bridge.timestamp = event.block.timestamp;
  bridge.save();
}

export function handleValidatorDelegated(event: ValidatorDelegated): void {
  let delegated = new Delegated(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  delegated.user = event.params.user;
  delegated.validator = event.params.validator;
  delegated.amount = event.params.amount;
  delegated.timestamp = event.block.timestamp;
  delegated.save();
}

export function handleProposalCreated(event: ProposalCreated): void {
  let proposal = new Proposal(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  proposal.proposalId = event.params.proposalId;
  proposal.descriptionHash = event.params.descriptionHash;
  proposal.timestamp = event.block.timestamp;
  proposal.save();
}
