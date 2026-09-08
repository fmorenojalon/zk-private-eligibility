pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/gates.circom";
include "../merkle-baseline/template.circom";
include "range_predicates.circom";

// Phase 2 (F2.1, F2.2, F2.3 bookend). Condition A only (P1 v P2), plus the
// always-structural P7/P8/P10 - specs/phase-2/eligibility-circuits.md §5.
// The complexity-dial minimum bookend, not a real EU regime configuration -
// the EU regime always needs the full 2-of-2 composition (circuit_full.circom).
//
// Merkle depth fixed at 20 for Phase 2's own functional testing (§2) -
// MerkleBaseline itself (circuits/merkle-baseline/template.circom) remains
// depth-parameterized for Phase 5's sweep.
//
// currentEpoch does double duty as P7's freshness comparison and P10's
// nullifier input - credential-protocol.md §7 states these are the same
// value ("epoch... matches the epoch of validSetRoot used in the same
// proof"), so this is one public input, not two.
template CircuitP1Only(depth) {
    // Credential attributes (credential-protocol.md §4.1) - all nine are
    // declared regardless of which predicates this variant checks, since
    // attr_hash always takes the full set (eligibility-circuits.md §3).
    // Only income, portfolio_value, and expiry_epoch are constrained
    // against a threshold below; the rest exist here solely as attr_hash
    // inputs.
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

    // P8: Merkle inclusion of `leaf` in the valid-set tree.
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

    // condA = P1 v P2 (income >= 60000 OR portfolio_value > 100000,
    // credential-protocol.md §5). Regulatory constants are compile-time
    // literals, not inputs - a threshold change is a new circuit version
    // (new schema_version, new trusted setup), the same tradeoff TR-5
    // already accepts for any circuit change.
    component p1 = RangeGte(64);
    p1.value <== income;
    p1.threshold <== 60000;

    component p2 = RangeGt(64);
    p2.value <== portfolio_value;
    p2.threshold <== 100000;

    component condA = OR();
    condA.a <== p1.out;
    condA.b <== p2.out;
    condA.out === 1;

    // P7: credential not expired (expiry_epoch >= currentEpoch, inclusive).
    component p7 = RangeGte(64);
    p7.value <== expiry_epoch;
    p7.threshold <== currentEpoch;
    p7.out === 1;

    // P8: credential not revoked - Merkle inclusion of `leaf` against
    // validSetRoot. Reuses circuits/merkle-baseline's MerkleBaseline
    // template as-is (eligibility-circuits.md §4).
    component p8 = MerkleBaseline(depth);
    p8.leaf <== leafHash.out;
    for (var i = 0; i < depth; i++) {
        p8.pathElements[i] <== pathElements[i];
        p8.pathIndices[i] <== pathIndices[i];
    }
    p8.root <== validSetRoot;
    p8.valid === 1;

    // P10: scope-bound nullifier (credential-protocol.md §7). Always
    // computed as output, never constrained - PR-4's all-or-nothing
    // property comes from the predicates above, not this.
    component nullifierHash = Poseidon(3);
    nullifierHash.inputs[0] <== holder_secret;
    nullifierHash.inputs[1] <== currentEpoch;
    nullifierHash.inputs[2] <== scope;
    nullifier <== nullifierHash.out;
}

component main {public [currentEpoch, validSetRoot, scope]} = CircuitP1Only(20);
