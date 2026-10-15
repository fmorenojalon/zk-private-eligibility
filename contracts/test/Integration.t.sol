// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EligibilityRegistry} from "../src/EligibilityRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {OfferingPolicy} from "../src/OfferingPolicy.sol";
import {Groth16VerifierFull} from "../src/verifiers/Groth16VerifierFull.sol";

// specs/phase-3/verification-infrastructure.md Section 7.4. Deploys the entire
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

        pA_b = [
            0x2ba176f17e8cdc5bcf794648822d5b35a10ca3ac5eed2a8150938c0bfd714857,
            0x0604b118e6d9d5e1b8b623f34d12a63a149fbe9fb6621db01a973172982a50fb
        ];
        pB_b = [
            [
                0x12e4816d0dec82f064a2355bc5dc4e7d6dc15ef6176e5958458c5a2a16b46035,
                0x11827c890a2d1c68da1e6ff1796501ae308dd15f133c05f6638dc179a6bc1131
            ],
            [
                0x12e65be57dfb7669f73174a533cbeb198e3e2a796ce030d67aebd1ead06fd3ee,
                0x21eb6a3140a83287dd999c3efe21b311574ded58688a5e8a514dfbedf8725c96
            ]
        ];
        pC_b = [
            0x09162fb1eea4445e60361b16ac2d41455c5aff25fce257b53d3e02b189bf869d,
            0x1fcaeceda23da5ec37e095d22149f42118acf47e74b5a92895d9e1ffa4b84e4c
        ];
        publicSignals_b = [
            0x15ff5f37f52326d1cea0983b154fecf00c2344e850a4620f5cdc58eb804e606c,
            0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,
            0x019bd66abc02866ee9621d2377848d93a98a7f17f1fcc7ec337ece1e5368a21a,
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
        // leaf removal or Poseidon computation happens here (Section 6): currentEpoch
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
