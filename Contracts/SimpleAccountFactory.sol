// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./SimpleAccount.sol";

interface ISafe {
    function isOwner(address owner) external view returns (bool);
}

contract SimpleAccountFactory {
    address public immutable accountImplementation;
    address public immutable multisig;
    address public immutable sonicGateway;
    address public immutable sonicValidator;
    address public immutable beetsStaking;
    address public immutable feeCollector;
    address public immutable entryPoint;

    event AccountCreated(address indexed owner, address indexed account, bytes32 salt);

    constructor(
        address _accountImplementation,
        address _multisig,
        address _sonicGateway,
        address _sonicValidator,
        address _beetsStaking,
        address _feeCollector,
        address _entryPoint
    ) {
        require(_accountImplementation != address(0), "Invalid implementation");
        require(_multisig != address(0), "Invalid multisig");
        require(_sonicGateway != address(0), "Invalid gateway");
        require(_sonicValidator != address(0), "Invalid validator");
        require(_beetsStaking != address(0), "Invalid BEETS staking");
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_entryPoint != address(0), "Invalid entry point");
        accountImplementation = _accountImplementation;
        multisig = _multisig;
        sonicGateway = _sonicGateway;
        sonicValidator = _sonicValidator;
        beetsStaking = _beetsStaking;
        feeCollector = _feeCollector;
        entryPoint = _entryPoint;
    }

    function createAccount(address owner, bytes32 salt) external returns (address) {
        require(owner != address(0), "Invalid owner");
        require(ISafe(multisig).isOwner(owner), "Not multisig owner");
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            accountImplementation,
            abi.encodeWithSelector(
                SimpleAccount.initialize.selector,
                multisig,
                sonicGateway,
                sonicValidator,
                beetsStaking,
                feeCollector,
                entryPoint
            )
        );
        emit AccountCreated(owner, address(proxy), salt);
        return address(proxy);
    }

    function getAccountAddress(address owner, bytes32 salt) external view returns (address) {
        require(owner != address(0), "Invalid owner");
        require(ISafe(multisig).isOwner(owner), "Not multisig owner");
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    accountImplementation,
                    abi.encodeWithSelector(
                        SimpleAccount.initialize.selector,
                        multisig,
                        sonicGateway,
                        sonicValidator,
                        beetsStaking,
                        feeCollector,
                        entryPoint
                    )
                )
            ))
        ))))));
    }
