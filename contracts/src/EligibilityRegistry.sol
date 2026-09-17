// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EligibilityRegistry {
    address public immutable issuer;

    uint256 public currentEpoch;
    mapping(uint256 => bytes32) public validSetRootAt;
    bytes32 public sanctionsRoot;
    mapping(bytes32 => bool) public approvedJurisdictionRoots;

    event ValidSetRootPublished(uint256 indexed epoch, bytes32 root);
    event SanctionsRootPublished(bytes32 root);
    event JurisdictionRootApproved(bytes32 root);

    modifier onlyIssuer() {
        require(msg.sender == issuer, "not issuer");
        _;
    }

    constructor(address _issuer) {
        issuer = _issuer;
    }

    function publishValidSetRoot(bytes32 newRoot) external onlyIssuer {
        currentEpoch += 1;
        validSetRootAt[currentEpoch] = newRoot;
        emit ValidSetRootPublished(currentEpoch, newRoot);
    }

    function publishSanctionsRoot(bytes32 newRoot) external onlyIssuer {
        sanctionsRoot = newRoot;
        emit SanctionsRootPublished(newRoot);
    }

    function approveJurisdictionRoot(bytes32 root) external onlyIssuer {
        approvedJurisdictionRoots[root] = true;
        emit JurisdictionRootApproved(root);
    }
}
