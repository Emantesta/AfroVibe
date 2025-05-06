// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import "./UserOperation.sol";
import "./IStakeManager.sol";
import "./IAggregator.sol";
import "./INonceManager.sol";
import "./IEntryPoint.sol";

contract EntryPoint is IEntryPoint, IStakeManager, INonceManager {
    using UserOperationLib for UserOperation;

    // Internal state
    mapping(address => mapping(uint192 => uint256)) private _nonces;
    mapping(address => StakeInfo) private _stakes;
    address private constant _DUMMY_AGGREGATOR = address(1);

    // Events
    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost,
        uint256 actualGasUsed
    );
    event UserOperationRevertReason(
        bytes32 indexed userOpHash,
        address indexed sender,
        uint256 nonce,
        bytes revertReason
    );
    event AccountDeployed(
        bytes32 indexed userOpHash,
        address indexed sender,
        address factory,
        address paymaster
    );
    event SignatureAggregatorChanged(address indexed aggregator);
    event StakeLocked(address indexed account, uint256 totalStaked, uint256 withdrawTime);
    event StakeUnlocked(address indexed account, uint256 withdrawTime);
    event StakeWithdrawn(address indexed account, address withdrawAddress, uint256 amount);
    event Deposited(address indexed account, uint256 totalDeposit);
    event Withdrawn(address indexed account, address dest, uint256 amount);
    event BeforeExecution();

    // Constructor
    constructor() {
        // No initialization needed
    }

    // External functions
    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external override {
        require(msg.sender != address(this), "EP: recursive call");
        for (uint256 i = 0; i < ops.length; i++) {
            _handleOp(i, ops[i], beneficiary);
        }
    }

    function handleAggregatedOps(
        UserOpsPerAggregator[] calldata opsPerAggregator,
        address payable beneficiary
    ) external override {
        require(msg.sender != address(this), "EP: recursive call");
        for (uint256 i = 0; i < opsPerAggregator.length; i++) {
            UserOperation[] calldata ops = opsPerAggregator[i].userOps;
            IAggregator aggregator = opsPerAggregator[i].aggregator;
            emit SignatureAggregatorChanged(address(aggregator));
            for (uint256 j = 0; j < ops.length; j++) {
                _handleOp(j, ops[j], beneficiary);
            }
        }
    }

    function simulateValidation(UserOperation calldata userOp)
        external
        returns (ValidationData memory)
    {
        return _validateUserOp(userOp, false);
    }

    function simulateHandleOp(UserOperation calldata op, address target, bytes calldata targetCallData)
        external
    {
        _simulateHandleOp(op, target, targetCallData);
    }

    // Deposit management
    function depositTo(address account) external payable override {
        require(account != address(0), "EP: deposit to zero address");
        _stakes[account].deposit += msg.value;
        emit Deposited(account, _stakes[account].deposit);
    }

    function withdrawTo(address payable withdrawAddress, uint256 amount) external override {
        require(withdrawAddress != address(0), "EP: withdraw to zero address");
        StakeInfo storage info = _stakes[msg.sender];
        require(info.deposit >= amount, "EP: insufficient deposit");
        info.deposit -= amount;
        (bool success, ) = withdrawAddress.call{value: amount}("");
        require(success, "EP: withdraw failed");
        emit Withdrawn(msg.sender, withdrawAddress, amount);
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _stakes[account].deposit;
    }

    // Stake management
    function addStake(uint32 unstakeDelaySec) external payable override {
        StakeInfo storage info = _stakes[msg.sender];
        require(info.unstakeDelaySec == 0 || info.unstakeDelaySec == unstakeDelaySec, "EP: invalid delay");
        require(msg.value > 0, "EP: no stake provided");
        info.deposit += msg.value;
        info.stake += msg.value;
        info.unstakeDelaySec = unstakeDelaySec;
        emit StakeLocked(msg.sender, info.deposit, block.timestamp + unstakeDelaySec);
    }

    function unlockStake() external override {
        StakeInfo storage info = _stakes[msg.sender];
        require(info.stake > 0, "EP: no stake to unlock");
        require(info.withdrawTime == 0, "EP: stake already unlocking");
        info.withdrawTime = block.timestamp + info.unstakeDelaySec;
        emit StakeUnlocked(msg.sender, info.withdrawTime);
    }

    function withdrawStake(address payable withdrawAddress) external override {
        StakeInfo storage info = _stakes[msg.sender];
        require(info.stake > 0, "EP: no stake to withdraw");
        require(info.withdrawTime > 0, "EP: stake not unlocked");
        require(info.withdrawTime <= block.timestamp, "EP: stake locked");
        uint256 amount = info.stake;
        info.stake = 0;
        info.withdrawTime = 0;
        info.deposit -= amount;
        (bool success, ) = withdrawAddress.call{value: amount}("");
        require(success, "EP: withdraw failed");
        emit StakeWithdrawn(msg.sender, withdrawAddress, amount);
    }

    function getDepositInfo(address account) external view override returns (StakeInfo memory) {
        return _stakes[account];
    }

    // Nonce management
    function getNonce(address sender, uint192 key) external view override returns (uint256) {
        return _nonces[sender][key];
    }

    function incrementNonce(uint192 key) external override {
        _nonces[msg.sender][key]++;
    }

    // Internal functions
    function _handleOp(uint256 opIndex, UserOperation calldata op, address payable beneficiary) internal {
        bytes32 userOpHash = getUserOpHash(op);
        ValidationData memory validationData = _validateUserOp(op, true);
        if (validationData.aggregator != address(0) && validationData.aggregator != _DUMMY_AGGREGATOR) {
            revert("EP: invalid aggregator");
        }

        uint256 gasUsed;
        bool success;
        bytes memory result;
        emit BeforeExecution();
        try this._executeOp{gas: op.callGasLimit}(op, userOpHash) returns (uint256 _gasUsed, bool _success, bytes memory _result) {
            gasUsed = _gasUsed;
            success = _success;
            result = _result;
        } catch (bytes memory reason) {
            gasUsed = op.preVerificationGas + op.verificationGasLimit;
            emit UserOperationRevertReason(userOpHash, op.sender, op.nonce, reason);
            return;
        }

        uint256 actualGasCost = gasUsed * tx.gasprice;
        emit UserOperationEvent(
            userOpHash,
            op.sender,
            op.paymaster,
            op.nonce,
            success,
            actualGasCost,
            gasUsed
        );
    }

    function _executeOp(UserOperation calldata op, bytes32 userOpHash)
        external
        returns (uint256 gasUsed, bool success, bytes memory result)
    {
        require(msg.sender == address(this), "EP: external call");
        gasUsed = gasleft();
        if (op.initCode.length > 0) {
            _deployAccount(op, userOpHash);
        }
        (success, result) = op.sender.call{value: 0, gas: op.callGasLimit}(op.callData);
        gasUsed = gasUsed - gasleft();
    }

    function _deployAccount(UserOperation calldata op, bytes32 userOpHash) internal {
        address factory = address(bytes20(op.initCode[0:20]));
        bytes memory initCallData = op.initCode[20:];
        (bool success, bytes memory result) = factory.call(initCallData);
        require(success, string(abi.encodePacked("EP: factory failed: ", result)));
        address deployed = address(uint160(uint256(keccak256(abi.encodePacked(
            hex"ff",
            factory,
            keccak256(initCallData),
            block.chainid
        ))))));
        require(deployed == op.sender, "EP: invalid sender");
        emit AccountDeployed(userOpHash, op.sender, factory, op.paymaster);
    }

    function _validateUserOp(UserOperation calldata userOp, bool withExecution)
        internal
        returns (ValidationData memory)
    {
        bytes32 userOpHash = getUserOpHash(userOp);
        ValidationData memory validationData;

        // Validate sender
        if (userOp.initCode.length == 0) {
            (bool success, bytes memory result) = userOp.sender.call{gas: userOp.verificationGasLimit}(
                abi.encodeWithSignature("validateUserOp((address,uint256,bytes,bytes,uint256,uint256,uint256,uint256,uint256,bytes,bytes),bytes32,uint256)",
                    userOp, userOpHash, userOp.maxFeePerGas)
            );
            require(success, string(abi.encodePacked("EP: sender validation failed: ", result)));
            validationData = abi.decode(result, (ValidationData));
        }

        // Validate paymaster
        if (userOp.paymasterAndData.length >= 20) {
            address paymaster = address(bytes20(userOp.paymasterAndData[0:20]));
            (bool success, bytes memory result) = paymaster.call{gas: userOp.verificationGasLimit}(
                abi.encodeWithSignature("validatePaymasterUserOp((address,uint256,bytes,bytes,uint256,uint256,uint256,uint256,uint256,bytes,bytes),bytes32,uint256)",
                    userOp, userOpHash, userOp.maxFeePerGas)
            );
            require(success, string(abi.encodePacked("EP: paymaster validation failed: ", result)));
            (bytes memory context, uint256 validationData2) = abi.decode(result, (bytes, uint256));
            validationData = _intersectValidationData(validationData, ValidationData(paymaster, validationData2));
        }

        // Increment nonce
        if (withExecution) {
            _nonces[userOp.sender][uint192(userOp.nonce >> 64)]++;
        }

        return validationData;
    }

    function _simulateHandleOp(UserOperation calldata op, address target, bytes calldata targetCallData) internal {
        bytes32 userOpHash = getUserOpHash(op);
        ValidationData memory validationData = _validateUserOp(op, false);
        if (validationData.aggregator != address(0) && validationData.aggregator != _DUMMY_AGGREGATOR) {
            revert("EP: invalid aggregator");
        }

        if (op.initCode.length > 0) {
            _deployAccount(op, userOpHash);
        }

        (bool success, bytes memory result) = target.call{gas: op.callGasLimit}(targetCallData);
        if (!success) {
            revert(string(abi.encodePacked("EP: call failed: ", result)));
        }
    }

    function getUserOpHash(UserOperation calldata userOp) public view returns (bytes32) {
        return keccak256(abi.encode(
            userOp.sender,
            userOp.nonce,
            keccak256(userOp.initCode),
            keccak256(userOp.callData),
            userOp.callGasLimit,
            userOp.verificationGasLimit,
            userOp.preVerificationGas,
            userOp.maxFeePerGas,
            userOp.maxPriorityFeePerGas,
            keccak256(userOp.paymasterAndData),
            block.chainid
        ));
    }

    function _intersectValidationData(ValidationData memory data1, ValidationData memory data2)
        internal
        pure
        returns (ValidationData memory)
    {
        address aggregator = data1.aggregator != address(0) ? data1.aggregator : data2.aggregator;
        uint48 validAfter = data1.validAfter > data2.validAfter ? data1.validAfter : data2.validAfter;
        uint48 validUntil = data1.validUntil == 0 ? data2.validUntil : (data2.validUntil == 0 ? data1.validUntil : data1.validUntil < data2.validUntil ? data1.validUntil : data2.validUntil);
        return ValidationData(aggregator, validAfter, validUntil);
    }

    // Fallback to receive S tokens
    receive() external payable {}
}
