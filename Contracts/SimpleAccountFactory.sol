// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./SimpleAccount.sol";

contract SimpleAccountFactory {
    address public immutable accountImplementation;

    event AccountCreated(address indexed owner, address indexed account, bytes32 salt);

    constructor(address _accountImplementation) {
        accountImplementation = _accountImplementation;
    }

    function createAccount(address owner, bytes32 salt) external returns (address) {
        // Deploy UUPS proxy using CREATE2
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            accountImplementation,
            abi.encodeWithSelector(SimpleAccount.initialize.selector, owner)
        );
        emit AccountCreated(owner, address(proxy), salt);
        return address(proxy);
    }

    function getAccountAddress(address owner, bytes32 salt) external view returns (address) {
        // Predict proxy address using CREATE2
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    accountImplementation,
                    abi.encodeWithSelector(SimpleAccount.initialize.selector, owner)
                )
            ))
        ))))));
    }
