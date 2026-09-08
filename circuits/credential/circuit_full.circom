pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/gates.circom";
include "../merkle-baseline/template.circom";
include "range_predicates.circom";
include "threshold.circom";
include "indexed_nonmembership.circom";

// Phase 2 (F2.1-F2.4, complexity-dial maximum). The full EU 2-of-2 regime:
// P1-P4 threshold composition, P5/P6 (jurisdiction/sanctions membership),
// plus the always-structural P7/P8/P10 - eligibility-circuits.md §5.
// P5/P6 are unconditional here, not optional-if-supplied: jurisdictionRoot
// and sanctionsRoot are always public inputs to this circuit, matching
// "included whenever jurisdictionRoot/sanctionsRoot are supplied as
// public inputs - always, in circuit_full.circom" (§5).
template CircuitFull(depth) {
    signal input income;
    signal input portfolio_value;
    signal input financial_sector_months;
    signal input executive_months;
    signal input jurisdiction_code;
    signal input identity_commitment;
    signal input issued_epoch;
    signal input expiry_epoch;
    signal input schema_version;

    signal input holder_secret;

    // P5: jurisdiction membership. Leaf is jurisdiction_code itself - an
    // allowlist of small ISO 3166-1 numeric codes needs no further
    // hashing before being a tree leaf.
    signal input jurisdictionPathElements[depth];
    signal input jurisdictionPathIndices[depth];
    signal input jurisdictionRoot;

    // P6: sanctions non-membership (credential-protocol.md §5.3). The
    // low-leaf triple bracketing identity_commitment, found off-circuit,
    // plus its own Merkle path - separate from P5/P8's paths, since it's
    // a different tree.
    signal input sanctionsValue;
    signal input sanctionsNextValue;
    signal input sanctionsNextIndex;
    signal input sanctionsPathElements[depth];
    signal input sanctionsPathIndices[depth];
    signal input sanctionsRoot;

    // P8: valid-set membership (revocation check).
    signal input validSetPathElements[depth];
    signal input validSetPathIndices[depth];
    signal input validSetRoot;

    signal input currentEpoch;
    signal input scope;

    signal output nullifier;

    // F2.1: attr_hash = Poseidon(9 attributes), leaf = Poseidon(holder_secret,
    // attr_hash) - credential-protocol.md §4.2.
    component attrHash = Poseidon(9);
    attrHash.inputs[0] <== income;
    attrHash.inputs[1] <== portfolio_value;
    attrHash.inputs[2] <== financial_sector_months;
    attrHash.inputs[3] <== executive_months;
    attrHash.inputs[4] <== jurisdiction_code;
    attrHash.inputs[5] <== identity_commitment;
    attrHash.inputs[6] <== issued_epoch;
    attrHash.inputs[7] <== expiry_epoch;
    attrHash.inputs[8] <== schema_version;

    component leafHash = Poseidon(2);
    leafHash.inputs[0] <== holder_secret;
    leafHash.inputs[1] <== attrHash.out;

    // condA = P1 v P2.
    component p1 = RangeGte(64);
    p1.value <== income;
    p1.threshold <== 60000;

    component p2 = RangeGt(64);
    p2.value <== portfolio_value;
    p2.threshold <== 100000;

    component condA = OR();
    condA.a <== p1.out;
    condA.b <== p2.out;

    // condB = P3.
    component p3a = RangeGte(64);
    p3a.value <== financial_sector_months;
    p3a.threshold <== 12;

    component p3b = RangeGte(64);
    p3b.value <== executive_months;
    p3b.threshold <== 12;

    component condB = OR();
    condB.a <== p3a.out;
    condB.b <== p3b.out;

    // P4: 2-of-2.
    component p4 = ThresholdOfN(2, 2);
    p4.conditions[0] <== condA.out;
    p4.conditions[1] <== condB.out;
    p4.out === 1;

    // P5: jurisdiction in the allowed set.
    component p5 = MerkleBaseline(depth);
    p5.leaf <== jurisdiction_code;
    for (var i = 0; i < depth; i++) {
        p5.pathElements[i] <== jurisdictionPathElements[i];
        p5.pathIndices[i] <== jurisdictionPathIndices[i];
    }
    p5.root <== jurisdictionRoot;
    p5.valid === 1;

    // P6: identity_commitment absent from the sanctions set.
    component p6 = IndexedNonMembership(depth);
    p6.identityCommitment <== identity_commitment;
    p6.value <== sanctionsValue;
    p6.nextValue <== sanctionsNextValue;
    p6.nextIndex <== sanctionsNextIndex;
    for (var i = 0; i < depth; i++) {
        p6.pathElements[i] <== sanctionsPathElements[i];
        p6.pathIndices[i] <== sanctionsPathIndices[i];
    }
    p6.sanctionsRoot <== sanctionsRoot;
    p6.out === 1;

    // P7: credential not expired.
    component p7 = RangeGte(64);
    p7.value <== expiry_epoch;
    p7.threshold <== currentEpoch;
    p7.out === 1;

    // P8: credential not revoked.
    component p8 = MerkleBaseline(depth);
    p8.leaf <== leafHash.out;
    for (var i = 0; i < depth; i++) {
        p8.pathElements[i] <== validSetPathElements[i];
        p8.pathIndices[i] <== validSetPathIndices[i];
    }
    p8.root <== validSetRoot;
    p8.valid === 1;

    // P10: scope-bound nullifier.
    component nullifierHash = Poseidon(3);
    nullifierHash.inputs[0] <== holder_secret;
    nullifierHash.inputs[1] <== currentEpoch;
    nullifierHash.inputs[2] <== scope;
    nullifier <== nullifierHash.out;
}

component main {public [jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope]} = CircuitFull(20);
