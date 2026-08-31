pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/eddsaposeidon.circom";

// Phase 1 baseline primitive (F1.4): EdDSA-over-Baby-Jubjub signature
// verification, Poseidon-based per TR-2/TR-3. Standalone reference cost -
// per protocol-spec.md §3 the Phase 2 credential circuit does NOT verify
// an issuer signature in-circuit (tree membership is the attestation), so
// this number characterizes the primitive but is not part of that
// circuit's constraint count.
template EdDSABaseline() {
    signal input Ax;
    signal input Ay;
    signal input S;
    signal input R8x;
    signal input R8y;
    signal input M;

    component verifier = EdDSAPoseidonVerifier();
    verifier.enabled <== 1;
    verifier.Ax <== Ax;
    verifier.Ay <== Ay;
    verifier.S <== S;
    verifier.R8x <== R8x;
    verifier.R8y <== R8y;
    verifier.M <== M;
}

component main {public [Ax, Ay, M]} = EdDSABaseline();
