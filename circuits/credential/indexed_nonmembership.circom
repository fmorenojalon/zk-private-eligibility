pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/gates.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";
include "../merkle-baseline/template.circom";

// Phase 2 (F2.2, P6). Indexed Merkle tree non-membership -
// credential-protocol.md §5.3. Each leaf commits to a sorted linked-list
// triple (value, nextValue, nextIndex); non-membership of
// identityCommitment is proven by exhibiting the one leaf whose range
// (value, nextValue) brackets it, plus a Merkle inclusion proof of that
// leaf's hash. Adjacency is enforced by the tree root itself - nextValue
// is part of the leaf's hashed content, not a side assumption trusted
// separately - replacing an earlier, unsound two-independent-leaves
// design (credential-protocol.md §5.3's own note on that correction).
//
// 252-bit comparators, not 64 like range_predicates.circom's RangeGte/
// RangeGt: value/nextValue/identityCommitment are full Poseidon field
// elements (up to ~254 bits), not small integers like income/portfolio.
// circomlib's LessThan asserts n <= 252 - the safe maximum below the
// field's top, avoiding modular-wraparound ambiguity near p.
template IndexedNonMembership(depth) {
    signal input identityCommitment;
    signal input value;
    signal input nextValue;
    signal input nextIndex;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    signal input sanctionsRoot;
    signal output out;

    // value < identityCommitment < nextValue (strict both sides).
    component lowBound = LessThan(252);
    lowBound.in[0] <== value;
    lowBound.in[1] <== identityCommitment;

    component highBound = LessThan(252);
    highBound.in[0] <== identityCommitment;
    highBound.in[1] <== nextValue;

    // Leaf content is the triple itself - this is what makes adjacency
    // structural rather than trusted.
    component leafHash = Poseidon(3);
    leafHash.inputs[0] <== value;
    leafHash.inputs[1] <== nextValue;
    leafHash.inputs[2] <== nextIndex;

    component inclusion = MerkleBaseline(depth);
    inclusion.leaf <== leafHash.out;
    for (var i = 0; i < depth; i++) {
        inclusion.pathElements[i] <== pathElements[i];
        inclusion.pathIndices[i] <== pathIndices[i];
    }
    inclusion.root <== sanctionsRoot;

    // out = 1 iff both bounds hold AND the bracketing leaf is genuinely
    // in the tree - the caller decides whether to force this to 1,
    // matching range_predicates.circom's RangeGte/RangeGt convention
    // rather than self-enforcing here.
    component and1 = AND();
    and1.a <== lowBound.out;
    and1.b <== highBound.out;

    component and2 = AND();
    and2.a <== and1.out;
    and2.b <== inclusion.valid;

    out <== and2.out;
}
