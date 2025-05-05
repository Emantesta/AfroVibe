// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SimpleAccount is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Events
    event Executed(address indexed target, uint256 value, bytes data);

    // Constructor is disabled to prevent direct deployment
    constructor() {
        _disableInitializers();
    }

    // Initialize function to set up the contract
    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
    }

    // Execute a transaction (example functionality)
    function execute(address target, uint256 value, bytes calldata data) external onlyOwner {
        (bool success, ) = target.call{value: value}(data);
        require(success, "Execution failed");
        emit Executed(target, value, data);
    }

    // Authorize upgrade (only owner can upgrade)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Allow the contract to receive ETH
    receive() external payable {}
}
