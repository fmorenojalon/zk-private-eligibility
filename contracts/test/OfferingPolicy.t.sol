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
    // scope) (credential-protocol.md §7) deliberately excludes epoch,
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
            0x29a12b187b2b5b29fb2fe262e4a47b9cbc065faed44d062dc8bd71f7d373b56d,
            0x0bae0a9c999cb315dbc0f3409e19143664d8d3da8e2c989b23bd5a4a5c15dfd3
        ];
        uint256[2][2] memory epoch6PB = [
            [
                0x172d278785239b5515a1bbd9d94f7b9359489dbab007feec80480f1fa7c8d95b,
                0x196927bc73bf1aca2d73c018290bbb08ecb06f2e4ee00add211efe78d7b52e09
            ],
            [
                0x1b48b11b18e81f4b0247d4b8a8d28ffd317f145a82aabbffe88ded0b532bda6a,
                0x03c47ff6143e203b7f2d3bc5aa4406520b73c3b948fb8c1a722bfa95f397fe92
            ]
        ];
        uint256[2] memory epoch6PC = [
            0x17a48c8adf0785afe65e87fab89721fdcc067df910101e87e95f22b0dabcf751,
            0x26ce34e2597f2e2203c410bbbc17d226a09e9750bb198b76092041392efa46ed
        ];
        uint256[6] memory epoch6PublicSignals = [
            0x08d54883e989bc5094454a9625a15d0abe3b96de641f26cec85f3eef7bef8bab,
            0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,
            0x0b9fa49e73ac3e867872fcbe504c1a93652e83a030af877ec38d2fd7a9b51af3,
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
