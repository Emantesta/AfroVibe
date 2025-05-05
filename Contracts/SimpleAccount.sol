// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4337.sol";

// Interface for Sonic-compatible multisig (e.g., Gnosis Safe)
interface ISafe {
    function isOwner(address owner) external view returns (bool);
    function execTransaction(address to, uint256 value, bytes calldata data) external returns (bool);
    function isValidSignature(bytes32 dataHash, bytes memory signature) external view returns (bytes4);
}

// Interfaces from Staking.sol
interface IBeetsStaking {
    function stake(address user, uint256 amount) external returns (uint256 stSAmount);
    function unstake(address user, uint256 stSAmount) external returns (uint256 amount);
    function claimRewards(address user) external returns (uint256 rewards);
    function isPaused() external view returns (bool);
}

interface ISonicValidator {
    function delegate(address validator, uint256 amount) external;
    function undelegate(address validator, uint256 amount) external;
    function claimValidatorRewards(address validator) external returns (uint256);
}

interface ISonicGateway {
    function bridgeFromEthereum(address token, uint256 amount, address recipient) external returns (bool);
    function bridgeToEthereum(address token, uint256 amount, address recipient) external returns (bool);
}

contract SimpleAccount is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IAccount {
    // Multisig contract address (e.g., Gnosis Safe)
    address public multisig;

    // Sonic-specific contracts
    address public sonicGateway;
    address public sonicValidator;
    address public beetsStaking;
    address public feeCollector;

    // ERC-4337 EntryPoint
    IEntryPoint public entryPoint;

    // Nonce for ERC-4337 UserOperations
    mapping(uint256 => uint256) public nonces;

    // Trusted paymasters (e.g., AfroVibePaymaster)
    mapping(address => bool) public trustedPaymasters;

    // Maximum batch size for UserOperations
    uint256 public constant MAX_BATCH_SIZE = 10;

    // Events
    event TokenSent(address indexed token, address indexed recipient, uint256 amount);
    event TokenApproved(address indexed token, address indexed spender, uint256 amount);
    event Executed(address indexed target, uint256 value, bytes data);
    event BatchExecuted(uint256 transactionCount);
    event BatchTokenSent(address indexed token, uint256 recipientCount);
    event Upgraded(address indexed newImplementation);
    event Staked(address indexed stakingContract, address indexed token, uint256 amount, uint256 stSAmount);
    event Unstaked(address indexed stakingContract, address indexed token, uint256 amount, uint256 stSAmount);
    event RewardsClaimed(address indexed stakingContract, address indexed token, uint256 rewards);
    event Bridged(address indexed token, uint256 amount, address recipient, bool toEthereum);
    event FeeCollected(address indexed token, uint256 amount);
    event UserOperationExecuted(address indexed sender, uint256 nonce);
    event BatchUserOperationExecuted(address indexed sender, uint256[] nonces);
    event PaymasterAdded(address indexed paymaster);
    event PaymasterRemoved(address indexed paymaster);

    // Constructor disables direct initialization
    constructor() {
        _disableInitializers();
    }

    // Initialize with multisig, Sonic-specific contracts, EntryPoint, and initial paymasters
    function initialize(
        address _multisig,
        address _sonicGateway,
        address _sonicValidator,
        address _beetsStaking,
        address _feeCollector,
        address _entryPoint,
        address[] calldata initialPaymasters
    ) external initializer {
        require(_multisig != address(0), "Invalid multisig");
        require(_sonicGateway != address(0), "Invalid gateway");
        require(_sonicValidator != address(0), "Invalid validator");
        require(_beetsStaking != address(0), "Invalid BEETS staking");
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_entryPoint != address(0), "Invalid entry point");
        multisig = _multisig;
        sonicGateway = _sonicGateway;
        sonicValidator = _sonicValidator;
        beetsStaking = _beetsStaking;
        feeCollector = _feeCollector;
        entryPoint = IEntryPoint(_entryPoint);
        for (uint256 i = 0; i < initialPaymasters.length; i++) {
            require(initialPaymasters[i] != address(0), "Invalid paymaster");
            trustedPaymasters[initialPaymasters[i]] = true;
            emit PaymasterAdded(initialPaymasters[i]);
        }
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    // Modifier to restrict access to multisig owners
    modifier onlyMultisig() {
        require(ISafe(multisig).isOwner(msg.sender), "Not multisig owner");
        _;
    }

    // Modifier to restrict access to EntryPoint
    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "Only EntryPoint");
        _;
    }

    // Add a trusted paymaster (e.g., AfroVibePaymaster)
    function addPaymaster(address paymaster) external onlyMultisig {
        require(paymaster != address(0), "Invalid paymaster");
        require(!trustedPaymasters[paymaster], "Paymaster already trusted");
        trustedPaymasters[paymaster] = true;
        emit PaymasterAdded(paymaster);
    }

    // Remove a trusted paymaster
    function removePaymaster(address paymaster) external onlyMultisig {
        require(trustedPaymasters[paymaster], "Paymaster not trusted");
        trustedPaymasters[paymaster] = false;
        emit PaymasterRemoved(paymaster);
    }

    // ERC-4337: Validate single UserOperation
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override onlyEntryPoint returns (uint256 validationData) {
        require(userOp.sender == address(this), "Invalid sender");
        require(nonces[userOp.nonce] == 0, "Nonce already used");
        nonces[userOp.nonce] = 1;

        // Check paymasterAndData for AfroVibePaymaster
        address paymaster;
        if (userOp.paymasterAndData.length >= 20) {
            paymaster = address(bytes20(userOp.paymasterAndData[:20]));
            require(trustedPaymasters[paymaster], "Untrusted paymaster");
        }

        // Delegate signature validation to multisig (EIP-1271)
        (bool success, bytes memory result) = multisig.staticcall(
            abi.encodeWithSelector(ISafe.isValidSignature.selector, userOpHash, userOp.signature)
        );
        require(success, "Signature validation failed");
        bytes4 sigResult = abi.decode(result, (bytes4));
        bool validSignature = sigResult == bytes4(0x1626ba7e); // EIP-1271 magic value

        // Pay EntryPoint for missing funds if no valid paymaster
        if (missingAccountFunds > 0 && (paymaster == address(0) || !trustedPaymasters[paymaster])) {
            (bool sent, ) = address(entryPoint).call{value: missingAccountFunds}("");
            require(sent, "Failed to pay EntryPoint");
        }

        validationData = validSignature ? 0 : 1;
    }

    // ERC-4337: Validate batch UserOperations
    function validateBatchUserOp(
        UserOperation[] calldata userOps,
        bytes32[] calldata userOpHashes,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256[] memory validationData) {
        require(userOps.length == userOpHashes.length, "Array length mismatch");
        require(userOps.length > 0 && userOps.length <= MAX_BATCH_SIZE, "Invalid batch size");
        validationData = new uint256[](userOps.length);

        bool hasValidPaymaster = false;
        address paymaster;

        for (uint256 i = 0; i < userOps.length; i++) {
            UserOperation calldata userOp = userOps[i];
            require(userOp.sender == address(this), "Invalid sender");
            require(nonces[userOp.nonce] == 0, "Nonce already used");
            nonces[userOp.nonce] = 1;

            // Check paymasterAndData (use first valid paymaster)
            if (!hasValidPaymaster && userOp.paymasterAndData.length >= 20) {
                paymaster = address(bytes20(userOp.paymasterAndData[:20]));
                if (trustedPaymasters[paymaster]) {
                    hasValidPaymaster = true;
                }
            }

            // Delegate signature validation to multisig (EIP-1271)
            (bool success, bytes memory result) = multisig.staticcall(
                abi.encodeWithSelector(ISafe.isValidSignature.selector, userOpHashes[i], userOp.signature)
            );
            require(success, "Signature validation failed");
            bytes4 sigResult = abi.decode(result, (bytes4));
            validationData[i] = sigResult == bytes4(0x1626ba7e) ? 0 : 1;
        }

        // Pay EntryPoint for missing funds if no valid paymaster
        if (missingAccountFunds > 0 && !hasValidPaymaster) {
            (bool sent, ) = address(entryPoint).call{value: missingAccountFunds}("");
            require(sent, "Failed to pay EntryPoint");
        }
    }

    // ERC-4337: Execute single UserOperation
    function executeUserOp(UserOperation calldata userOp) external onlyEntryPoint nonReentrant {
        require(userOp.sender == address(this), "Invalid sender");
        require(nonces[userOp.nonce] == 1, "Invalid nonce");

        // Decode and execute callData
        (address target, uint256 value, bytes memory data) = abi.decode(userOp.callData, (address, uint256, bytes));
        require(target != address(0), "Invalid target");
        require(target != address(this), "Cannot call self");

        bool success = ISafe(multisig).execTransaction(target, value, data);
        require(success, "UserOp execution failed");

        emit UserOperationExecuted(userOp.sender, userOp.nonce);
    }

    // ERC-4337: Execute batch UserOperations
    function executeBatchUserOp(UserOperation[] calldata userOps) external onlyEntryPoint nonReentrant {
        require(userOps.length > 0 && userOps.length <= MAX_BATCH_SIZE, "Invalid batch size");
        uint256[] memory executedNonces = new uint256[](userOps.length);
        uint256 nonceCount = 0;

        for (uint256 i = 0; i < userOps.length; i++) {
            UserOperation calldata userOp = userOps[i];
            require(userOp.sender == address(this), "Invalid sender");
            require(nonces[userOp.nonce] == 1, "Invalid nonce");

            // Decode and execute callData
            (address target, uint256 value, bytes memory data) = abi.decode(userOp.callData, (address, uint256, bytes));
            require(target != address(0), "Invalid target");
            require(target != address(this), "Cannot call self");

            bool success = ISafe(multisig).execTransaction(target, value, data);
            require(success, "Batch UserOp execution failed");

            executedNonces[nonceCount] = userOp.nonce;
            nonceCount++;
        }

        emit BatchUserOperationExecuted(address(this), executedNonces);
    }

    // Execute a single transaction (via multisig)
    function execute(address target, uint256 value, bytes calldata data) external onlyMultisig nonReentrant {
        require(target != address(0), "Invalid target");
        require(target != address(this), "Cannot call self");
        bool success = ISafe(multisig).execTransaction(target, value, data);
        require(success, "Execution failed");
        emit Executed(target, value, data);
    }

    // Execute batch transactions
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyMultisig nonReentrant {
        require(targets.length == values.length && values.length == datas.length, "Array length mismatch");
        require(targets.length > 0, "Empty batch");
        for (uint256 i = 0; i < targets.length; i++) {
            require(targets[i] != address(0), "Invalid target");
            require(targets[i] != address(this), "Cannot call self");
            bool success = ISafe(multisig).execTransaction(targets[i], values[i], datas[i]);
            require(success, "Batch execution failed");
            emit Executed(targets[i], values[i], datas[i]);
        }
        emit BatchExecuted(targets.length);
    }

    // Send a specific token (e.g., S, USDC, BEETS)
    function sendToken(address token, address recipient, uint256 amount) external onlyMultisig nonReentrant {
        require(token != address(0), "Invalid token");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");
        bool success = IERC20(token).transfer(recipient, amount);
        require(success, "Token transfer failed");
        emit TokenSent(token, recipient, amount);
    }

    // Send a specific token to multiple recipients
    function sendTokenBatch(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyMultisig nonReentrant {
        require(token != address(0), "Invalid token");
        require(recipients.length == amounts.length, "Array length mismatch");
        require(recipients.length > 0, "Empty batch");
        uint256 totalAmount;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(amounts[i] > 0, "Invalid amount");
            totalAmount += amounts[i];
        }
        require(IERC20(token).balanceOf(address(this)) >= totalAmount, "Insufficient token balance");
        for (uint256 i = 0; i < recipients.length; i++) {
            bool success = IERC20(token).transfer(recipients[i], amounts[i]);
            require(success, "Token transfer failed");
            emit TokenSent(token, recipients[i], amounts[i]);
        }
        emit BatchTokenSent(token, recipients.length);
    }

    // Approve a spender for a specific token
    function approveToken(address token, address spender, uint256 amount) external onlyMultisig nonReentrant {
        require(token != address(0), "Invalid token");
        require(spender != address(0), "Invalid spender");
        bool success = IERC20(token).approve(spender, amount);
        require(success, "Token approval failed");
        emit TokenApproved(token, spender, amount);
    }

    // Get balance of a specific token
    function getTokenBalance(address token) external view returns (uint256) {
        require(token != address(0), "Invalid token");
        return IERC20(token).balanceOf(address(this));
    }

    // Stake S tokens in Sonic staking contract
    function stakeS(address sToken, uint256 amount, uint256 lockPeriod) external onlyMultisig nonReentrant {
        require(sToken != address(0), "Invalid S token");
        require(amount > 0, "Invalid amount");
        require(sonicValidator != address(0), "Validator not set");
        require(!IBeetsStaking(beetsStaking).isPaused(), "BeetsStaking paused");
        require(lockPeriod >= 1 && lockPeriod <= 365, "Invalid lock period");
        require(IERC20(sToken).balanceOf(address(this)) >= amount, "Insufficient S balance");

        bool success = IERC20(sToken).approve(beetsStaking, amount);
        require(success, "S approval failed");

        uint256 stSAmount;
        try IBeetsStaking(beetsStaking).stake(address(this), amount) returns (uint256 _stSAmount) {
            stSAmount = _stSAmount;
            require(stSAmount > 0, "Zero stSAmount");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Beets staking failed: ", reason)));
        }

        emit Staked(beetsStaking, sToken, amount, stSAmount);
    }

    // Unstake S tokens from Sonic staking contract
    function unstakeS(address sToken, uint256 stSAmount) external onlyMultisig nonReentrant {
        require(sToken != address(0), "Invalid S token");
        require(stSAmount > 0, "Invalid amount");
        require(sonicValidator != address(0), "Validator not set");
        require(!IBeetsStaking(beetsStaking).isPaused(), "BeetsStaking paused");

        uint256 amount;
        try IBeetsStaking(beetsStaking).unstake(address(this), stSAmount) returns (uint256 _amount) {
            amount = _amount;
            require(amount > 0, "Zero amount returned");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Beets unstaking failed: ", reason)));
        }

        emit Unstaked(beetsStaking, sToken, amount, stSAmount);
    }

    // Claim S token staking rewards
    function claimSRewards() external onlyMultisig nonReentrant {
        require(sonicValidator != address(0), "Validator not set");
        require(!IBeetsStaking(beetsStaking).isPaused(), "BeetsStaking paused");

        uint256 rewards;
        try IBeetsStaking(beetsStaking).claimRewards(address(this)) returns (uint256 _rewards) {
            rewards = _rewards;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Beets reward claim failed: ", reason)));
        }

        emit RewardsClaimed(beetsStaking, address(0), rewards);
    }

    // Delegate S tokens to a validator
    function delegateS(address sToken, address validator, uint256 amount) external onlyMultisig nonReentrant {
        require(sToken != address(0), "Invalid S token");
        require(validator != address(0), "Invalid validator");
        require(amount > 0, "Invalid amount");
        require(sonicValidator != address(0), "Validator not set");
        require(IERC20(sToken).balanceOf(address(this)) >= amount, "Insufficient S balance");

        bool success = IERC20(sToken).approve(sonicValidator, amount);
        require(success, "S approval failed");

        try ISonicValidator(sonicValidator).delegate(validator, amount) {
            emit Staked(sonicValidator, sToken, amount, 0);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Validator delegation failed: ", reason)));
        }
    }

    // Undelegate S tokens from a validator
    function undelegateS(address sToken, address validator, uint256 amount) external onlyMultisig nonReentrant {
        require(sToken != address(0), "Invalid S token");
        require(validator != address(0), "Invalid validator");
        require(amount > 0, "Invalid amount");
        require(sonicValidator != address(0), "Validator not set");

        try ISonicValidator(sonicValidator).undelegate(validator, amount) {
            emit Unstaked(sonicValidator, sToken, amount, 0);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Validator undelegation failed: ", reason)));
        }
    }

    // Claim validator rewards
    function claimValidatorRewards(address validator) external onlyMultisig nonReentrant {
        require(validator != address(0), "Invalid validator");
        require(sonicValidator != address(0), "Validator not set");

        uint256 rewards;
        try ISonicValidator(sonicValidator).claimValidatorRewards(validator) returns (uint256 _rewards) {
            rewards = _rewards;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Validator reward claim failed: ", reason)));
        }

        emit RewardsClaimed(sonicValidator, address(0), rewards);
    }

    // Stake BEETS tokens
    function stakeBeets(address beetsToken, uint256 amount) external onlyMultisig nonReentrant {
        require(beetsToken != address(0), "Invalid BEETS token");
        require(amount > 0, "Invalid amount");
        require(beetsStaking != address(0), "Beets staking not set");
        require(!IBeetsStaking(beetsStaking).isPaused(), "BeetsStaking paused");
        require(IERC20(beetsToken).balanceOf(address(this)) >= amount, "Insufficient BEETS balance");

        bool success = IERC20(beetsToken).approve(beetsStaking, amount);
        require(success, "BEETS approval failed");

        uint256 stSAmount;
        try IBeetsStaking(beetsStaking).stake(address(this), amount) returns (uint256 _stSAmount) {
            stSAmount = _stSAmount;
            require(stSAmount > 0, "Zero stSAmount");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Beets staking failed: ", reason)));
        }

        emit Staked(beetsStaking, beetsToken, amount, stSAmount);
    }

    // Unstake BEETS tokens
    function unstakeBeets(address beetsToken, uint256 stSAmount) external onlyMultisig nonReentrant {
        require(beetsToken != address(0), "Invalid BEETS token");
        require(stSAmount > 0, "Invalid amount");
        require(beetsStaking != address(0), "Beets staking not set");
        require(!IBeetsStaking(beetsStaking).isPaused(), "BeetsStaking paused");

        uint256 amount;
        try IBeetsStaking(beetsStaking).unstake(address(this), stSAmount) returns (uint256 _amount) {
            amount = _amount;
            require(amount > 0, "Zero amount returned");
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Beets unstaking failed: ", reason)));
        }

        emit Unstaked(beetsStaking, beetsToken, amount, stSAmount);
    }

    // Claim BEETS staking rewards
    function claimBeetsRewards() external onlyMultisig nonReentrant {
        require(beetsStaking != address(0), "Beets staking not set");
        require(!IBeetsStaking(beetsStaking).isPaused(), "BeetsStaking paused");

        uint256 rewards;
        try IBeetsStaking(beetsStaking).claimRewards(address(this)) returns (uint256 _rewards) {
            rewards = _rewards;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Beets reward claim failed: ", reason)));
        }

        emit RewardsClaimed(beetsStaking, address(0), rewards);
    }

    // Bridge tokens via Sonic Gateway
    function bridgeTokens(address token, uint256 amount, address recipient, bool toEthereum) external onlyMultisig nonReentrant {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        require(recipient != address(0), "Invalid recipient");
        require(sonicGateway != address(0), "Gateway not set");

        bool success = IERC20(token).approve(sonicGateway, amount);
        require(success, "Token approval failed");

        bool bridgeSuccess;
        if (toEthereum) {
            try ISonicGateway(sonicGateway).bridgeToEthereum(token, amount, recipient) returns (bool _success) {
                bridgeSuccess = _success;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Bridge to Ethereum failed: ", reason)));
            }
        } else {
            try ISonicGateway(sonicGateway).bridgeFromEthereum(token, amount, recipient) returns (bool _success) {
                bridgeSuccess = _success;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Bridge from Ethereum failed: ", reason)));
            }
        }
        require(bridgeSuccess, "Bridge failed");

        emit Bridged(token, amount, recipient, toEthereum);
    }

    // Collect fees for Sonic Fee Monetization
    function collectFee(address token, uint256 amount) external onlyMultisig nonReentrant {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        require(feeCollector != address(0), "Fee collector not set");
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");
        bool success = IERC20(token).transfer(feeCollector, amount);
        require(success, "Fee transfer failed");
        emit FeeCollected(token, amount);
    }

    // Authorize upgrade with multisig check
    function _authorizeUpgrade(address newImplementation) internal override onlyMultisig {
        require(newImplementation != address(0), "Invalid implementation");
        emit Upgraded(newImplementation);
    }

    // Allow receiving S tokens or ETH for gas
    receive() external payable {}
}
