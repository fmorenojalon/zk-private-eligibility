pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/poseidon.circom";

// F1.4 baseline: arity 10, matching attr_hash = Poseidon(10 attributes) from
// specs/phase-1/protocol-spec.md §4.2. Companion to circuit.circom (arity 2,
// used for leaf = Poseidon(holder_secret, attr_hash) and for F1.1's on-device
// plumbing test).
template PoseidonBaselineArity10() {
    signal input in[10];
    signal output out;

    component hasher = Poseidon(10);
    for (var i = 0; i < 10; i++) {
        hasher.inputs[i] <== in[i];
    }
    out <== hasher.out;
}

component main = PoseidonBaselineArity10();
