// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EligibilityRegistry} from "../src/EligibilityRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {OfferingPolicy} from "../src/OfferingPolicy.sol";
import {Groth16VerifierFull} from "../src/verifiers/Groth16VerifierFull.sol";

// specs/phase-3/verification-infrastructure.md §7.4. Deploys the entire
// stack fresh per test, matching the real deployment sequence: registry,
// nullifiers, verifier, policy, then nullifiers.setAuthorized(policy) by
// the same deployer account that deployed nullifiers.
contract IntegrationTest is Test {
    EligibilityRegistry internal registry;
    NullifierRegistry internal nullifiers;
    Groth16VerifierFull internal verifier;
    OfferingPolicy internal policy;

    address internal issuer = address(0xE55);
    address internal platform = address(0xF1A7);

    // Alice's real proof against Offering A (scope = 0)
    uint256[2] internal pA;
    uint256[2][2] internal pB;
    uint256[2] internal pC;
    uint256[6] internal publicSignals;

    // Same credential, real proof against Offering B (scope = 1)
    uint256[2] internal pA_b;
    uint256[2][2] internal pB_b;
    uint256[2] internal pC_b;
    uint256[6] internal publicSignals_b;

    uint256 internal offeringA;
    uint256 internal offeringB;

    function setUp() public {
        vm.prank(issuer);
        registry = new EligibilityRegistry(issuer);
        nullifiers = new NullifierRegistry();
        verifier = new Groth16VerifierFull();
        policy = new OfferingPolicy(platform, registry, nullifiers, verifier);
        nullifiers.setAuthorized(address(policy));

        pA = [
            0x060fc32807bc7e7e464ebd95af36e153c9e0d5b5ead3dae26dc8d11a2cf683ab,
            0x2b99305a8a98c1def6bdc1a0c49f2a2a11babbf586a9064828fb02f450d54c55
        ];
        pB = [
            [
                0x1ca1a01f24aac569c0a1104eb1dc719240aa9691f5f529b8192009afe2994fa0,
                0x251082d516d29c78bf63cd5c6859fccf74a4851da0e95af110284c933489d437
            ],
            [
                0x02881368a6989192d09fb52c6af353a84b09d7dba8c3604ff5ab7ba5d05687ac,
                0x2a0b692d1c2c3d2f8a8cb6e6df86e93eb812f956621dc5ae40c38dc2feb5c968
            ]
        ];
        pC = [
            0x06af8d2f8363b3a6807a78b14a565634ab8dea65b1e7f001f2908459a40cb445,
            0x03b2d48ee0b84cfab0003f71ca58a00b0f2b4e19a57c592f81c007b4b95bbb48
        ];
        publicSignals = [
            0x1286f39bcb5e397777332dbfa971c100c51f94b406ab03e48509a11b6a259100,
            0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,
            0x0b9fa49e73ac3e867872fcbe504c1a93652e83a030af877ec38d2fd7a9b51af3,
            0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2,
            0x0000000000000000000000000000000000000000000000000000000000000005,
            0x0000000000000000000000000000000000000000000000000000000000000000
        ];

        pA_b = [
            0x02d686299443eff1218d0283e26dba243984a302301c87c2ca41312ce5675f1a,
            0x27381dbafba2e8f6a52f544ccdb3842313a21341cf5c112034b12710cebaf309
        ];
        pB_b = [
            [
                0x303bcd50892bf9e3ba0f0592f209e935ce57dc5cd057f0034f7a192c9c1fca14,
                0x03e4310c8d78d4af4a3aa7899e4c25aa3a4a6c5d8ca4ef21a0f14783414b8389
            ],
            [
                0x13cda175326819dd1805713a32c7cd3810935c5a4f9a7fd96abf9ae00d1e5ac5,
                0x14da362f04a230c097330ea4bd9e2ec7f13445fe1ebe6168afdcf0e85dc84deb
            ]
        ];
        pC_b = [
            0x036c25efef519f9f1586cfdee762e2c8fbe1b9432bce523071155dc9824070a1,
            0x046863f8b4338411ba7e305d74da1c516abad2a2a1bbb7e28ba9c83af60fb0e0
        ];
        publicSignals_b = [
            0x217d5aa38475bc769e55ca53a0149e34bb355f215433a96dd3770e5b999102b8,
            0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,
            0x0b9fa49e73ac3e867872fcbe504c1a93652e83a030af877ec38d2fd7a9b51af3,
            0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2,
            0x0000000000000000000000000000000000000000000000000000000000000005,
            0x0000000000000000000000000000000000000000000000000000000000000001
        ];

        vm.startPrank(issuer);
        registry.approveJurisdictionRoot(bytes32(publicSignals[1]));
        for (uint256 i = 0; i < 5; i++) {
            registry.publishValidSetRoot(i == 4 ? bytes32(publicSignals[3]) : bytes32(uint256(1000 + i)));
        }
        registry.publishSanctionsRoot(bytes32(publicSignals[2]));
        vm.stopPrank();

        vm.startPrank(platform);
        offeringA = policy.registerOffering(bytes32(publicSignals[1])); // id 0, matches scope=0
        offeringB = policy.registerOffering(bytes32(publicSignals[1])); // id 1, matches scope=1
        vm.stopPrank();
    }

    // Case 17
    function test_HappyPath_IssuedCredentialVerifiesOnChain() public {
        bool granted = policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
        assertTrue(granted);
    }

    // Case 18
    function test_RevocationCausesSubsequentPresentationToFail() public {
        // "Revoke" by publishing a new, different validSetRoot - no on-chain
        // leaf removal or Poseidon computation happens here (§6): currentEpoch
        // advances to 6, so Alice's original, unmodified proof (naming epoch 5)
        // now fails the epoch-freshness check.
        vm.prank(issuer);
        registry.publishValidSetRoot(bytes32(uint256(999)));

        vm.expectRevert("stale epoch");
        policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
    }

    // Case 19
    function test_SameCredentialPresentsIndependentlyToTwoOfferings() public {
        bool grantedA = policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
        bool grantedB = policy.presentEligibility(offeringB, pA_b, pB_b, pC_b, publicSignals_b);

        assertTrue(grantedA);
        assertTrue(grantedB);
        assertTrue(nullifiers.consumed(publicSignals[0]));
        assertTrue(nullifiers.consumed(publicSignals_b[0]));
    }
}
