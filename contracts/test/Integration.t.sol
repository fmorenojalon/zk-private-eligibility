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
            0x1ea2297bb145da2c150b49237b782f9dd3775af2fa8d8d1bcf3936393835e11e,
            0x30355218c7356879250395d7619ea3529f0348ed8d7cef91420d62d49e2b2281
        ];
        pB = [
            [
                0x05aadf4ae017b5a751248e5d8f0e046c8a3d5717d79e807a69d91790818b14d4,
                0x238a2e36252e0da1070d1bbf3a9e9a5a1d66fcbf4e385f0b796e34d4f976e1a2
            ],
            [
                0x04b51142a343ddc219611e43f703f3980884b70227504db7877d498c5c94f773,
                0x0263200cf53d8fa9ba21be7dcd01bfb113559fe170f28cb8774695ec2cd85bd7
            ]
        ];
        pC = [
            0x01df1e61a87819d2399a4e80d204ad2aa2296345a4cee7af93045758eaff510a,
            0x17e03702ad1e5938a3743decd95f969ed660d199c9732a9aebce11d0f16f2c06
        ];
        publicSignals = [
            0x08d54883e989bc5094454a9625a15d0abe3b96de641f26cec85f3eef7bef8bab,
            0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,
            0x0b9fa49e73ac3e867872fcbe504c1a93652e83a030af877ec38d2fd7a9b51af3,
            0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2,
            0x0000000000000000000000000000000000000000000000000000000000000005,
            0x0000000000000000000000000000000000000000000000000000000000000000
        ];

        pA_b = [
            0x0debaaf4c432e677d8a2447caca801a5df40d82e3929cd4539520f7ca8f35387,
            0x1165525c7cc933d485aaf6702ed49dcd22309e45b7638c73f83e43c31e3594c7
        ];
        pB_b = [
            [
                0x070be661e0df16ae68691d5ac69bad8e0e0f54376c5af139fdd9aa18df9eabb1,
                0x224cf06cc082fd7e8c812bf0a35e37d96020c45b654e61e7764c6fcfe447ece8
            ],
            [
                0x219a2cbfbc0ec3ac780a9c95a5295cfcbcf804a14fe7b1b8a9982f1e50ea8909,
                0x2ffd9c4922a50263a718f6bf4b1c6aedfeb9bdaf96325cfb9435f82721d0a58e
            ]
        ];
        pC_b = [
            0x1eb825d1588d17c9d9d8942dad2cbe3380813a2d332a27a1591cc9843e6f80c7,
            0x01f86656a0266e1fb14a594ce66fadbe9299a02460a6a780c16ee5b4d3c8edff
        ];
        publicSignals_b = [
            0x15ff5f37f52326d1cea0983b154fecf00c2344e850a4620f5cdc58eb804e606c,
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
