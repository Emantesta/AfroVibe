// Gas sponsorship for USDC transactions
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC4337.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

// Interface for Chainlink Keeper
interface IKeeperCompatible {
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData);
    function performUpkeep(bytes calldata performData) external;
}

// Interface for PaymasterFunder
interface IPaymasterFunder {
    function fund(uint256 amount) external;
}

contract AfroVibePaymaster is
    IPaymaster,
    ReentrancyGuard,
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    IKeeperCompatible
{
    // Roles for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IEntryPoint public immutable entryPoint;
    address public immutable simpleAccountFactory;
    address public immutable timelock; // Timelock for governance
    address public immutable funder; // PaymasterFunder for deposit automation
    bytes32 public immutable simpleAccountCodeHash;
    uint256 public maxGasCost;
    uint256 public minDepositThreshold;
    uint256 public totalGasSponsored;
    bool public paused;
    uint256 public lastUpkeepTimestamp;
    uint256 public constant TIMELOCK_DELAY = 2 days;
    uint256 public constant MIN_UPKEEP_INTERVAL = 1 hours;
    uint256 public constant MAX_PARTIAL_SPONSORSHIP = 50; // Max 50% user-paid gas

    // Whitelists
    mapping(address => bool) public validTargets;
    mapping(bytes32 => bool) public validActionTypes;
    mapping(address => bool) public authorizedFunders;

    // Pending updates for timelock
    struct PendingUpdate {
        address target;
        bytes32 actionType;
        bool isAdd;
        uint256 timestamp;
    }
    mapping(bytes32 => PendingUpdate) public pendingUpdates;

    // Valid function selectors (e.g., for POST, LIKE, TIP)
    mapping(bytes4 => bool) public validSelectors;

    // Events
    event GasSponsored(
        address indexed user,
        uint256 indexed nonce,
        uint256 gasUsed,
        address indexed target,
        bytes32 actionType
    );
    event DepositFunded(address indexed funder, uint256 amount);
    event LowDeposit(uint256 balance, uint256 threshold);
    event ValidationFailed(string reason, address sender, bytes32 actionType, address target);
    event TargetUpdateProposed(bytes32 indexed updateId, address target, bool isAdd, uint256 timestamp);
    event ActionTypeUpdateProposed(bytes32 indexed updateId, bytes32 actionType, bool isAdd, uint256 timestamp);
    event TargetUpdated(address indexed target, bool isAdd);
    event ActionTypeUpdated(bytes32 indexed actionType, bool isAdd);
    event SelectorUpdated(bytes4 indexed selector, bool isAdd);
    event MaxGasCostUpdated(uint256 oldMaxGasCost, uint256 newMaxGasCost);
    event MinDepositThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event AuthorizedFunderAdded(address indexed funder);
    event AuthorizedFunderRemoved(address indexed funder);
    event Paused(address indexed admin);
    event Unpaused(address indexed admin);
    event EmergencyWithdraw(address indexed recipient, uint256 amount);

    // Interface for SimpleAccountFactory
    interface ISimpleAccountFactory {
        function getAddress(address owner, uint256 salt) external view returns (address);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _entryPoint,
        address _simpleAccountFactory,
        address _timelock,
        bytes32 _simpleAccountCodeHash,
        address _funder
    ) {
        require(_entryPoint != address(0), "Invalid EntryPoint");
        require(_simpleAccountFactory != address(0), "Invalid factory");
        require(_timelock != address(0), "Invalid timelock");
        require(_funder != address(0), "Invalid funder");
        require(_simpleAccountCodeHash != bytes32(0), "Invalid code hash");
        entryPoint = IEntryPoint(_entryPoint);
        simpleAccountFactory = _simpleAccountFactory;
        timelock = _timelock;
        funder = _funder;
        simpleAccountCodeHash = _simpleAccountCodeHash;
        _disableInitializers();
    }

    function initialize(
        address[] memory _validTargets,
        uint256 _maxGasCost,
        uint256 _minDepositThreshold,
        bytes32[] memory _validActionTypes,
        bytes4[] memory _validSelectors,
        address[] memory _authorizedFunders,
        address _defaultAdmin
    ) public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(_maxGasCost > 0, "Invalid max gas cost");
        require(_minDepositThreshold > 0, "Invalid min deposit threshold");
        require(_defaultAdmin != address(0), "Invalid admin");

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(ADMIN_ROLE, _defaultAdmin);
        _grantRole(UPDATER_ROLE, timelock);
        _grantRole(PAUSER_ROLE, _defaultAdmin);

        maxGasCost = _maxGasCost;
        minDepositThreshold = _minDepositThreshold;

        // Initialize valid targets
        for (uint256 i = 0; i < _validTargets.length; ) {
            require(_validTargets[i] != address(0), "Invalid target");
            validTargets[_validTargets[i]] = true;
            emit TargetUpdated(_validTargets[i], true);
            unchecked { i++; }
        }

        // Initialize valid action types
        for (uint256 i = 0; i < _validActionTypes.length; ) {
            require(_validActionTypes[i] != bytes32(0), "Invalid action type");
            validActionTypes[_validActionTypes[i]] = true;
            emit ActionTypeUpdated(_validActionTypes[i], true);
            unchecked { i++; }
        }

        // Initialize valid selectors
        for (uint256 i = 0; i < _validSelectors.length; ) {
            require(_validSelectors[i] != bytes4(0), "Invalid selector");
            validSelectors[_validSelectors[i]] = true;
            emit SelectorUpdated(_validSelectors[i], true);
            unchecked { i++; }
        }

        // Initialize authorized funders
        authorizedFunders[funder] = true;
        emit AuthorizedFunderAdded(funder);
        for (uint256 i = 0; i < _authorizedFunders.length; ) {
            require(_authorizedFunders[i] != address(0), "Invalid funder");
            authorizedFunders[_authorizedFunders[i]] = true;
            emit AuthorizedFunderAdded(_authorizedFunders[i]);
            unchecked { i++; }
        }
    }

    // UUPS: Restrict upgrades to ADMIN_ROLE
    function _authorizeUpgrade(address) internal override onlyRole(ADMIN_ROLE) {}

    // Modifier to restrict when not paused
    modifier whenNotPaused() {
        require(!paused, "Paymaster paused");
        _;
    }

    // Deposit ETH to EntryPoint
    function deposit() external payable {
        require(authorizedFunders[msg.sender], "Unauthorized funder");
        require(msg.value > 0, "Invalid deposit amount");
        entryPoint.depositTo{value: msg.value}(address(this));
        emit DepositFunded(msg.sender, msg.value);
    }

    // Emergency withdraw to recover funds
    function emergencyWithdraw(address payable to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Withdraw failed");
        emit EmergencyWithdraw(to, amount);
    }

    // Propose adding/removing a valid target
    function proposeTargetUpdate(address target, bool isAdd) external onlyRole(ADMIN_ROLE) {
        require(target != address(0), "Invalid target");
        bytes32 updateId = keccak256(abi.encode(target, isAdd, block.timestamp));
        pendingUpdates[updateId] = PendingUpdate({
            target: target,
            actionType: bytes32(0),
            isAdd: isAdd,
            timestamp: block.timestamp
        });
        emit TargetUpdateProposed(updateId, target, isAdd, block.timestamp);

        // Schedule via Timelock
        (bool success, ) = timelock.call(
            abi.encodeCall(
                ITimelockController.schedule,
                (address(this), 0, abi.encodeCall(this.executeTargetUpdate, (updateId, target, isAdd)), bytes32(0), updateId, TIMELOCK_DELAY)
            )
        );
        require(success, "Timelock scheduling failed");
    }

    // Execute target update
    function executeTargetUpdate(bytes32 updateId, address target, bool isAdd) external {
        require(msg.sender == timelock, "Only timelock");
        PendingUpdate memory update = pendingUpdates[updateId];
        require(update.target == target && update.isAdd == isAdd, "Invalid update");
        require(block.timestamp >= update.timestamp + TIMELOCK_DELAY, "Timelock not elapsed");

        validTargets[target] = isAdd;
        emit TargetUpdated(target, isAdd);
        delete pendingUpdates[updateId];
    }

    // Propose adding/removing a valid action type
    function proposeActionTypeUpdate(bytes32 actionType, bool isAdd) external onlyRole(ADMIN_ROLE) {
        require(actionType != bytes32(0), "Invalid action type");
        bytes32 updateId = keccak256(abi.encode(actionType, isAdd, block.timestamp));
        pendingUpdates[updateId] = PendingUpdate({
            target: address(0),
            actionType: actionType,
            isAdd: isAdd,
            timestamp: block.timestamp
        });
        emit ActionTypeUpdateProposed(updateId, actionType, isAdd, block.timestamp);

        // Schedule via Timelock
        (bool success, ) = timelock.call(
            abi.encodeCall(
                ITimelockController.schedule,
                (address(this), 0, abi.encodeCall(this.executeActionTypeUpdate, (updateId, actionType, isAdd)), bytes32(0), updateId, TIMELOCK_DELAY)
            )
        );
        require(success, "Timelock scheduling failed");
    }

    // Execute action type update
    function executeActionTypeUpdate(bytes32 updateId, bytes32 actionType, bool isAdd) external {
        require(msg.sender == timelock, "Only timelock");
        PendingUpdate memory update = pendingUpdates[updateId];
        require(update.actionType == actionType && update.isAdd == isAdd, "Invalid update");
        require(block.timestamp >= update.timestamp + TIMELOCK_DELAY, "Timelock not elapsed");

        validActionTypes[actionType] = isAdd;
        emit ActionTypeUpdated(actionType, isAdd);
        delete pendingUpdates[updateId];
    }

    // Propose adding/removing a valid selector
    function proposeSelectorUpdate(bytes4 selector, bool isAdd) external onlyRole(ADMIN_ROLE) {
        require(selector != bytes4(0), "Invalid selector");
        bytes32 updateId = keccak256(abi.encode(selector, isAdd, block.timestamp));
        pendingUpdates[updateId] = PendingUpdate({
            target: address(0),
            actionType: selector,
            isAdd: isAdd,
            timestamp: block.timestamp
        });
        emit SelectorUpdated(selector, isAdd);

        // Schedule via Timelock
        (bool success, ) = timelock.call(
            abi.encodeCall(
                ITimelockController.schedule,
                (address(this), 0, abi.encodeCall(this.executeSelectorUpdate, (updateId, selector, isAdd)), bytes32(0), updateId, TIMELOCK_DELAY)
            )
        );
        require(success, "Timelock scheduling failed");
    }

    // Execute selector update
    function executeSelectorUpdate(bytes32 updateId, bytes4 selector, bool isAdd) external {
        require(msg.sender == timelock, "Only timelock");
        PendingUpdate memory update = pendingUpdates[updateId];
        require(update.actionType == bytes32(selector) && update.isAdd == isAdd, "Invalid update");
        require(block.timestamp >= update.timestamp + TIMELOCK_DELAY, "Timelock not elapsed");

        validSelectors[selector] = isAdd;
        emit SelectorUpdated(selector, violin isAdd);
        delete pendingUpdates[updateId];
    }

    // Update authorized funder
    function updateAuthorizedFunder(address funderAddress, bool isAdd) external onlyRole(ADMIN_ROLE) {
        require(funderAddress != address(0), "Invalid funder");
        authorizedFunders[funderAddress] = isAdd;
        if (isAdd) {
            emit AuthorizedFunderAdded(funderAddress);
        } else {
            emit AuthorizedFunderRemoved(funderAddress);
        }
    }

    // Update max gas cost
    function updateMaxGasCost(uint256 newMaxGasCost) external onlyRole(ADMIN_ROLE) {
        require(newMaxGasCost > 0, "Invalid max gas cost");
        emit MaxGasCostUpdated(maxGasCost, newMaxGasCost);
        maxGasCost = newMaxGasCost;
    }

    // Update min deposit threshold
    function updateMinDepositThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        require(newThreshold > 0, "Invalid threshold");
        emit MinDepositThresholdUpdated(minDepositThreshold, newThreshold);
        minDepositThreshold = newThreshold;
    }

    // Propose pause
    function proposePause() external onlyRole(PAUSER_ROLE) {
        (bool success, ) = timelock.call(
            abi.encodeCall(
                ITimelockController.schedule,
                (address(this), 0, abi.encodeCall(this.pause, ()), bytes32(0), keccak256(abi.encode("pause", block.timestamp)), TIMELOCK_DELAY)
            )
        );
        require(success, "Timelock scheduling failed");
    }

    // Unpause
    function unpause() external onlyRole(PAUSER_ROLE) {
        require(paused, "Not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    // Execute pause
    function pause() external {
        require(msg.sender == timelock, "Only timelock");
        require(!paused, "Already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    // Chainlink Keeper: Check deposit
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 balance = entryPoint.balanceOf(address(this));
        upkeepNeeded = balance < minDepositThreshold && block.timestamp >= lastUpkeepTimestamp + MIN_UPKEEP_INTERVAL;
        performData = abi.encode(balance);
        return (upkeepNeeded, performData);
    }

    // Chainlink Keeper: Replenish deposit
    function performUpkeep(bytes calldata performData) external override {
        require(block.timestamp >= lastUpkeepTimestamp + MIN_UPKEEP_INTERVAL, "Upkeep too frequent");
        uint256 balance = abi.decode(performData, (uint256));
        require(balance < minDepositThreshold, "Deposit sufficient");
        uint256 amount = minDepositThreshold - balance;
        IPaymasterFunder(funder).fund(amount);
        lastUpkeepTimestamp = block.timestamp;
        emit DepositFunded(funder, amount);
    }

    // Validate UserOperation
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 maxCost
    ) external override whenNotPaused returns (bytes memory context, uint256 validationData) {
        require(msg.sender == address(entryPoint), "Only EntryPoint");

        // Verify paymaster
        if (userOp.paymasterAndData.length < 20 || address(bytes20(userOp.paymasterAndData[:20])) != address(this)) {
            emit ValidationFailed("Wrong paymaster", userOp.sender, bytes32(0), address(0));
            return (bytes(0), 1);
        }

        // Verify sender
        if (!isValidAccount(userOp.sender)) {
            emit ValidationFailed("Invalid account", userOp.sender, bytes32(0), address(0));
            return (bytes(0), 1);
        }

        // Validate target
        address target;
        if (userOp.callData.length >= 24) {
            target = address(bytes20(userOp.callData[4:24]));
            if (!validTargets[target]) {
                emit ValidationFailed("Invalid target", userOp.sender, bytes32(0), target);
                return (bytes(0), 1);
            }
        } else {
            emit ValidationFailed("Invalid call data", userOp.sender, bytes32(0), address(0));
            return (bytes(0), 1);
        }

        // Validate action type
        bytes32 actionType;
        if (userOp.paymasterAndData.length < 52) {
            emit ValidationFailed("Missing action type", userOp.sender, bytes32(0), target);
            return (bytes(0), 1);
        }
        actionType = bytes32(userOp.paymasterAndData[20:52]);
        if (!validActionTypes[actionType]) {
            emit ValidationFailed("Invalid action type", userOp.sender, actionType, target);
            return (bytes(0), 1);
        }

        // Validate function selector
        if (userOp.callData.length >= 4) {
            bytes4 selector = bytes4(userOp.callData[:4]);
            if (!validSelectors[selector]) {
                emit ValidationFailed("Invalid selector", userOp.sender, actionType, target);
                return (bytes(0), 1);
            }
        } else {
            emit ValidationFailed("Missing selector", userOp.sender, actionType, target);
            return (bytes(0), 1);
        }

        // Gas cost calculation
        uint256 sponsorCost = maxCost;
        if (maxCost > maxGasCost) {
            sponsorCost = maxGasCost;
            uint256 userCost = maxCost - sponsorCost;
            require(
                userCost <= (maxCost * MAX_PARTIAL_SPONSORSHIP) / 100,
                "User cost exceeds partial sponsorship limit"
            );
            require(
                userOp.preVerificationGas + userOp.verificationGas + userOp.callGas >= userCost,
                "Insufficient user gas"
            );
        }

        // Check deposit
        uint256 deposit = entryPoint.balanceOf(address(this));
        if (deposit < Math.max(sponsorCost, minDepositThreshold)) {
            emit LowDeposit(deposit, minDepositThreshold);
            return (bytes(0), 1);
        }

        context = abi.encode(userOp.sender, userOp.nonce, actionType, target);
        validationData = 0;
    }

    // Post-operation handling
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override nonReentrant {
        require(msg.sender == address(entryPoint), "Only EntryPoint");
        (address sender, uint256 nonce, bytes32 actionType, address target) = abi.decode(
            context,
            (address, uint256, bytes32, address)
        );

        if (mode == PostOpMode.opReverted) {
            emit ValidationFailed("Operation reverted", sender, actionType, target);
            return;
        }

        totalGasSponsored += actualGasCost;
        emit GasSponsored(sender, nonce, actualGasCost, target, actionType);
    }

    // Check if account is valid
    function isValidAccount(address account) internal view returns (bool) {
        if (account == address(0)) return false;
        try ISimpleAccountFactory(simpleAccountFactory).getAddress(account, 0) returns (
            address computedAddress
        ) {
            return computedAddress == account;
        } catch {
            return false;
        }
    }

    // Receive ETH
    receive() external payable {
        if (msg.value > 0) {
            require(authorizedFunders[msg.sender], "Unauthorized funder");
            entryPoint.depositTo{value: msg.value}(address(this));
            emit DepositFunded(msg.sender, msg.value);
        }
    }
}

// TimelockController interface for scheduling
interface ITimelockController {
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
}
