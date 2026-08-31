pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

// Phase 1 baseline primitive (F1.4). Binary Merkle inclusion proof,
// parameterized by depth per TR-6. Reused directly for P5/P6/P8 in
// Phase 2 (jurisdiction/sanctions/valid-set membership,
// specs/phase-1/protocol-spec.md §5).
//
// pathIndices[i] = 0 means the current node is the LEFT child at level i,
// 1 means it is the RIGHT child. Explicitly constrained to be boolean -
// circomlib's Mux1 alone does not enforce this, and an unconstrained
// selector would let a malicious prover pick a non-boolean value to
// bypass the intended path semantics.
template DualMux() {
    signal input in[2];
    signal input s;
    signal output out[2];

    s * (1 - s) === 0;

    out[0] <== (in[1] - in[0]) * s + in[0];
    out[1] <== (in[0] - in[1]) * s + in[1];
}

template MerkleBaseline(depth) {
    signal input leaf;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    signal input root;
    signal output valid;

    component mux[depth];
    component hashers[depth];
    signal levels[depth + 1];
    levels[0] <== leaf;

    for (var i = 0; i < depth; i++) {
        mux[i] = DualMux();
        mux[i].in[0] <== levels[i];
        mux[i].in[1] <== pathElements[i];
        mux[i].s <== pathIndices[i];

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== mux[i].out[0];
        hashers[i].inputs[1] <== mux[i].out[1];
        levels[i + 1] <== hashers[i].out;
    }

    component eq = IsEqual();
    eq.in[0] <== levels[depth];
    eq.in[1] <== root;
    valid <== eq.out;
}
