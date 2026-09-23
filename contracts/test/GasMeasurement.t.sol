// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EligibilityRegistry} from "../src/EligibilityRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {OfferingPolicy} from "../src/OfferingPolicy.sol";
import {Groth16VerifierP1Only} from "../src/verifiers/Groth16VerifierP1Only.sol";
import {Groth16VerifierCondAB} from "../src/verifiers/Groth16VerifierCondAB.sol";
import {Groth16VerifierFull} from "../src/verifiers/Groth16VerifierFull.sol";

// specs/phase-3/verification-infrastructure.md §6 (F3.7). Isolated gas
// measurements, one test per number reported in PHASE3_RESULTS.md - kept
// separate from the correctness test suites so `forge test --gas-report`
// output for this file maps directly onto that table, uncluttered by
// unrelated test functions' gas.
contract GasMeasurementTest is Test {
    address internal issuer = address(0xE55);
    address internal platform = address(0xF1A7);

    // circuit_p1only: [nullifier, currentEpoch, validSetRoot, scope]
    function test_Gas_BareVerifyProof_P1Only() public {
        Groth16VerifierP1Only verifier = new Groth16VerifierP1Only();
        uint256[2] memory pA = [
            0x027a13b88ea2621fb6dfee875fc621e46f9d83766fca744d1ea79d7a269a5bca,
            0x0d7c8fcadc2721ea2d57929406a9f99dfd808d53e91fdac62a152c85a1038b62
        ];
        uint256[2][2] memory pB = [
            [
                0x25b3af8aa5c28f9bda85d930cd88ab4d9ec9ca00d0913850bc57643f62508011,
                0x1491aea2843974ee6e7803a3aafcbeb66fa55aa6cb6624dbcb2ccfd6c92c14e0
            ],
            [
                0x28ad9678f8f73bd6613f6c965fa44f9116768998c577aee7ec8cfe422069cb8f,
                0x14a4d84d73cf2d0104239882be5c37017c4b1a683d89e9f82d31d6c48ade4105
            ]
        ];
        uint256[2] memory pC = [
            0x285e76bf43c6b4708f53962d25961ac939499cda35098ac86ba2592820e3b616,
            0x2e0cc4da1424d02e2504f830e14bcde5fd6cb3c5d70d9d143a6be6980b88881a
        ];
        uint256[4] memory publicSignals = [
            0x08d54883e989bc5094454a9625a15d0abe3b96de641f26cec85f3eef7bef8bab,
            0x0000000000000000000000000000000000000000000000000000000000000005,
            0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2,
            0x0000000000000000000000000000000000000000000000000000000000000000
        ];
        bool ok = verifier.verifyProof(pA, pB, pC, publicSignals);
        assertTrue(ok);
    }

    // circuit_condab: same 4-signal shape as p1only
    function test_Gas_BareVerifyProof_CondAB() public {
        Groth16VerifierCondAB verifier = new Groth16VerifierCondAB();
        uint256[2] memory pA = [
            0x10126f77125a50f5976185086dd174e001dcb2fe6af15f6eecbdd55d0c863cf1,
            0x01524f84d3bc480c790e238a846bd06575b6a459b27f1f1f33b9183fd5105494
        ];
        uint256[2][2] memory pB = [
            [
                0x1cfca24717bbe84785fca0e83dfc4390e5c332c02f66553c07e56ec277f95aa1,
                0x0a4d322dd6bb6eb9056c2363abb3d120074cf64f55011f118bea89be37da17a2
            ],
            [
                0x1a12cb0faf8feb4029e42951c1f25af8dd572e4602bbabde4619b815475f3056,
                0x284b00d6e1d5fd968ccaec4b6dc7d0db5182e36464918f7fab9484c0f2d860ab
            ]
        ];
        uint256[2] memory pC = [
            0x0d7469662467cd82c82a7b32db8788b0841b8a52e06d992e193d28bc611a21ac,
            0x0cd190f6a91e6f192eaf92175e65e2e8ac2ec237068bc9bf07ad460a74392c95
        ];
        uint256[4] memory publicSignals = [
            0x08d54883e989bc5094454a9625a15d0abe3b96de641f26cec85f3eef7bef8bab,
            0x0000000000000000000000000000000000000000000000000000000000000005,
            0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2,
            0x0000000000000000000000000000000000000000000000000000000000000000
        ];
        bool ok = verifier.verifyProof(pA, pB, pC, publicSignals);
        assertTrue(ok);
    }

    // circuit_full: [nullifier, jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope]
    function test_Gas_BareVerifyProof_Full() public {
        Groth16VerifierFull verifier = new Groth16VerifierFull();
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, uint256[6] memory publicSignals) =
            _aliceFullProof();
        bool ok = verifier.verifyProof(pA, pB, pC, publicSignals);
        assertTrue(ok);
    }

    // circuit_full via the full stack: presentEligibility (recorded-value
    // cross-checks + verifyProof + nullifier consumption), same fixture proof.
    function test_Gas_PresentEligibility_Full() public {
        EligibilityRegistry registry;
        vm.prank(issuer);
        registry = new EligibilityRegistry(issuer);
        NullifierRegistry nullifiers = new NullifierRegistry();
        Groth16VerifierFull verifier = new Groth16VerifierFull();
        OfferingPolicy policy = new OfferingPolicy(platform, registry, nullifiers, verifier);
        nullifiers.setAuthorized(address(policy));

        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, uint256[6] memory publicSignals) =
            _aliceFullProof();

        vm.startPrank(issuer);
        registry.approveJurisdictionRoot(bytes32(publicSignals[1]));
        for (uint256 i = 0; i < 5; i++) {
            registry.publishValidSetRoot(i == 4 ? bytes32(publicSignals[3]) : bytes32(uint256(1000 + i)));
        }
        registry.publishSanctionsRoot(bytes32(publicSignals[2]));
        vm.stopPrank();

        vm.prank(platform);
        uint256 offeringId = policy.registerOffering(bytes32(publicSignals[1]));

        bool granted = policy.presentEligibility(offeringId, pA, pB, pC, publicSignals);
        assertTrue(granted);
    }

    function _aliceFullProof()
        internal
        pure
        returns (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, uint256[6] memory publicSignals)
    {
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
    }
}
