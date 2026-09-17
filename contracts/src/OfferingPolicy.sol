// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EligibilityRegistry} from "./EligibilityRegistry.sol";
import {NullifierRegistry} from "./NullifierRegistry.sol";
import {Groth16VerifierFull} from "./verifiers/Groth16VerifierFull.sol";

contract OfferingPolicy {
    struct Offering {
        bytes32 jurisdictionRoot;
        bool exists;
        // no separate `scope` field - the mapping key (offeringId) IS the scope
    }

    address public immutable platform;
    EligibilityRegistry public immutable registry;
    NullifierRegistry public immutable nullifiers;
    Groth16VerifierFull public immutable verifier; // circuit_full only

    uint256 public nextOfferingId;
    mapping(uint256 => Offering) public offerings;

    event OfferingRegistered(uint256 indexed offeringId, bytes32 jurisdictionRoot);
    event EligibilityGranted(uint256 indexed offeringId, uint256 indexed nullifier);

    modifier onlyPlatform() {
        require(msg.sender == platform, "not platform");
        _;
    }

    constructor(address _platform, EligibilityRegistry _registry, NullifierRegistry _nullifiers, Groth16VerifierFull _verifier) {
        platform = _platform;
        registry = _registry;
        nullifiers = _nullifiers;
        verifier = _verifier;
    }

    function registerOffering(bytes32 jurisdictionRoot) external onlyPlatform returns (uint256 offeringId) {
        require(registry.approvedJurisdictionRoots(jurisdictionRoot), "jurisdictionRoot not issuer-approved");
        offeringId = nextOfferingId++;
        offerings[offeringId] = Offering(jurisdictionRoot, true);
        emit OfferingRegistered(offeringId, jurisdictionRoot);
    }

    function presentEligibility(
        uint256 offeringId,
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[6] calldata publicSignals
        // [nullifier, jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope] -
        // outputs first (circom's universal R1CS wire layout), then circuit_full's declared
        // public inputs in the order component main {public [...]} lists them. Verified
        // against circuit_full.circom's literal declaration line and cross-checked by value
        // against circuits/credential/input_full.json vs. public_full.json.
    ) external returns (bool granted) {
        Offering memory o = offerings[offeringId];
        require(o.exists, "unknown offering");

        // Recorded-value cross-checks (credential-protocol.md §5.4) - before the expensive
        // cryptographic verification, so a mismatched offering fails cheaply.
        require(publicSignals[1] == uint256(o.jurisdictionRoot), "wrong jurisdictionRoot for this offering");
        require(publicSignals[2] == uint256(registry.sanctionsRoot()), "stale or wrong sanctionsRoot");
        require(publicSignals[4] == registry.currentEpoch(), "stale epoch");
        require(publicSignals[3] == uint256(registry.validSetRootAt(publicSignals[4])), "wrong validSetRoot for the current epoch");
        require(publicSignals[5] == offeringId, "wrong scope for this offering");

        // Cryptographic binding (credential-protocol.md §5.4) - the proof itself.
        require(verifier.verifyProof(pA, pB, pC, publicSignals), "invalid proof");

        // Atomic with verification - no window for a second presentation to slip
        // through between "verified" and "recorded" (credential-protocol.md §7).
        nullifiers.consumeIfUnused(publicSignals[0]);
        emit EligibilityGranted(offeringId, publicSignals[0]);

        granted = true;
    }
}
