// frontend/src/components/Paymaster.js
import React, { useState, useEffect } from "react";
import { ethers } from "ethers";
import PaymasterFunder from "../utils/PaymasterFunder"; // Adjust path

const Paymaster = () => {
  const [funder, setFunder] = useState(null);
  const [userAddress, setUserAddress] = useState(null);
  const [isFunder, setIsFunder] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);
  const [isPauser, setIsPauser] = useState(false);
  const [minFundingAmount, setMinFundingAmount] = useState("0");
  const [maxFundingAmount, setMaxFundingAmount] = useState("0");
  const [paymasterBalance, setPaymasterBalance] = useState("0");
  const [isPaused, setIsPaused] = useState(false);
  const [fundingAmount, setFundingAmount] = useState("");
  const [newFunderAddress, setNewFunderAddress] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    const init = async () => {
      try {
        if (!window.ethereum) {
          throw new Error("MetaMask is not installed");
        }

        // Connect to MetaMask
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        await provider.send("eth_requestAccounts", []);
        const signer = provider.getSigner();
        const address = await signer.getAddress();
        setUserAddress(address);

        // Ensure correct network (replace YOUR_SONIC_CHAIN_ID)
        const network = await provider.getNetwork();
        const YOUR_SONIC_CHAIN_ID = 1234; // Replace with Sonic chain ID
        if (network.chainId !== YOUR_SONIC_CHAIN_ID) {
          await window.ethereum.request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: ethers.utils.hexValue(YOUR_SONIC_CHAIN_ID) }],
          });
        }

        // Initialize PaymasterFunder
        const contractAddress = process.env.REACT_APP_PAYMASTER_FUNDER_ADDRESS;
        if (!contractAddress) {
          throw new Error("PAYMASTER_FUNDER_ADDRESS not set");
        }
        const funderInstance = new PaymasterFunder(contractAddress, signer);
        setFunder(funderInstance);

        // Check roles
        setIsFunder(await funderInstance.isFunder(address));
        setIsAdmin(await funderInstance.isAdmin(address));
        setIsPauser(await funderInstance.isPauser(address));

        // Query contract state
        setMinFundingAmount(ethers.utils.formatEther(await funderInstance.getMinFundingAmount()));
        setMaxFundingAmount(ethers.utils.formatEther(await funderInstance.getMaxFundingAmount()));
        setPaymasterBalance(ethers.utils.formatEther(await funderInstance.getPaymasterBalance()));
        setIsPaused(await funderInstance.isPaused());

        // Listen for Funded events
        funderInstance.onFunded((paymaster, funder, amount) => {
          console.log(`Funded: ${funder} sent ${ethers.utils.formatEther(amount)} to ${paymaster}`);
          funderInstance.getPaymasterBalance().then((balance) => {
            setPaymasterBalance(ethers.utils.formatEther(balance));
          });
        });

        // Handle account/network changes
        window.ethereum.on("accountsChanged", () => window.location.reload());
        window.ethereum.on("chainChanged", () => window.location.reload());
      } catch (err) {
        setError(err.message);
      }
    };
    init();
  }, []);

  const handleApprove = async () => {
    if (!funder || !isFunder || !fundingAmount) return;
    setIsLoading(true);
    setError(null);
    try {
      const amount = ethers.utils.parseEther(fundingAmount);
      const receipt = await funder.approveSonicSToken(funder.getContract().address, amount);
      console.log("Approval successful:", receipt);
    } catch (error) {
      setError(error.message || "Approval failed");
    } finally {
      setIsLoading(false);
    }
  };

  const handleFund = async () => {
    if (!funder || !isFunder || !fundingAmount || isPaused) return;
    setIsLoading(true);
    setError(null);
    try {
      const amount = ethers.utils.parseEther(fundingAmount);
      const receipt = await funder.fund(amount);
      console.log("Funding successful:", receipt);
      setFundingAmount("");
    } catch (error) {
      setError(error.message || "Funding failed");
    } finally {
      setIsLoading(false);
    }
  };

  const handleGrantFunderRole = async () => {
    if (!funder || !isAdmin || !ethers.utils.isAddress(newFunderAddress)) return;
    setIsLoading(true);
    setError(null);
    try {
      const receipt = await funder.grantFunderRole(newFunderAddress);
      console.log("Funder role granted:", receipt);
      setNewFunderAddress("");
    } catch (error) {
      setError(error.message || "Failed to grant funder role");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div>
      <h1>Paymaster Funder</h1>
      {error && <p style={{ color: "red" }}>{error}</p>}
      <p>Connected Address: {userAddress || "Not connected"}</p>
      <p>Paymaster Balance: {paymasterBalance} Sonic S</p>
      <p>Min Funding Amount: {minFundingAmount} Sonic S</p>
      <p>Max Funding Amount: {maxFundingAmount} Sonic S</p>
      <p>Contract Status: {isPaused ? "Paused" : "Active"}</p>
      {isAdmin && <p style={{ color: "green" }}>You are an admin</p>}
      {isFunder && <p style={{ color: "green" }}>You are a funder</p>}
      {isPauser && <p style={{ color: "green" }}>You are a pauser</p>}

      {isFunder && !isPaused ? (
        <div>
          <input
            type="number"
            value={fundingAmount}
            onChange={(e) => setFundingAmount(e.target.value)}
            placeholder={`Amount (${minFundingAmount} - ${maxFundingAmount} Sonic S)`}
            disabled={isLoading}
          />
          <button onClick={handleApprove} disabled={isLoading || !fundingAmount}>
            {isLoading ? "Approving..." : "Approve Sonic S"}
          </button>
          <button onClick={handleFund} disabled={isLoading || !fundingAmount}>
            {isLoading ? "Funding..." : "Fund Paymaster"}
          </button>
        </div>
      ) : (
        <p style={{ color: "orange" }}>
          {isPaused ? "Contract is paused" : "Only funders can fund the paymaster"}
        </p>
      )}

      {isAdmin && (
        <div>
          <h2>Admin Controls</h2>
          <input
            value={newFunderAddress}
            onChange={(e) => setNewFunderAddress(e.target.value)}
            placeholder="New Funder Address"
            disabled={isLoading}
          />
          <button onClick={handleGrantFunderRole} disabled={isLoading || !newFunderAddress}>
            {isLoading ? "Granting..." : "Grant Funder Role"}
          </button>
        </div>
      )}

      {!isFunder && !isAdmin && (
        <p>Contact the admin to become a funder or use the paymaster for gasless transactions.</p>
      )}
    </div>
  );
};

export default Paymaster;
