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
//
// secret_hash (added after the nullifier fix, credential-protocol.md §7):
// binds this proof to Poseidon(holder_secret) as a third public output,
// so the issuer service can compare it against whatever secret_hash it
// has on file for this holder's identity_commitment (verification-
// infrastructure.md §4.1/§4.2) - re-issuance with a genuinely different
// holder_secret produces a different secret_hash and is rejected. This
// is a one-way commitment, not the secret itself, and doesn't touch
// PR-5's guarantee (credential-protocol.md §4.1) - holder_secret is a
// high-entropy random field element, and Poseidon isn't invertible, so
// the issuer learning secret_hash gives it no way to recover
// holder_secret.
template LeafBinding() {
    signal input holder_secret;
    signal input attr_hash;
    signal input leaf;
    signal input secret_hash;

    component leafHasher = Poseidon(2);
    leafHasher.inputs[0] <== holder_secret;
    leafHasher.inputs[1] <== attr_hash;
    leafHasher.out === leaf;

    component secretHasher = Poseidon(1);
    secretHasher.inputs[0] <== holder_secret;
    secretHasher.out === secret_hash;
}

component main {public [attr_hash, leaf, secret_hash]} = LeafBinding();
