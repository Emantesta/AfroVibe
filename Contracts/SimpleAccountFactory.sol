// Factory for smart contract wallets
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SimpleAccount.sol";

contract SimpleAccountFactory {
    address public immutable accountImplementation;

    event AccountCreated(address indexed owner, address indexed account);

    constructor(address _accountImplementation) {
        accountImplementation = _accountImplementation;
    }

    function createAccount(address owner, bytes32 salt) external returns (address) {
        // Deploy new account using CREATE2
        SimpleAccount account = new SimpleAccount{salt: salt}();
        account.initialize(owner);
        emit AccountCreated(owner, address(account));
        return address(account);
    }

    function getAccountAddress(address owner, bytes32 salt) external view returns (address) {
        // Predict address using CREATE2
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(SimpleAccount).creationCode,
                abi.encode(accountImplementation)
            ))
        ))))));
    }
}
