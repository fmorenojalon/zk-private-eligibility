pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/poseidon.circom";

// Phase 1 baseline primitive (F1.4) and F1.1 toolchain plumbing circuit.
// Arity 2: matches leaf = Poseidon(holder_secret, attr_hash) from
// specs/phase-1/protocol-spec.md §4.2.
template PoseidonBaseline() {
    signal input in[2];
    signal output out;

    component hasher = Poseidon(2);
    hasher.inputs[0] <== in[0];
    hasher.inputs[1] <== in[1];
    out <== hasher.out;
}

component main = PoseidonBaseline();
