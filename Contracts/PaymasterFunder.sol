// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface for AfroVibePaymaster
interface IPaymaster {
    function depositSonicS(uint256 amount) external;
}

/// @title PaymasterFunder
/// @notice A contract to manage funding of an AfroVibePaymaster with Sonic S tokens, using role-based access control.
/// @dev This contract is upgradeable via TransparentUpgradeableProxy, uses a multi-signature wallet for admin roles,
///      and includes reentrancy protection, pausing, timelock for admin actions, and funding history.
///      Funders must approve this contract to transfer Sonic S tokens on their behalf.
contract PaymasterFunder is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    // Role identifiers
    bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The AfroVibePaymaster contract to fund.
    /// @dev Immutable to prevent changes after initialization.
    IPaymaster public immutable paymaster;

    /// @notice The Sonic S ERC-20 token used for funding.
    /// @dev Immutable to prevent changes after initialization.
    IERC20 public immutable sonicSToken;

    /// @notice Minimum amount of Sonic S tokens per funding operation.
    /// @dev Immutable to reduce gas costs.
    uint256 public immutable minFundingAmount;

    /// @notice Maximum amount of Sonic S tokens per funding operation.
    uint256 public maxFundingAmount;

    /// @notice Maximum total Sonic S tokens the contract can hold.
    uint256 public maxContractBalance;

    /// @notice Duration for timelock on admin actions (1 day).
    uint256 public constant TIMELOCK_DURATION = 1 days;

    /// @notice Struct to store timelock actions for admin operations.
    /// @dev Used for delayed execution of sensitive actions.
    struct TimelockAction {
        uint256 amount; // Amount for the action (e.g., funding amount, withdraw amount)
        uint256 timestamp; // When the action was initiated
        bool executed; // Whether the action has been executed
    }

    /// @notice Mapping of action IDs to timelock actions.
    mapping(bytes32 => TimelockAction) public timelockActions;

    /// @notice Struct to store funding history entries.
    struct Funding {
        address funder; // Address that initiated the funding
        uint256 amount; // Amount of Sonic S tokens funded
        uint256 timestamp; // Timestamp of the funding
    }

    /// @notice Array storing the history of funding operations.
    Funding[] public fundingHistory;

    // Events
    /// @notice Emitted when the paymaster is funded with Sonic S tokens.
    /// @param paymaster The address of the paymaster.
    /// @param funder The address that funded the paymaster.
    /// @param amount The amount of Sonic S tokens funded.
    event Funded(address indexed paymaster, address indexed funder, uint256 amount);

    /// @notice Emitted when the maximum funding amount is updated.
    /// @param newAmount The new maximum funding amount.
    event MaxFundingAmountUpdated(uint256 newAmount);

    /// @notice Emitted when an emergency withdrawal is executed.
    /// @param to The recipient of the withdrawn tokens.
    /// @param amount The amount of Sonic S tokens withdrawn.
    event EmergencyWithdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when the maximum contract balance is updated.
    /// @param newBalance The new maximum contract balance.
    event MaxContractBalanceUpdated(uint256 newBalance);

    /// @notice Emitted when a timelock action is initiated.
    /// @param actionId The unique ID of the timelock action.
    /// @param action The type of action (e.g., "updateMaxFundingAmount").
    /// @param amount The amount associated with the action.
    /// @param timestamp The timestamp when the action was initiated.
    event TimelockInitiated(bytes32 indexed actionId, string action, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a timelock action is executed.
    /// @param actionId The unique ID of the timelock action.
    /// @param action The type of action (e.g., "updateMaxFundingAmount").
    /// @param amount The amount associated with the action.
    event TimelockExecuted(bytes32 indexed actionId, string action, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the provided parameters.
    /// @dev Replaces the constructor for upgradeability. Can only be called once.
    /// @param _paymaster The address of the AfroVibePaymaster contract.
    /// @param _sonicSToken The address of the Sonic S ERC-20 token contract.
    /// @param _multiSigWallet The address of the multi-signature wallet (e.g., Gnosis Safe) for admin roles.
    /// @param _minFundingAmount The minimum Sonic S tokens per funding operation.
    /// @param _maxFundingAmount The maximum Sonic S tokens per funding operation.
    /// @param _maxContractBalance The maximum Sonic S tokens the contract can hold.
    function initialize(
        address _paymaster,
        address _sonicSToken,
        address _multiSigWallet,
        uint256 _minFundingAmount,
        uint256 _maxFundingAmount,
        uint256 _maxContractBalance
    ) public initializer {
        require(_paymaster != address(0), "Invalid paymaster address");
        require(_sonicSToken != address(0), "Invalid token address");
        require(_multiSigWallet != address(0), "Invalid multi-sig wallet address");
        require(_minFundingAmount > 0, "Invalid min funding amount");
        require(_maxFundingAmount >= _minFundingAmount, "Invalid max funding amount");
        require(_maxContractBalance > 0, "Invalid max contract balance");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        paymaster = IPaymaster(_paymaster);
        sonicSToken = IERC20(_sonicSToken);
        minFundingAmount = _minFundingAmount;
        maxFundingAmount = _maxFundingAmount;
        maxContractBalance = _maxContractBalance;

        _grantRole(DEFAULT_ADMIN_ROLE, _multiSigWallet);
        _grantRole(FUNDER_ROLE, _multiSigWallet);
        _grantRole(PAUSER_ROLE, _multiSigWallet);
    }

    /// @notice Funds the paymaster with Sonic S tokens.
    /// @dev Requires the caller to have FUNDER_ROLE and approve this contract to transfer tokens.
    ///      Includes reentrancy protection and checks paymaster balance.
    /// @param amount The amount of Sonic S tokens to fund.
    function fund(uint256 amount) external onlyRole(FUNDER_ROLE) whenNotPaused nonReentrant {
        require(amount >= minFundingAmount, "Below min funding amount");
        require(amount <= maxFundingAmount, "Exceeds max funding amount");
        uint256 newBalance = sonicSToken.balanceOf(address(this)) + amount;
        require(newBalance <= maxContractBalance, "Exceeds max contract balance");

        // Transfer tokens from funder to this contract
        require(sonicSToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        // Verify paymaster balance before and after deposit
        uint256 previousBalance = sonicSToken.balanceOf(address(paymaster));
        paymaster.depositSonicS(amount);
        require(
            sonicSToken.balanceOf(address(paymaster)) >= previousBalance + amount,
            "Paymaster deposit failed"
        );

        // Record funding
        fundingHistory.push(Funding(msg.sender, amount, block.timestamp));
        emit Funded(address(paymaster), msg.sender, amount);
    }

    /// @notice Initiates an update to the maximum funding amount with a timelock.
    /// @dev Requires DEFAULT_ADMIN_ROLE. The update must be executed after TIMELOCK_DURATION.
    /// @param newAmount The new maximum funding amount.
    function initiateUpdateMaxFundingAmount(uint256 newAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAmount >= minFundingAmount, "Invalid amount");
        bytes32 actionId = keccak256(abi.encode("updateMaxFundingAmount", newAmount, block.timestamp));
        timelockActions[actionId] = TimelockAction(newAmount, block.timestamp, false);
        emit TimelockInitiated(actionId, "updateMaxFundingAmount", newAmount, block.timestamp);
    }

    /// @notice Executes the update to the maximum funding amount after the timelock period.
    /// @dev Requires DEFAULT_ADMIN_ROLE and a valid, unexecuted timelock action.
    /// @param actionId The ID of the timelock action.
    function executeUpdateMaxFundingAmount(bytes32 actionId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TimelockAction storage action = timelockActions[actionId];
        require(action.timestamp > 0, "Action does not exist");
        require(!action.executed, "Action already executed");
        require(block.timestamp >= action.timestamp + TIMELOCK_DURATION, "Timelock not expired");

        maxFundingAmount = action.amount;
        action.executed = true;
        emit MaxFundingAmountUpdated(action.amount);
        emit TimelockExecuted(actionId, "updateMaxFundingAmount", action.amount);
    }

    /// @notice Initiates an update to the maximum contract balance with a timelock.
    /// @dev Requires DEFAULT_ADMIN_ROLE. The update must be executed after TIMELOCK_DURATION.
    /// @param newBalance The new maximum contract balance.
    function initiateUpdateMaxContractBalance(uint256 newBalance)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newBalance > 0, "Invalid balance");
        bytes32 actionId = keccak256(abi.encode("updateMaxContractBalance", newBalance, block.timestamp));
        timelockActions[actionId] = TimelockAction(newBalance, block.timestamp, false);
        emit TimelockInitiated(actionId, "updateMaxContractBalance", newBalance, block.timestamp);
    }

   些1
    /// @notice Executes the update to the maximum contract balance after the timelock period.
    /// @dev Requires DEFAULT_ADMIN_ROLE and a valid, unexecuted timelock action.
    /// @param actionId The ID of the timelock action.
    function executeUpdateMaxContractBalance(bytes32 actionId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TimelockAction storage action = timelockActions[actionId];
        require(action.timestamp > 0, "Action does not exist");
        require(!action.executed, "Action already executed");
        require(block.timestamp >= action.timestamp + TIMELOCK_DURATION, "Timelock not expired");

        maxContractBalance = action.amount;
        action.executed = true;
        emit MaxContractBalanceUpdated(action.amount);
        emit TimelockExecuted(actionId, "updateMaxContractBalance", action.amount);
    }

    /// @notice Initiates an emergency withdrawal of Sonic S tokens with a timelock.
    /// @dev Requires DEFAULT_ADMIN_ROLE. The withdrawal must be executed after TIMELOCK_DURATION.
    /// @param to The recipient address for the withdrawn tokens.
    /// @param amount The amount of Sonic S tokens to withdraw.
    function initiateEmergencyWithdraw(address to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(to != address(0), "Invalid recipient");
        require(amount <= sonicSToken.balanceOf(address(this)), "Insufficient balance");
        bytes32 actionId = keccak256(abi.encode("emergencyWithdraw", to, amount, block.timestamp));
        timelockActions[actionId] = TimelockAction(amount, block.timestamp, false);
        emit TimelockInitiated(actionId, "emergencyWithdraw", amount, block.timestamp);
    }

    /// @notice Executes the emergency withdrawal after the timelock period.
    /// @dev Requires DEFAULT_ADMIN_ROLE, a valid timelock action, and reentrancy protection.
    /// @param actionId The ID of the timelock action.
    /// @param to The recipient address for the withdrawn tokens.
    function executeEmergencyWithdraw(bytes32 actionId, address to)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        TimelockAction storage action = timelockActions[actionId];
        require(action.timestamp > 0, "Action does not exist");
        require(!action.executed, "Action already executed");
        require(block.timestamp >= action.timestamp + TIMELOCK_DURATION, "Timelock not expired");

        action.executed = true;
        require(sonicSToken.transfer(to, action.amount), "Token transfer failed");
        emit EmergencyWithdrawn(to, action.amount);
        emit TimelockExecuted(actionId, "emergencyWithdraw", action.amount);
    }

    /// @notice Pauses the contract, disabling funding and emergency withdrawals.
    /// @dev Requires PAUSER_ROLE.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract, re-enabling funding and emergency withdrawals.
    /// @dev Requires PAUSER_ROLE.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Revokes the FUNDER_ROLE from an account.
    /// @dev Requires DEFAULT_ADMIN_ROLE.
    /// @param account The account to revoke the role from.
    function revokeFunderRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(FUNDER_ROLE, account);
    }

    /// @notice Grants the FUNDER_ROLE to an account.
    /// @dev Requires DEFAULT_ADMIN_ROLE.
    /// @param account The account to grant the role to.
    function grantFunderRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(FUNDER_ROLE, account);
    }

    /// @notice Returns the number of funding operations in the history.
    /// @return The length of the funding history array.
    function getFundingHistoryLength() external view returns (uint256) {
        return fundingHistory.length;
    }

    /// @notice Returns the current Sonic S token balance of the paymaster.
    /// @return The balance of Sonic S tokens held by the paymaster.
    function getPaymasterBalance() external view returns (uint256) {
        return sonicSToken.balanceOf(address(paymaster));
    }
}
