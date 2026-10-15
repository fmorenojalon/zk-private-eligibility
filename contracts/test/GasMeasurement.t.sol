// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EligibilityRegistry} from "../src/EligibilityRegistry.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";
import {OfferingPolicy} from "../src/OfferingPolicy.sol";
import {Groth16VerifierP1Only} from "../src/verifiers/Groth16VerifierP1Only.sol";
import {Groth16VerifierCondAB} from "../src/verifiers/Groth16VerifierCondAB.sol";
import {Groth16VerifierFull} from "../src/verifiers/Groth16VerifierFull.sol";

// specs/phase-3/verification-infrastructure.md Section 6 (F3.7). Isolated gas
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
    }
}
