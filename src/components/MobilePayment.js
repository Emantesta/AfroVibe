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
  const { fee, provider } = await onramper.getBestProvider();
  if (fee && isNewUser(userAddress)) {
    await subsidizeFee(userAddress, fee); // Refund $0.70 for new users
  }
  onramper.show();
  return onramper.transactionId;
};
