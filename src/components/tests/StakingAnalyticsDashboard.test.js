import React from 'react';
import { render, waitFor, fireEvent } from '@testing-library/react-native';
import AnalyticsDashboard from './AnalyticsDashboard';
import { request } from 'graphql-request';
import { ethers } from 'ethers';
import WalletConnectProvider from '@walletconnect/ethereum-provider';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Linking from 'react-native-communications';
import * as env from '@env';

// Mock dependencies
jest.mock('graphql-request');
jest.mock('ethers');
jest.mock('@walletconnect/ethereum-provider');
jest.mock('@react-native-firebase/analytics', () => ({
  default: () => ({
    logScreenView: jest.fn(),
    logEvent: jest.fn(),
  }),
}));
jest.mock('retry-axios', () => ({
  rax: { attach: jest.fn() },
}));
jest.mock('@react-native-async-storage/async-storage', () => ({
  getItem: jest.fn(),
  setItem: jest.fn(),
}));
jest.mock('react-native-communications', () => ({
  Linking: { email: jest.fn() },
}));
jest.mock('@env', () => ({
  SONIC_RPC_URL: 'https://mock-rpc-url',
  STAKING_CONTRACT_ADDRESS: '0xMockStakingContract',
  SIMPLE_ACCOUNT_FACTORY_ADDRESS: '0xMockFactoryContract',
  ENTRY_POINT_ADDRESS: '0xMockEntryPoint',
  SUBGRAPH_URL: 'https://mock-subgraph-url',
  CHAIN_ID: '1234',
}));
jest.mock('@react-native-google-fonts/inter', () => ({
  useFonts: () => [true],
  Inter_400Regular: 'Inter_400Regular',
  Inter_700Bold: 'Inter_700Bold',
}));
jest.mock('react-native-modal', () => {
  const Modal = ({ isVisible, children, onBackdropPress }) =>
    isVisible ? (
      <View testID="modal" onPress={onBackdropPress}>
        {children}
      </View>
    ) : null;
  return Modal;
});

describe('AnalyticsDashboard', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders connect wallet button when no account', () => {
    const { getByText } = render(<AnalyticsDashboard />);
    expect(getByText('Connect Wallet')).toBeTruthy();
  });

  it('shows error modal with contact support on wallet connection failure', async () => {
    (WalletConnectProvider).mockImplementation(() => {
      throw new Error('Connection failed');
    });
    const { getByText, getByTestId } = render(<AnalyticsDashboard />);
    fireEvent.press(getByText('Connect Wallet'));
    await waitFor(() => {
      expect(getByTestId('modal')).toBeTruthy();
      expect(getByText('Failed to connect wallet after multiple attempts.')).toBeTruthy();
      expect(getByText('Contact Support')).toBeTruthy();
    });
    fireEvent.press(getByText('Contact Support'));
    expect(analytics().logEvent).toHaveBeenCalledWith('contact_support');
    expect(Linking.email).toHaveBeenCalled();
  });

  it('dismisses error modal', async () => {
    (WalletConnectProvider).mockImplementation(() => {
      throw new Error('Connection failed');
    });
    const { getByText, getByTestId } = render(<AnalyticsDashboard />);
    fireEvent.press(getByText('Connect Wallet'));
    await waitFor(() => {
      expect(getByTestId('modal')).toBeTruthy();
    });
    fireEvent.press(getByText('Dismiss'));
    expect(analytics().logEvent).toHaveBeenCalledWith('dismiss_error_modal');
  });

  it('loads saved theme from AsyncStorage', async () => {
    AsyncStorage.getItem.mockResolvedValue('light');
    const { getByAccessibilityLabel } = render(<AnalyticsDashboard />);
    await waitFor(() => {
      expect(AsyncStorage.getItem).toHaveBeenCalledWith('theme');
      expect(getByAccessibilityLabel('Switch to dark mode')).toBeTruthy();
    });
  });

  it('renders data correctly and logs analytics events', async () => {
    const mockProvider = {
      enable: jest.fn().mockResolvedValue(undefined),
      disconnect: jest.fn().mockResolvedValue(undefined),
    };
    (WalletConnectProvider).mockImplementation(() => mockProvider);
    const mockSigner = {
      getAddress: jest.fn().mockResolvedValue('0xOwnerAddress'),
    };
    const mockEthersProvider = {
      getSigner: () => mockSigner,
      getCode: jest.fn().mockResolvedValue('0x'),
    };
    (ethers.providers.Web3Provider).mockImplementation(() => mockEthersProvider);
    const mockContract = {
      sonicPoints: jest.fn().mockResolvedValue(ethers.BigNumber.from('1000000000000000000')),
    };
    const mockFactory = {
      getAccountAddress: jest.fn().mockResolvedValue('0xSmartAccount'),
      createAccount: jest.fn().mockResolvedValue(undefined),
    };
    (ethers.Contract)
      .mockImplementationOnce(() => mockContract)
      .mockImplementationOnce(() => mockFactory);
    (request).mockResolvedValue({
      stakes: [{ id: '1', user: '0xSmartAccount', amount: '1000000000000000000', lockPeriod: 30 }],
      delegateds: [{ user: '0xSmartAccount', validator: '0xValidator', amount: '500000000000000000' }],
      proposals: [{ id: '1', proposalId: '1', descriptionHash: 'hash', timestamp: 1697059200 }],
      upgradeProposals: [{ id: '1', newImplementation: '0xNewImpl', timelockEnd: 1697145600, validated: false, cancelled: false }],
    });

    const { getByText, getByAccessibilityLabel } = render(<AnalyticsDashboard />);
    fireEvent.press(getByText('Connect Wallet'));
    await waitFor(() => {
      expect(getByText('Analytics Dashboard')).toBeTruthy();
      expect(getByText('Account: 0xOwne...ress')).toBeTruthy();
      expect(getByText('Smart Account: 0xSmar...ount')).toBeTruthy();
      expect(getByText('Sonic Points: 1.0')).toBeTruthy();
      expect(getByText('Total Staked: 1.0 S')).toBeTruthy();
      expect(getByText('Amount: 1.0 S')).toBeTruthy();
      expect(getByText('Lock Period: 30 days')).toBeTruthy();
    });

    // Test analytics events
    expect(analytics().logEvent).toHaveBeenCalledWith('click_connect_wallet');
    fireEvent.press(getByAccessibilityLabel('Refresh Data'));
    expect(analytics().logEvent).toHaveBeenCalledWith('refresh_data');
    fireEvent.press(getByAccessibilityLabel('Disconnect Wallet'));
    expect(analytics().logEvent).toHaveBeenCalledWith('click_disconnect_wallet');
    fireEvent.press(getByAccessibilityLabel('Recent Stakes Section'));
    expect(analytics().logEvent).toHaveBeenCalledWith('view_recent_stakes');
    fireEvent.press(getByAccessibilityLabel('Stake 1'));
    expect(analytics().logEvent).toHaveBeenCalledWith('view_stake', {
      stake_id: '1',
      amount: '1000000000000000000',
    });
  });
});
