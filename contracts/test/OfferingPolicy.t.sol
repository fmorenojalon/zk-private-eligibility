// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EligibilityRegistry} from "../src/EligibilityRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {OfferingPolicy} from "../src/OfferingPolicy.sol";
import {Groth16VerifierFull} from "../src/verifiers/Groth16VerifierFull.sol";

// specs/phase-3/verification-infrastructure.md Section 7.3. Uses Alice's real
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
            0x24861ea70418a9050775457a21f51154d4f3e7ab973b855a5f6dfd7804c1c772,
            0x1f5dc70ca8cb58d6d12d235842975150405ed7a682c6e45271acbe9b973ed0e1
        ];
        pB = [
            [
                0x2160dee2f49cab55e47de064e66c559d7a4dc369f6fa7e509c2ac87a85bae199,
                0x2f82a2da8da367e173f0487c6a5dab9f9c601d42d8cbaae6abbf731d8bf61b1c
            ],
            [
                0x25570d11eb2bec7548e7d5fbe5e4f8a8cd6dfae79f5b5b81dd6e3dbbb5e753a2,
                0x0d4f415ca39939d25a70fdc4b7ba3b5b52fba5460bbffbae46499be87c2ca3cf
            ]
        ];
        pC = [
            0x164f3788a330c007d4f10691b981d15648af712ba4cfcba723921e1feb6c2fb1,
            0x0f28c1ff33e619d386c40c1b2aba17a7a66ab787b106a829c583b5ad43c94654
        ];
        publicSignals = [
            0x08d54883e989bc5094454a9625a15d0abe3b96de641f26cec85f3eef7bef8bab,
            0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,
            0x019bd66abc02866ee9621d2377848d93a98a7f17f1fcc7ec337ece1e5368a21a,
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

    // Case 11b - case 11 above only resubmits the literal same calldata
    // at a fixed epoch, which can't tell whether replay detection
    // survives an epoch advance. nullifier = Poseidon(holder_secret,
    // scope) (credential-protocol.md Section 7) deliberately excludes epoch,
    // since currentEpoch advances system-wide on *any* holder's issuance
    // or revocation - a formula that included it would let a holder
    // simply wait for the next such event and present again. This proof
    // is a real, independently-generated proof for Alice at epoch 6
    // (same holder_secret, same scope, same validSetRoot - her own leaf
    // never moved, only the global epoch counter did), confirming her
    // nullifier is stable across an epoch change and the replay is still
    // caught.
    function test_SamePresentationAtLaterEpochStillReverts() public {
        policy.presentEligibility(offeringA, pA, pB, pC, publicSignals);

        // Simulate an unrelated holder's issuance/revocation elsewhere
        // advancing currentEpoch to 6 - Alice's own root is unaffected,
        // so republishing the identical root bytes is the correct
        // simulation, not a stand-in for an unrelated one.
        vm.prank(issuer);
        registry.publishValidSetRoot(bytes32(publicSignals[3]));

        uint256[2] memory epoch6PA = [
            0x24246794ded5c754d50df14437a2737e58f5b0bc39adffe2b5f12534dba56735,
            0x05f88d097efcce93fb9fc5902b61d213628ee3daa436cf27d1211db5c7d96719
        ];
        uint256[2][2] memory epoch6PB = [
            [
                0x1dc3c7c8dc715b34db2c02453827e4c44a4b1ff5a79de9756a94c7850a4da228,
                0x067f51ca192d98e70ede1906845a14c02ef42010a64227818714352e796041a6
            ],
            [
                0x26a8afb3310f096a2fa4c509158f3ab83f1221d45a50785d77a5652ce195522b,
                0x2d7afd9beb6f02ff551be217749884448675d9531e11a219fcf16f5a3fbb0cd8
            ]
        ];
        uint256[2] memory epoch6PC = [
            0x123005ebdf5aadbb02071de8955396632f4f0343699d6350515b73bca143968a,
            0x23500f79ab0dd05897fa33b3401d177fbf1110c93cdcdc3962bcd0bc6e37a388
        ];
        uint256[6] memory epoch6PublicSignals = [
            0x08d54883e989bc5094454a9625a15d0abe3b96de641f26cec85f3eef7bef8bab,
            0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,
            0x019bd66abc02866ee9621d2377848d93a98a7f17f1fcc7ec337ece1e5368a21a,
            0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2,
            0x0000000000000000000000000000000000000000000000000000000000000006,
            0x0000000000000000000000000000000000000000000000000000000000000000
        ];
        // Same nullifier as epoch 5's proof (publicSignals[0] above) -
        // confirmed identical off-chain when both were generated.
        assertEq(epoch6PublicSignals[0], publicSignals[0]);

        vm.expectRevert("nullifier already used");
        policy.presentEligibility(offeringA, epoch6PA, epoch6PB, epoch6PC, epoch6PublicSignals);
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
