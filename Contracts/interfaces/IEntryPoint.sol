// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./UserOperation.sol";

interface IEntryPoint {
    struct ValidationData {
        address aggregator;
        uint48 validAfter;
        uint48 validUntil;
    }

    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external;
    function handleAggregatedOps(UserOpsPerAggregator[] calldata opsPerAggregator, address payable beneficiary) external;
    function simulateValidation(UserOperation calldata userOp) external returns (ValidationData memory);
    function simulateHandleOp(UserOperation calldata op, address target, bytes calldata targetCallData) external;
    function getUserOpHash(UserOperation calldata userOp) external view returns (bytes32);
}

struct UserOpsPerAggregator {
    UserOperation[] userOps;
    IAggregator aggregator;
    bytes signature;
}
