// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EligibilityRegistry} from "../src/EligibilityRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {OfferingPolicy} from "../src/OfferingPolicy.sol";
import {Groth16VerifierFull} from "../src/verifiers/Groth16VerifierFull.sol";

// specs/phase-3/verification-infrastructure.md §7.3. Uses Alice's real
// fixture proofs for circuit_full - proof_full.json/public_full.json
// (scope=0, "Offering A") and proof_full_offeringB.json/public_full_offeringB.json
// (scope=1, "Offering B") - real Phase 2 fixture data, not mocked.
contract OfferingPolicyTest is Test {
    EligibilityRegistry internal registry;
    NullifierRegistry internal nullifiers;
    Groth16VerifierFull internal verifier;
    OfferingPolicy internal policy;

    address internal issuer = address(0xE55);
    address internal platform = address(0xF1A7);
    address internal stranger = address(0xBAD);

    // Alice's real proof against Offering A (scope = 0)
    uint256[2] internal pA;
    uint256[2][2] internal pB;
    uint256[2] internal pC;
    uint256[6] internal publicSignals;
    // [nullifier, jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope]

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

        vm.startPrank(issuer);
        registry.approveJurisdictionRoot(bytes32(publicSignals[1]));
        // reach currentEpoch = 5, matching the fixture, ending on the real validSetRoot
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

    // Case 9
    function test_NonPlatformCannotRegisterOffering() public {
        vm.prank(stranger);
        vm.expectRevert("not platform");
        policy.registerOffering(bytes32(publicSignals[1]));
    }

    // Case 9b
    function test_RegisterOfferingWithUnapprovedJurisdictionRootReverts() public {
        vm.prank(platform);
        vm.expectRevert("jurisdictionRoot not issuer-approved");
        policy.registerOffering(bytes32(uint256(0xBADBEEF)));
    }

    // Case 10
    function test_GenuineProofGrantsAccess() public {
        bool granted = policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
        assertTrue(granted);
        assertTrue(nullifiers.consumed(publicSignals[0]));
    }

    // Case 11
    function test_SamePresentationTwiceReverts() public {
        policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
        vm.expectRevert("nullifier already used");
        policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
    }

    // Case 12
    function test_ProofPresentedAgainstWrongOfferingReverts() public {
        vm.expectRevert("wrong scope for this offering");
        policy.presentEligibility(offeringB, pA, pB, pC, publicSignals);
    }

    // Case 13
    function test_ProofWithWrongJurisdictionRootForOfferingReverts() public {
        bytes32 differentRoot = bytes32(uint256(777));
        vm.prank(issuer);
        registry.approveJurisdictionRoot(differentRoot);

        vm.prank(platform);
        uint256 offeringC = policy.registerOffering(differentRoot);

        vm.expectRevert("wrong jurisdictionRoot for this offering");
        policy.presentEligibility(offeringC, pA, pB, pC, publicSignals);
    }

    // Case 14
    function test_StaleSanctionsRootReverts() public {
        vm.prank(issuer);
        registry.publishSanctionsRoot(bytes32(uint256(999999)));

        vm.expectRevert("stale or wrong sanctionsRoot");
        policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
    }

    // Case 15
    function test_StaleEpochReverts() public {
        vm.prank(issuer);
        registry.publishValidSetRoot(bytes32(uint256(12345))); // currentEpoch now 6

        vm.expectRevert("stale epoch");
        policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);
    }

    // Case 16
    function test_TamperedProofRejected() public {
        uint256[2] memory tamperedA = pA;
        tamperedA[0] = tamperedA[0] + 1;
        vm.expectRevert("invalid proof");
        policy.presentEligibility(offeringA, tamperedA, pB, pC, publicSignals);
    }
}
