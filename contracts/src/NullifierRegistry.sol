// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NullifierRegistry {
    mapping(uint256 => bool) public consumed;
    address public immutable deployer;
    address public authorized;

    event NullifierConsumed(uint256 indexed nullifier);

    constructor() {
        deployer = msg.sender;
    }

    function setAuthorized(address a) external {
        require(msg.sender == deployer, "not deployer");
        require(authorized == address(0), "already set");
        authorized = a;
    }

    modifier onlyAuthorized() {
        require(msg.sender == authorized, "not authorized");
        _;
    }

    function consumeIfUnused(uint256 nullifier) external onlyAuthorized {
        require(!consumed[nullifier], "nullifier already used");
        consumed[nullifier] = true;
        emit NullifierConsumed(nullifier);
    }
}
