import React, { createContext, useContext, useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { ethers } from 'ethers';
import { request, gql } from 'graphql-request';
import analytics from '@react-native-firebase/analytics';
import WalletConnectProvider from '@walletconnect/ethereum-provider';
import Icon from 'react-native-vector-icons/MaterialIcons';
import { useFonts, Inter_400Regular, Inter_700Bold } from '@react-native-google-fonts/inter';
import Animated, { ZoomIn, ZoomOut, BounceIn, Layout } from 'react-native-reanimated';
import LinearGradient from 'react-native-linear-gradient';
import Modal from 'react-native-modal';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Linking } from 'react-native-communications';
import { rax } from 'retry-axios';
import StakingABI from '../abis/Staking.json';
import SimpleAccountFactoryABI from '../abis/SimpleAccountFactory.json';
import {
  SONIC_RPC_URL,
  STAKING_CONTRACT_ADDRESS,
  SIMPLE_ACCOUNT_FACTORY_ADDRESS,
  ENTRY_POINT_ADDRESS,
  SUBGRAPH_URL,
  CHAIN_ID,
} from '@env';

// Theme Context
const ThemeContext = createContext();
const ThemeProvider = ({ children }) => {
  const [theme, setTheme] = useState('dark');

  useEffect(() => {
    // Load saved theme
    const loadTheme = async () => {
      try {
        const savedTheme = await AsyncStorage.getItem('theme');
        if (savedTheme) setTheme(savedTheme);
      } catch (err) {
        console.error('Failed to load theme:', err);
      }
    };
    loadTheme();
  }, []);

  const toggleTheme = async () => {
    const newTheme = theme === 'dark' ? 'light' : 'dark';
    setTheme(newTheme);
    try {
      await AsyncStorage.setItem('theme', newTheme);
      await analytics().logEvent('switch_theme', { theme: newTheme });
    } catch (err) {
      console.error('Failed to save theme:', err);
    }
  };

  return (
    <ThemeContext.Provider value={{ theme, toggleTheme }}>{children}</ThemeContext.Provider>
  );
};

// Theme-aware styles
const getStyles = (theme) =>
  StyleSheet.create({
    container: { flex: 1, padding: 20 },
    gradient: {
      colors: theme === 'dark' ? ['#4c669f', '#3b5998', '#192f6a'] : ['#e6f0fa', '#f5f7fa', '#dfe9f3'],
    },
    centered: { flex: 1, justifyContent: 'center', alignItems: 'center' },
    headerContainer: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
    header: {
      fontSize: 28,
      fontWeight: '700',
      color: theme === 'dark' ? '#fff' : '#333',
      fontFamily: 'Inter_700Bold',
    },
    refreshButton: { padding: 10 },
    themeButton: { padding: 10, marginLeft: 10 },
    disconnectButton: {
      backgroundColor: '#ff4444',
      padding: 10,
      borderRadius: 8,
      alignItems: 'center',
      marginBottom: 20,
    },
    disconnectButtonText: {
      color: '#fff',
      fontSize: 16,
      fontFamily: 'Inter_400Regular',
    },
    button: {
      backgroundColor: theme === 'dark' ? '#007bff' : '#005bb5',
      padding: 15,
      borderRadius: 8,
      alignItems: 'center',
      marginTop: 20,
    },
    buttonText: {
      color: '#fff',
      fontSize: 18,
      fontFamily: 'Inter_700Bold',
    },
    card: {
      backgroundColor: theme === 'dark' ? 'rgba(255, 255, 255, 0.1)' : 'rgba(0, 0, 0, 0.05)',
      borderRadius: 12,
      padding: 15,
      marginBottom: 20,
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.3,
      shadowRadius: 4,
      elevation: 5,
    },
    cardTitle: {
      fontSize: 20,
      fontWeight: '700',
      color: theme === 'dark' ? '#fff' : '#333',
      marginBottom: 10,
      fontFamily: 'Inter_700Bold',
    },
    cardText: {
      fontSize: 16,
      color: theme === 'dark' ? '#ddd' : '#555',
      marginBottom: 5,
      fontFamily: 'Inter_400Regular',
    },
    sectionHeader: { flexDirection: 'row', alignItems: 'center', marginBottom: 10 },
    sectionIcon: { marginRight: 10 },
    section: {
      fontSize: 20,
      fontWeight: '700',
      color: theme === 'dark' ? '#fff' : '#333',
      fontFamily: 'Inter_700Bold',
    },
    item: {
      backgroundColor: theme === 'dark' ? 'rgba(255, 255, 255, 0.05)' : 'rgba(0, 0, 0, 0.03)',
      padding: 15,
      borderRadius: 8,
      marginBottom: 10,
    },
    itemText: {
      fontSize: 14,
      color: theme === 'dark' ? '#ddd' : '#555',
      fontFamily: 'Inter_400Regular',
    },
    emptyText: {
      fontSize: 14,
      color: theme === 'dark' ? '#aaa' : '#777',
      fontStyle: 'italic',
      fontFamily: 'Inter_400Regular',
    },
    loading: { marginTop: 20 },
    error: {
      color: '#ff4444',
      textAlign: 'center',
      marginTop: 20,
      fontSize: 16,
      fontFamily: 'Inter_400Regular',
    },
    modal: {
      justifyContent: 'flex-end',
      margin: 0,
    },
    modalContent: {
      backgroundColor: theme === 'dark' ? '#333' : '#fff',
      padding: 20,
      borderTopLeftRadius: 12,
      borderTopRightRadius: 12,
    },
    modalTitle: {
      fontSize: 18,
      fontWeight: '700',
      color: theme === 'dark' ? '#fff' : '#333',
      marginBottom: 10,
      fontFamily: 'Inter_700Bold',
    },
    modalText: {
      fontSize: 16,
      color: theme === 'dark' ? '#ddd' : '#555',
      marginBottom: 20,
      fontFamily: 'Inter_400Regular',
    },
    modalButton: {
      backgroundColor: theme === 'dark' ? '#007bff' : '#005bb5',
      padding: 15,
      borderRadius: 8,
      alignItems: 'center',
      marginBottom: 10,
    },
    modalButtonText: {
      color: '#fff',
      fontSize: 16,
      fontFamily: 'Inter_700Bold',
    },
    modalCancelButton: {
      backgroundColor: theme === 'dark' ? '#555' : '#ccc',
      padding: 15,
      borderRadius: 8,
      alignItems: 'center',
      marginBottom: 10,
    },
    modalCancelButtonText: {
      color: theme === 'dark' ? '#fff' : '#333',
      fontSize: 16,
      fontFamily: 'Inter_700Bold',
    },
    modalSupportButton: {
      backgroundColor: theme === 'dark' ? '#ff4444' : '#cc0000',
      padding: 15,
      borderRadius: 8,
      alignItems: 'center',
    },
    modalSupportButtonText: {
      color: '#fff',
      fontSize: 16,
      fontFamily: 'Inter_700Bold',
    },
  });

