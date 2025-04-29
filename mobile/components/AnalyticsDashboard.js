// Analytics for subscriptions, commerce, music; Displays Beets APR, AfroVibe APY; Enhanced for reward visualization.

import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { ethers } from 'ethers';
import { request, gql } from 'graphql-request';
import StakingABI from '../abis/Staking.json';

const AnalyticsDashboard = () => {
  const [account, setAccount] = useState('');
  const [sonicPoints, setSonicPoints] = useState('0');
  const [totalStaked, setTotalStaked] = useState('0');
  const [delegatedAmounts, setDelegatedAmounts] = useState([]);
  const [recentStakes, setRecentStakes] = useState([]);

  useEffect(() => {
    const init = async () => {
      try {
        // Initialize contract
        const provider = new ethers.providers.JsonRpcProvider(process.env.SONIC_RPC_URL);
        const signer = provider.getSigner();
        const contract = new ethers.Contract(process.env.STAKING_CONTRACT_ADDRESS, StakingABI.abi, signer);
        const accounts = await signer.getAddress();
        setAccount(accounts);

        // Fetch on-chain data
        const points = await contract.sonicPoints(accounts);
        const stakeCount = await contract.stakeCount(accounts);
        let total = ethers.BigNumber.from(0);
        for (let i = 0; i < stakeCount; i++) {
          const stake = await contract.stakes(accounts, i);
          total = total.add(stake.amount);
        }
        setSonicPoints(ethers.utils.formatEther(points));
        setTotalStaked(ethers.utils.formatEther(total));

        // Fetch subgraph data
        const query = gql`
          {
            stakes(where: { user: "${accounts.toLowerCase()}" }, first: 5) {
              id
              user
              amount
              lockPeriod
            }
            delegateds(where: { user: "${accounts.toLowerCase()}" }) {
              user
              validator
              amount
            }
          }
        `;
        const response = await request(process.env.SUBGRAPH_URL, query);
        setRecentStakes(response.stakes);
        setDelegatedAmounts(response.delegateds);
      } catch (error) {
        console.error('Error fetching data:', error);
      }
    };
    init();
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.header}>Analytics Dashboard</Text>
      <Text>Account: {account}</Text>
      <Text>Sonic Points: {sonicPoints}</Text>
      <Text>Total Staked: {totalStaked} S</Text>

      <Text style={styles.section}>Recent Stakes</Text>
      {recentStakes.map((stake, index) => (
        <View key={index} style={styles.item}>
          <Text>Amount: {ethers.utils.formatEther(stake.amount)} S</Text>
          <Text>Lock Period: {stake.lockPeriod} days</Text>
        </View>
      ))}

      <Text style={styles.section}>Delegated Amounts</Text>
      {delegatedAmounts.map((delegation, index) => (
        <View key={index} style={styles.item}>
          <Text>Validator: {delegation.validator}</Text>
          <Text>Amount: {ethers.utils.formatEther(delegation.amount)} S</Text>
        </View>
      ))}
    </View>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, padding: 20 },
  header: { fontSize: 24, fontWeight: 'bold', marginBottom: 20 },
  section: { fontSize: 18, fontWeight: 'bold', marginTop: 20, marginBottom: 10 },
  item: { padding: 10, borderBottomWidth: 1, borderBottomColor: '#ccc' },
});

export default AnalyticsDashboard;


