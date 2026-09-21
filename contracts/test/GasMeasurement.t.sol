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
            0x01aa0d5e3eb31d98301bbb5d2f3bfc541505129323d0fc72516c2fc41721d22d,
            0x1f626a70b821ceb5b538b3a9801c1aef00fa8ebbc6a1b73b53dd155343751a68
        ];
        uint256[2][2] memory pB = [
            [
                0x288fab1827b6491117aeef897501e3fd55551bb882ad957b5cc2ebe73379cec2,
                0x2e03f2e8372831f84d9961cd871959436380bed70116efdf5ff500d2ca58bc24
            ],
            [
                0x017e3b16ba4849b7f42304169f04d04fa90ba7ebee1963e91b1f131f3bff569a,
                0x138460b219b1810354b2e9157475a58b84c311aa85e895197db6827cb67b6f26
            ]
        ];
        uint256[2] memory pC = [
            0x03c5f64b8739c29ee2e4a49ac5e1e1d2a02f426e9b85f6bc29d2d2d05f7c96fe,
            0x17b47a0bdbf3784cb8cd63f3956860d77b19065e2109bb4cdea158b2c9eb7a4f
        ];
        uint256[4] memory publicSignals = [
            0x1286f39bcb5e397777332dbfa971c100c51f94b406ab03e48509a11b6a259100,
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
            0x0d4a7b40125b571b5cdd583372511b2ec470ddc69efe24a5f23347dc8b4ac4b8,
            0x12abf7e8ae45d5959a2e0f4bd620f249cbedef72e39da31166c592525a528065
        ];
        uint256[2][2] memory pB = [
            [
                0x13d3c0e09af2d3efb8c5bc05562f64e66ae071d771349884a5e5664a2e85a255,
                0x05eeb64ef3629cb40de3a4b534c32f4e5cf833627b0542afff0d7a48bcac5b3e
            ],
            [
                0x0ffae68005b48a108c039d41361b177c6a154ecd6cef8a783a08b9d01037ced8,
                0x11340ae8afa2918028058d4f8caf68f82615bf835c0e067d1541ff944ee28709
            ]
        ];
        uint256[2] memory pC = [
            0x16a3a36d14b1712ac567546763ff8ded633746ef313ce92c9345821b2502d7c8,
            0x16e318acce3af9170a6c1d64a05e47d001963ff63db20266e5e17dde2958af2c
        ];
        uint256[4] memory publicSignals = [
            0x1286f39bcb5e397777332dbfa971c100c51f94b406ab03e48509a11b6a259100,
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
    }
}
