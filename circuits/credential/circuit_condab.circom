pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/gates.circom";
include "../merkle-baseline/template.circom";
include "range_predicates.circom";
include "threshold.circom";

// Phase 2 (F2.1-F2.4, complexity-dial midpoint). Full P1-P4 threshold
// composition, plus the always-structural P7/P8/P10 - but no P5/P6
// (jurisdiction/sanctions membership). Exists specifically to isolate
// P5/P6's constraint cost from P3/P4's once measured
// (eligibility-circuits.md §2's "why three, not two"), not to model any
// real regulatory variant - the EU regime always needs P5/P6 too
// (circuit_full.circom).
template CircuitCondAB(depth) {
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

    signal input pathElements[depth];
    signal input pathIndices[depth];

    signal input currentEpoch;
    signal input validSetRoot;
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

    // condA = P1 v P2 (income >= 60000 OR portfolio_value > 100000).
    component p1 = RangeGte(64);
    p1.value <== income;
    p1.threshold <== 60000;

    component p2 = RangeGt(64);
    p2.value <== portfolio_value;
    p2.threshold <== 100000;

    component condA = OR();
    condA.a <== p1.out;
    condA.b <== p2.out;

    // condB = P3 (>=1yr financial sector OR >=12mo executive, both
    // inclusive - credential-protocol.md §5).
    component p3a = RangeGte(64);
    p3a.value <== financial_sector_months;
    p3a.threshold <== 12;

    component p3b = RangeGte(64);
    p3b.value <== executive_months;
    p3b.threshold <== 12;

    component condB = OR();
    condB.a <== p3a.out;
    condB.b <== p3b.out;

    // P4: >=2 of {condA, condB} - which, at N=2, means both, per the EU
    // 2-of-2 MVP scope (credential-protocol.md §5, §5.2).
    component p4 = ThresholdOfN(2, 2);
    p4.conditions[0] <== condA.out;
    p4.conditions[1] <== condB.out;
    p4.out === 1;

    // P7: credential not expired (expiry_epoch >= currentEpoch, inclusive).
    component p7 = RangeGte(64);
    p7.value <== expiry_epoch;
    p7.threshold <== currentEpoch;
    p7.out === 1;

    // P8: credential not revoked - Merkle inclusion of `leaf` against
    // validSetRoot.
    component p8 = MerkleBaseline(depth);
    p8.leaf <== leafHash.out;
    for (var i = 0; i < depth; i++) {
        p8.pathElements[i] <== pathElements[i];
        p8.pathIndices[i] <== pathIndices[i];
    }
    p8.root <== validSetRoot;
    p8.valid === 1;

    // P10: scope-bound nullifier (credential-protocol.md §7). Always
    // computed as output, never constrained.
    component nullifierHash = Poseidon(3);
    nullifierHash.inputs[0] <== holder_secret;
    nullifierHash.inputs[1] <== currentEpoch;
    nullifierHash.inputs[2] <== scope;
    nullifier <== nullifierHash.out;
}

component main {public [currentEpoch, validSetRoot, scope]} = CircuitCondAB(20);
