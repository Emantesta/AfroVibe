// Fiat-to-USDC on-ramps
// Onramper’s widget integrates with MobilePayment.js

import { OnrampWebSDK } from '@onramp.money/onramp-web-sdk';

const buyUSDC = async (amount, paymentMethod) => {
  const walletAddress = await simpleAccountFactory.getAccountAddress(userAddress, salt);
  const onramper = new OnrampWebSDK({
    appId: process.env.ONRAMPER_APP_ID,
    walletAddress,
    fiatAmount: amount,
    fiatCurrency: paymentMethod === 'MTN_MoMo' ? 'NGN' : 'USD',
    cryptoAsset: 'USDC',
    chain: 'Sonic'
  });
  
  function subsidizeOnRampFee(address user, uint256 fee) external onlyOwner {
  require(isNewUser(user), "Not a new user");
  IERC20(usdc).transfer(user, fee);
  emit FeeSubsidized(user, fee);
}
  const { fee, provider } = await onramper.getBestProvider();
  if (fee && isNewUser(userAddress)) {
    await subsidizeFee(userAddress, fee); // Refund $0.70 for new users
  }
  onramper.show();
  return onramper.transactionId;
};
