// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title TimelockController
 * @dev A contract that delays execution of governance operations to ensure transparency and security.
 * Authorized proposers can schedule operations, which can be executed by a multi-sig executor after a minimum delay.
 * Supports batch operations, predecessor dependencies, and upgradeability via UUPS proxy.
 */
contract TimelockController is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    // Roles for governance
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Operation states
    enum OperationState {
        Unset,
        Pending,
        Ready,
        Done
    }

    // Operation structure
    struct Operation {
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
        uint256 timestamp; // When the operation becomes ready
    }

    // Minimum and maximum delay for operations
    uint256 public minDelay;
    uint256 public constant MAX_DELAY = 30 days;

    // Mapping of operation ID to operation details
    mapping(bytes32 => Operation) private _operations;

    // Multi-sig address for executor role
    address public immutable multiSigExecutor;

    // Events
    event OperationScheduled(
        bytes32 indexed id,
        address indexed target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay,
        uint256 timestamp
    );
    event OperationExecuted(bytes32 indexed id, address indexed target, uint256 value, bytes data);
    event OperationCancelled(bytes32 indexed id);
    event MinDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event CallSalt(bytes32 indexed id, bytes32 salt);

    /**
     * @dev Constructor to set the multi-sig executor and disable initialization.
     * @param _multiSigExecutor The address of the multi-sig wallet (e.g., Gnosis Safe) for execution.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _multiSigExecutor) {
        require(_multiSigExecutor != address(0), "Invalid multi-sig executor");
        multiSigExecutor = _multiSigExecutor;
        _disableInitializers();
    }

    /**
     * @dev Initializer for the UUPS proxy.
     * @param _minDelay Minimum delay for operations (e.g., 2 days).
     * @param _proposers List of addresses allowed to propose operations.
     * @param _admin Initial admin address (can be revoked after setup).
     */
    function initialize(
        uint256 _minDelay,
        address[] memory _proposers,
        address _admin
    ) public initializer {
        require(_minDelay <= MAX_DELAY, "Delay exceeds maximum");
        require(_admin != address(0), "Invalid admin");

        __AccessControl_init();
        __UUPSUpgradeable_init();

        minDelay = _minDelay;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(EXECUTOR_ROLE, multiSigExecutor); // Restrict to multi-sig

        // Initialize proposers
        for (uint256 i = 0; i < _proposers.length; ) {
            require(_proposers[i] != address(0), "Invalid proposer");
            _grantRole(PROPOSER_ROLE, _proposers[i]);
            unchecked { i++; }
        }
    }

    /**
     * @dev Restrict upgrades to ADMIN_ROLE.
     */
    function _authorizeUpgrade(address) internal override onlyRole(ADMIN_ROLE) {}

    /**
     * @dev Modifier to check if the caller is the multi-sig executor.
     */
    modifier onlyExecutor() {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "Caller is not the executor");
        _;
    }

    /**
     * @dev Returns whether an operation is pending or ready.
     * @param id The operation ID.
     * @return The operation state (Unset, Pending, Ready, Done).
     */
    function getOperationState(bytes32 id) public view returns (OperationState) {
        Operation memory op = _operations[id];
        if (op.timestamp == 0) {
            return OperationState.Unset;
        }
        if (op.timestamp == type(uint256).max) {
            return OperationState.Done;
        }
        if (block.timestamp < op.timestamp) {
            return OperationState.Pending;
        }
        return OperationState.Ready;
    }

    /**
     * @dev Returns the timestamp when an operation becomes ready.
     * @param id The operation ID.
     * @return The ready timestamp or 0 if unset.
     */
    function getTimestamp(bytes32 id) public view returns (uint256) {
        return _operations[id].timestamp;
    }

    /**
     * @dev Schedules an operation.
     * @param target The target contract address.
     * @param value The ETH value to send.
     * @param data The call data.
     * @param predecessor The ID of a predecessor operation (0 if none).
     * @param salt A unique salt for the operation.
     * @param delay The delay before execution (must be >= minDelay).
     */
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(target != address(0), "Invalid target");
        require(delay >= minDelay, "Delay below minimum");
        require(delay <= MAX_DELAY, "Delay exceeds maximum");

        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        require(getOperationState(id) == OperationState.Unset, "Operation already scheduled");

        if (predecessor != bytes32(0)) {
            require(_operations[predecessor].timestamp != 0, "Invalid predecessor");
            require(getOperationState(predecessor) != OperationState.Unset, "Predecessor not scheduled");
        }

        _operations[id] = Operation({
            target: target,
            value: value,
            data: data,
            predecessor: predecessor,
            salt: salt,
            timestamp: block.timestamp + delay
        });

        emit OperationScheduled(id, target, value, data, predecessor, salt, delay, block.timestamp + delay);
        emit CallSalt(id, salt);
    }

    /**
     * @dev Schedules a batch of operations.
     * @param targets Array of target contract addresses.
     * @param values Array of ETH values.
     * @param datas Array of call data.
     * @param predecessor The ID of a predecessor operation.
     * @param salt A unique salt for the batch.
     * @param delay The delay before execution.
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(targets.length == values.length, "Array length mismatch");
        require(targets.length == datas.length, "Array length mismatch");
        require(delay >= minDelay, "Delay below minimum");
        require(delay <= MAX_DELAY, "Delay exceeds maximum");

        bytes32 id = hashOperationBatch(targets, values, datas, predecessor, salt);
        require(getOperationState(id) == OperationState.Unset, "Operation already scheduled");

        if (predecessor != bytes32(0)) {
            require(_operations[predecessor].timestamp != 0, "Invalid predecessor");
            require(getOperationState(predecessor) != OperationState.Unset, "Predecessor not scheduled");
        }

        for (uint256 i = 0; i < targets.length; ) {
            require(targets[i] != address(0), "Invalid target");
            unchecked { i++; }
        }

        _operations[id] = Operation({
            target: address(0),
            value: 0,
            data: abi.encode(targets, values, datas),
            predecessor: predecessor,
            salt: salt,
            timestamp: block.timestamp + delay
        });

        emit OperationScheduled(id, address(0), 0, abi.encode(targets, values, datas), predecessor, salt, delay, block.timestamp + delay);
        emit CallSalt(id, salt);
    }

    /**
     * @dev Cancels a scheduled operation.
     * @param id The operation ID.
     */
    function cancel(bytes32 id) external onlyRole(ADMIN_ROLE) {
        require(getOperationState(id) == OperationState.Pending, "Operation not pending");
        delete _operations[id];
        emit OperationCancelled(id);
    }

    /**
     * @dev Executes a ready operation.
     * @param target The target contract address.
     * @param value The ETH value to send.
     * @param data The call data.
     * @param predecessor The ID of a predecessor operation.
     * @param salt A unique salt for the operation.
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external payable onlyExecutor {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        require(getOperationState(id) == OperationState.Ready, "Operation not ready");

        if (predecessor != bytes32(0)) {
            require(getOperationState(predecessor) == OperationState.Done, "Predecessor not executed");
        }

        _operations[id].timestamp = type(uint256).max; // Mark as Done

        (bool success, ) = target.call{value: value}(data);
        require(success, "Execution failed");

        emit OperationExecuted(id, target, value, data);
    }

    /**
     * @dev Executes a batch of ready operations.
     * @param targets Array of target contract addresses.
     * @param values Array of ETH values.
     * @param datas Array of call data.
     * @param predecessor The ID of a predecessor operation.
     * @param salt A unique salt for the batch.
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) external payable onlyExecutor {
        require(targets.length == values.length, "Array length mismatch");
        require(targets.length == datas.length, "Array length mismatch");

        bytes32 id = hashOperationBatch(targets, values, datas, predecessor, salt);
        require(getOperationState(id) == OperationState.Ready, "Operation not ready");

        if (predecessor != bytes32(0)) {
            require(getOperationState(predecessor) == OperationState.Done, "Predecessor not executed");
        }

        _operations[id].timestamp = type(uint256).max; // Mark as Done

        for (uint256 i = 0; i < targets.length; ) {
            (bool success, ) = targets[i].call{value: values[i]}(datas[i]);
            require(success, "Batch execution failed");
            unchecked { i++; }
        }

        emit OperationExecuted(id, address(0), 0, abi.encode(targets, values, datas));
    }

    /**
     * @dev Updates the minimum delay.
     * @param newDelay The new minimum delay.
     */
    function updateMinDelay(uint256 newDelay) external onlyRole(ADMIN_ROLE) {
        require(newDelay <= MAX_DELAY, "Delay exceeds maximum");
        emit MinDelayUpdated(minDelay, newDelay);
        minDelay = newDelay;
    }

    /**
     * @dev Computes the operation ID for a single operation.
     */
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    /**
     * @dev Computes the operation ID for a batch operation.
     */
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(targets, values, datas, predecessor, salt));
    }

    /**
     * @dev Allows the contract to receive ETH for operations with value.
     */
    receive() external payable {}