const AnalyticsDashboard = () => {
  const { theme, toggleTheme } = useContext(ThemeContext);
  const [account, setAccount] = useState('');
  const [smartAccount, setSmartAccount] = useState('');
  const [sonicPoints, setSonicPoints] = useState('0');
  const [totalStaked, setTotalStaked] = useState('0');
  const [delegatedAmounts, setDelegatedAmounts] = useState([]);
  const [recentStakes, setRecentStakes] = useState([]);
  const [proposals, setProposals] = useState([]);
  const [upgradeProposals, setUpgradeProposals] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [modalVisible, setModalVisible] = useState(false);
  const [walletProvider, setWalletProvider] = useState(null);
  const [fontsLoaded] = useFonts({ Inter_400Regular, Inter_700Bold });

  const styles = getStyles(theme);

  // Format address for display
  const formatAddress = (address) => {
    if (!address) return '';
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  // Retry mechanism for WalletConnect
  const connectWalletWithRetry = async (attempts = 3, delay = 1000) => {
    for (let i = 0; i < attempts; i++) {
      try {
        const provider = new WalletConnectProvider({
          rpc: { [CHAIN_ID]: SONIC_RPC_URL },
          chainId: parseInt(CHAIN_ID),
        });
        await provider.enable();
        setWalletProvider(provider);
        const ethersProvider = new ethers.providers.Web3Provider(provider);
        const signer = ethersProvider.getSigner();
        const address = await signer.getAddress();
        setAccount(address);
        await analytics().logEvent('wallet_connected', { address });
        await analytics().logEvent('click_connect_wallet');
        return true;
      } catch (err) {
        console.error(`WalletConnect attempt ${i + 1} failed:`, err);
        if (i < attempts - 1) await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
    setError('Failed to connect wallet after multiple attempts.');
    setModalVisible(true);
    return false;
  };

  // Connect wallet
  const connectWallet = async () => {
    setLoading(true);
    const success = await connectWalletWithRetry();
    setLoading(false);
    if (success) setModalVisible(false);
  };

  // Disconnect wallet
  const disconnectWallet = async () => {
    if (walletProvider) {
      await walletProvider.disconnect();
      setWalletProvider(null);
      setAccount('');
      setSmartAccount('');
      setSonicPoints('0');
      setTotalStaked('0');
      setDelegatedAmounts([]);
      setRecentStakes([]);
      setProposals([]);
      setUpgradeProposals([]);
      await analytics().logEvent('wallet_disconnected');
      await analytics().logEvent('click_disconnect_wallet');
    }
  };

  // Refresh data
  const refreshData = async () => {
    if (!account) return;
    setLoading(true);
    await analytics().logEvent('refresh_data');
    await init();
  };

  // Retry after error
  const retryError = async () => {
    setModalVisible(false);
    setLoading(true);
    await analytics().logEvent('retry_error');
    await init();
  };

  // Contact support
  const contactSupport = async () => {
    setModalVisible(false);
    await analytics().logEvent('contact_support');
    Linking.email(
      ['support@yourapp.com'],
      'Analytics Dashboard Error',
      `Error: ${error}\n\nPlease provide details about the issue you encountered.`,
      null,
      null
    );
  };

  // Dismiss modal
  const dismissModal = async () => {
    setModalVisible(false);
    await analytics().logEvent('dismiss_error_modal');
  };

  // Initialize smart wallet and fetch data
  const init = async () => {
    if (!account || !walletProvider) return;
    setLoading(true);
    try {
      const ethersProvider = new ethers.providers.Web3Provider(walletProvider);
      const signer = ethersProvider.getSigner();

      // Initialize SimpleAccountFactory
      const factory = new ethers.Contract(
        SIMPLE_ACCOUNT_FACTORY_ADDRESS,
        SimpleAccountFactoryABI.abi,
        signer
      );

      // Create or get smart account
      const salt = ethers.utils.hexlify(ethers.utils.randomBytes(32));
      const smartAccountAddress = await factory.getAccountAddress(account, salt);
      if ((await ethersProvider.getCode(smartAccountAddress)) === '0x') {
        await factory.createAccount(account, salt);
        await analytics().logEvent('smart_account_created', { owner: account, smartAccount: smartAccountAddress });
      }
      setSmartAccount(smartAccountAddress);

      // Initialize staking contract with smart account
      const contract = new ethers.Contract(STAKING_CONTRACT_ADDRESS, StakingABI.abi, signer);
      const points = await contract.sonicPoints(smartAccountAddress);
      setSonicPoints(ethers.utils.formatEther(points));

      // GraphQL query with retry
      const query = gql`
        {
          stakes(where: { user: "${smartAccountAddress.toLowerCase()}" }, first: 5) {
            id
            user
            amount
            lockPeriod
          }
          delegateds(where: { user: "${smartAccountAddress.toLowerCase()}" }) {
            user
            validator
            amount
          }
          proposals(first: 5) {
            id
            proposalId
            descriptionHash
            timestamp
          }
          upgradeProposals(first: 5) {
            id
            newImplementation
            timelockEnd
            validated
            cancelled
          }
        }
      `;
      let response;
      try {
        rax.attach();
        response = await request(SUBGRAPH_URL, query, {}, { 'rax-config': { retry: 3, retryDelay: 1000 } });
      } catch (subgraphError) {
        console.error('Subgraph error:', subgraphError);
        setError('Subgraph is unavailable. Some data may be missing.');
        setModalVisible(true);
        response = { stakes: [], delegateds: [], proposals: [], upgradeProposals: [] };
      }

      setRecentStakes(response.stakes);
      setDelegatedAmounts(response.delegateds);
      setProposals(response.proposals);
      setUpgradeProposals(response.upgradeProposals);

      // Calculate total staked from subgraph
      const total = response.stakes.reduce(
        (sum, stake) => sum.add(ethers.BigNumber.from(stake.amount)),
        ethers.BigNumber.from(0)
      );
      setTotalStaked(ethers.utils.formatEther(total));

      // Log dashboard view
      await analytics().logScreenView({
        screen_name: 'AnalyticsDashboard',
        screen_class: 'AnalyticsDashboard',
      });
    } catch (error) {
      console.error('Error initializing:', error);
      setError('Failed to load data. Please try again.');
      setModalVisible(true);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (account && walletProvider) {
      init();
      const interval = setInterval(init, 30000); // Poll every 30 seconds
      return () => clearInterval(interval);
    }
  }, [account, walletProvider]);

  if (!fontsLoaded) {
    return null;
  }

  if (!account) {
    return (
      <LinearGradient style={styles.container} {...styles.gradient}>
        <View style={styles.centered}>
          <Text style={styles.header}>Analytics Dashboard</Text>
          <TouchableOpacity
            style={styles.button}
            onPress={connectWallet}
            accessible
            accessibilityLabel="Connect Wallet"
          >
            <Text style={styles.buttonText}>Connect Wallet</Text>
          </TouchableOpacity>
        </View>
      </LinearGradient>
    );
  }

  if (loading) {
    return (
      <LinearGradient style={styles.container} {...styles.gradient}>
        <ActivityIndicator
          size="large"
          color={theme === 'dark' ? '#fff' : '#333'}
          style={styles.loading}
          accessible
          accessibilityLabel="Loading dashboard"
        />
      </LinearGradient>
    );
  }

  return (
    <LinearGradient style={styles.container} {...styles.gradient}>
      <Modal
        isVisible={modalVisible}
        onBackdropPress={dismissModal}
        style={styles.modal}
      >
        <View style={styles.modalContent}>
          <Text style={styles.modalTitle}>Error</Text>
          <Text style={styles.modalText}>{error}</Text>
          <TouchableOpacity
            style={styles.modalButton}
            onPress={retryError}
            accessible
            accessibilityLabel="Retry"
          >
            <Text style={styles.modalButtonText}>Retry</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.modalSupportButton}
            onPress={contactSupport}
            accessible
            accessibilityLabel="Contact Support"
          >
            <Text style={styles.modalSupportButtonText}>Contact Support</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.modalCancelButton}
            onPress={dismissModal}
            accessible
            accessibilityLabel="Dismiss"
          >
            <Text style={styles.modalCancelButtonText}>Dismiss</Text>
          </TouchableOpacity>
        </View>
      </Modal>
      <ScrollView>
        <View style={styles.headerContainer}>
          <Text style={styles.header}>Analytics Dashboard</Text>
          <View style={{ flexDirection: 'row' }}>
            <TouchableOpacity
              style={styles.themeButton}
              onPress={toggleTheme}
              accessible
              accessibilityLabel={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
            >
              <Icon
                name={theme === 'dark' ? 'brightness-7' : 'brightness-4'}
                size={24}
                color={theme === 'dark' ? '#fff' : '#333'}
              />
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.refreshButton}
              onPress={refreshData}
              accessible
              accessibilityLabel="Refresh Data"
            >
              <Icon name="refresh" size={24} color={theme === 'dark' ? '#fff' : '#333'} />
            </TouchableOpacity>
          </View>
        </View>
        <TouchableOpacity
          style={styles.disconnectButton}
          onPress={disconnectWallet}
          accessible
          accessibilityLabel="Disconnect Wallet"
        >
          <Text style={styles.disconnectButtonText}>Disconnect Wallet</Text>
        </TouchableOpacity>
        <Animated.View
          entering={ZoomIn.delay(150).springify()}
          exiting={ZoomOut}
          layout={Layout.springify()}
          style={styles.card}
        >
          <Text style={styles.cardTitle}>Account Info</Text>
          <Text style={styles.cardText}>Account: {formatAddress(account)}</Text>
          <Text style={styles.cardText}>Smart Account: {formatAddress(smartAccount)}</Text>
          <Text style={styles.cardText}>Sonic Points: {sonicPoints}</Text>
          <Text style={styles.cardText}>Total Staked: {totalStaked} S</Text>
        </Animated.View>

        <Animated.View
          entering={BounceIn.delay(300).springify()}
          exiting={ZoomOut}
          layout={Layout.springify()}
          style={styles.card}
        >
          <View style={styles.sectionHeader}>
            <Icon
              name="lock"
              size={20}
              color={theme === 'dark' ? '#fff' : '#333'}
              style={styles.sectionIcon}
            />
            <Text
              style={styles.section}
              onPress={() => analytics().logEvent('view_recent_stakes')}
              accessible
              accessibilityLabel="Recent Stakes Section"
            >
              Recent Stakes
            </Text>
          </View>
          {recentStakes.length > 0 ? (
            recentStakes.map((stake, index) => (
              <TouchableOpacity
                key={index}
                style={styles.item}
                onPress={() =>
                  analytics().logEvent('view_stake', { stake_id: stake.id, amount: stake.amount })
                }
                accessible
                accessibilityLabel={`Stake ${index + 1}`}
              >
                <Text style={styles.itemText}>Amount: {ethers.utils.formatEther(stake.amount)} S</Text>
                <Text style={styles.itemText}>Lock Period: {stake.lockPeriod} days</Text>
              </TouchableOpacity>
            ))
          ) : (
            <Text style={styles.emptyText} accessibilityLabel="No recent stakes">
              No recent stakes found.
            </Text>
          )}
        </Animated.View>

        <Animated.View
          entering={ZoomIn.delay(450).springify()}
          exiting={ZoomOut}
          layout={Layout.springify()}
          style={styles.card}
        >
          <View style={styles.sectionHeader}>
            <Icon
              name="group"
              size={20}
              color={theme === 'dark' ? '#fff' : '#333'}
              style={styles.sectionIcon}
            />
            <Text
              style={styles.section}
              onPress={() => analytics().logEvent('view_delegated_amounts')}
              accessible
              accessibilityLabel="Delegated Amounts Section"
            >
              Delegated Amounts
            </Text>
          </View>
          {delegatedAmounts.length > 0 ? (
            delegatedAmounts.map((delegation, index) => (
              <TouchableOpacity
                key={index}
                style={styles.item}
                onPress={() =>
                  analytics().logEvent('view_delegation', {
                    validator: delegation.validator,
                    amount: delegation.amount,
                  })
                }
                accessible
                accessibilityLabel={`Delegation ${index + 1}`}
              >
                <Text style={styles.itemText}>Validator: {delegation.validator}</Text>
                <Text style={styles.itemText}>
                  Amount: {ethers.utils.formatEther(delegation.amount)} S
                </Text>
              </TouchableOpacity>
            ))
          ) : (
            <Text style={styles.emptyText} accessibilityLabel="No delegations">
              No delegations found.
            </Text>
          )}
        </Animated.View>

        <Animated.View
          entering={BounceIn.delay(600).springify()}
          exiting={ZoomOut}
          layout={Layout.springify()}
          style={styles.card}
        >
          <View style={styles.sectionHeader}>
            <Icon
              name="gavel"
              size={20}
              color={theme === 'dark' ? '#fff' : '#333'}
              style={styles.sectionIcon}
            />
            <Text
              style={styles.section}
              onPress={() => analytics().logEvent('view_proposals')}
              accessible
              accessibilityLabel="Governance Proposals Section"
            >
              Governance Proposals
            </Text>
          </View>
          {proposals.length > 0 ? (
            proposals.map((proposal, index) => (
              <TouchableOpacity
                key={index}
                style={styles.item}
                onPress={() =>
                  analytics().logEvent('view_proposal', { proposal_id: proposal.proposalId })
                }
                accessible
                accessibilityLabel={`Proposal ${index + 1}`}
              >
                <Text style={styles.itemText}>Proposal ID: {proposal.proposalId}</Text>
                <Text style={styles.itemText}>Description Hash: {proposal.descriptionHash}</Text>
                <Text style={styles.itemText}>
                  Created: {new Date(proposal.timestamp * 1000).toLocaleString()}
                </Text>
              </TouchableOpacity>
            ))
          ) : (
            <Text style={styles.emptyText} accessibilityLabel="No proposals">
              No proposals found.
            </Text>
          )}
        </Animated.View>

        <Animated.View
          entering={ZoomIn.delay(750).springify()}
          exiting={ZoomOut}
          layout={Layout.springify()}
          style={styles.card}
        >
          <View style={styles.sectionHeader}>
            <Icon
              name="update"
              size={20}
              color={theme === 'dark' ? '#fff' : '#333'}
              style={styles.sectionIcon}
            />
            <Text
              style={styles.section}
              onPress={() => analytics().logEvent('view_upgrade_proposals')}
              accessible
              accessibilityLabel="Upgrade Proposals Section"
            >
              Upgrade Proposals
            </Text>
          </View>
          {upgradeProposals.length > 0 ? (
            upgradeProposals.map((upgrade, index) => (
              <TouchableOpacity
                key={index}
                style={styles.item}
                onPress={() =>
                  analytics().logEvent('view_upgrade_proposal', { proposal_id: upgrade.id })
                }
                accessible
                accessibilityLabel={`Upgrade Proposal ${index + 1}`}
              >
                <Text style={styles.itemText}>New Implementation: {upgrade.newImplementation}</Text>
                <Text style={styles.itemText}>
                  Timelock End: {new Date(upgrade.timelockEnd * 1000).toLocaleString()}
                </Text>
                <Text style={styles.itemText}>
                  Status: {upgrade.validated ? 'Validated' : upgrade.cancelled ? 'Cancelled' : 'Pending'}
                </Text>
              </TouchableOpacity>
            ))
          ) : (
            <Text style={styles.emptyText} accessibilityLabel="No upgrade proposals">
              No upgrade proposals found.
            </Text>
          )}
        </Animated.View>
      </ScrollView>
    </LinearGradient>
  );
};

export default () => (
  <ThemeProvider>
    <AnalyticsDashboard />
  </ThemeProvider>
);
