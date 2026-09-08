pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/poseidon.circom";

// Phase 2 addendum (F2.8, PR-23, TR-23). Closes a soundness gap found
// during design review: the issuer computes attr_hash directly from its
// own records and sends it to the holder (Flow 1, credential-protocol.md
// §4.2) - that only confirms what attr_hash IS, not whether the `leaf`
// the holder hands back was built from it, since
// leaf = Poseidon(holder_secret, attr_hash) and the issuer never learns
// holder_secret (PR-5). A dishonest holder could receive one attr_hash
// from the issuer, then commit a leaf built from a different, fabricated
// one, undetected.
//
// This circuit is the fix: proof of knowledge of holder_secret such that
// Poseidon(holder_secret, attr_hash) = leaf, for attr_hash and leaf as
// PUBLIC inputs fixed to the issuer's own attested value and the
// commitment being submitted. The issuer verifies this once per
// issuance, off-chain (F3.3 - issuance is local HTTP, not on-chain), and
// only inserts the leaf if it holds. holder_secret never appears as
// anything but a private input - the issuer's view is unchanged from
// before this fix, it just gains one more check to run.
//
// Identical in shape to circuits/poseidon-baseline's arity-2 circuit
// (credential-protocol.md §4.3) - no new cryptographic construction,
// just an equality constraint against a public leaf instead of a free
// output.
template LeafBinding() {
    signal input holder_secret;
    signal input attr_hash;
    signal input leaf;

    component hasher = Poseidon(2);
    hasher.inputs[0] <== holder_secret;
    hasher.inputs[1] <== attr_hash;
    hasher.out === leaf;
}

component main {public [attr_hash, leaf]} = LeafBinding();
