const circomlibjs = require("circomlibjs");

const DEPTH = 20;
const SCHEMA_VERSION = 1n;

// Sparse Merkle tree over a fixed depth, defaulting every unset leaf to
// `emptyLeaf` (0n) - the standard "zero-hash" construction, so we never
// have to materialize 2^depth leaves to get a valid root/path for the
// handful of real ones under test (credential-protocol.md §6's
// valid-set tree, at Phase 2's fixed test depth - eligibility-circuits.md
// §2).
class SparseMerkleTree {
    constructor(depth, hash2, emptyLeaf = 0n) {
        this.depth = depth;
        this.hash2 = hash2;
        this.zeroHashes = [emptyLeaf];
        for (let i = 0; i < depth; i++) {
            this.zeroHashes.push(hash2(this.zeroHashes[i], this.zeroHashes[i]));
        }
        this.leaves = new Map();
    }

    setLeaf(index, value) {
        this.leaves.set(index, value);
    }

    _computeLevels() {
        const levels = [new Map(this.leaves)];
        for (let level = 0; level < this.depth; level++) {
            const cur = levels[level];
            const next = new Map();
            const parents = new Set();
            for (const idx of cur.keys()) parents.add(idx >> 1);
            for (const parentIdx of parents) {
                const leftIdx = parentIdx * 2;
                const rightIdx = parentIdx * 2 + 1;
                const left = cur.has(leftIdx) ? cur.get(leftIdx) : this.zeroHashes[level];
                const right = cur.has(rightIdx) ? cur.get(rightIdx) : this.zeroHashes[level];
                next.set(parentIdx, this.hash2(left, right));
            }
            levels.push(next);
        }
        this._levels = levels;
    }

    root() {
        this._computeLevels();
        return this._levels[this.depth].has(0)
            ? this._levels[this.depth].get(0)
            : this.zeroHashes[this.depth];
    }

    // pathIndices[i] = 0 means the leaf/node is the LEFT child at level i,
    // 1 means RIGHT - matches circuits/merkle-baseline/template.circom's
    // DualMux convention exactly.
    proof(index) {
        this._computeLevels();
        const pathElements = [];
        const pathIndices = [];
        let idx = index;
        for (let level = 0; level < this.depth; level++) {
            const siblingIdx = idx ^ 1;
            const cur = this._levels[level];
            const siblingVal = cur.has(siblingIdx) ? cur.get(siblingIdx) : this.zeroHashes[level];
            pathElements.push(siblingVal);
            pathIndices.push(idx % 2);
            idx = idx >> 1;
        }
        return { pathElements, pathIndices };
    }
}

async function buildFixtures() {
    const poseidon = await circomlibjs.buildPoseidon();
    const F = poseidon.F;
    const toObj = (x) => F.toObject(x);

    const hash2 = (a, b) => toObj(poseidon([a, b]));
    const hash3 = (a, b, c) => toObj(poseidon([a, b, c]));
    const hash9 = (arr) => toObj(poseidon(arr));

    // attr_hash = Poseidon(9 attributes), leaf = Poseidon(holder_secret,
    // attr_hash) - credential-protocol.md §4.2. Attribute order matches
    // circuit_p1only.circom's attrHash.inputs[0..8] wiring exactly.
    function attrHashOf(a) {
        return hash9([
            a.income,
            a.portfolio_value,
            a.financial_sector_months,
            a.executive_months,
            a.jurisdiction_code,
            a.identity_commitment,
            a.issued_epoch,
            a.expiry_epoch,
            a.schema_version,
        ]);
    }

    function leafOf(holderSecret, attrs) {
        return hash2(holderSecret, attrHashOf(attrs));
    }

    const CURRENT_EPOCH = 5n;
    const SCOPE = hash2(111n, 0n); // stand-in Poseidon(offering_id) - credential-protocol.md §7

    const ALICE = {
        holder_secret: 123456789n,
        attrs: {
            income: 70000n,
            portfolio_value: 150000n,
            financial_sector_months: 24n,
            executive_months: 0n,
            jurisdiction_code: 724n, // ISO 3166-1 numeric, Spain - placeholder
            identity_commitment: hash2(999n, 1n), // not a real sanctions-tree member
            issued_epoch: 1n,
            expiry_epoch: 10n, // > CURRENT_EPOCH
            schema_version: SCHEMA_VERSION,
        },
    };

    const BOB = {
        holder_secret: 987654321n,
        attrs: {
            income: 30000n,
            portfolio_value: 50000n,
            financial_sector_months: 3n,
            executive_months: 0n,
            jurisdiction_code: 724n,
            identity_commitment: hash2(999n, 2n),
            issued_epoch: 1n,
            expiry_epoch: 10n,
            schema_version: SCHEMA_VERSION,
        },
    };

    ALICE.leaf = leafOf(ALICE.holder_secret, ALICE.attrs);
    BOB.leaf = leafOf(BOB.holder_secret, BOB.attrs);

    // Both real leaves live in the same tree, at different indices, so
    // Bob's rejection cases fail for the intended reason (condA) rather
    // than incidentally failing P8 with a mismatched path.
    const validSetTree = new SparseMerkleTree(DEPTH, hash2);
    validSetTree.setLeaf(0, ALICE.leaf);
    validSetTree.setLeaf(1, BOB.leaf);

    ALICE.merkleIndex = 0;
    BOB.merkleIndex = 1;
    ALICE.merkleProof = validSetTree.proof(ALICE.merkleIndex);
    BOB.merkleProof = validSetTree.proof(BOB.merkleIndex);

    const VALID_SET_ROOT = validSetTree.root();

    // Jurisdiction allowlist: a plain Merkle tree whose leaves are the
    // allowed ISO 3166-1 numeric codes directly - no further hashing
    // needed for a single small integer (credential-protocol.md §5, P5).
    const ALLOWED_JURISDICTIONS = [724n, 276n, 372n]; // Spain, Germany, Ireland - placeholders
    const jurisdictionTree = new SparseMerkleTree(DEPTH, hash2);
    ALLOWED_JURISDICTIONS.forEach((code, idx) => jurisdictionTree.setLeaf(idx, code));
    const JURISDICTION_ROOT = jurisdictionTree.root();

    const jurisdictionIndexOf = (code) => ALLOWED_JURISDICTIONS.indexOf(code);
    ALICE.jurisdictionProof = jurisdictionTree.proof(jurisdictionIndexOf(ALICE.attrs.jurisdiction_code));
    BOB.jurisdictionProof = jurisdictionTree.proof(jurisdictionIndexOf(BOB.attrs.jurisdiction_code));

    // Sanctions list: indexed Merkle tree with embedded next-pointers,
    // per credential-protocol.md §5.3 / eligibility-circuits.md §7's
    // "Sanctions list fixture" - 10 real entries plus the two implicit
    // bounds (a value=0 leaf below the smallest entry, and the largest
    // entry's own nextValue left at p-1 rather than pointing elsewhere).
    // No dynamic insertion logic - built once, directly, as the spec
    // describes.
    const FIELD_MAX = F.p - 1n;
    const sortedSanctionedValues = Array.from({ length: 10 }, (_, i) =>
        hash2(777n, BigInt(i))
    ).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

    function buildIndexedTree(depth, values) {
        // leaves[0] is the value=0 sentinel; leaves[1..N] are the real
        // entries, each linking to the next via nextIndex; the last real
        // entry's nextValue is FIELD_MAX (no further insertion happened
        // above it).
        const leaves = [{ value: 0n, nextValue: values[0], nextIndex: 1 }];
        for (let i = 0; i < values.length; i++) {
            const isLast = i === values.length - 1;
            leaves.push({
                value: values[i],
                nextValue: isLast ? FIELD_MAX : values[i + 1],
                nextIndex: isLast ? i + 1 : i + 2,
            });
        }

        const tree = new SparseMerkleTree(depth, hash2);
        leaves.forEach((l, idx) => {
            tree.setLeaf(idx, hash3(l.value, l.nextValue, l.nextIndex));
        });

        return { leaves, tree, root: tree.root() };
    }

    // The one leaf whose (value, nextValue) range brackets `target` -
    // the low-leaf lookup a holder does off-circuit (credential-protocol.md
    // §5.3: "found off-circuit by the holder; the circuit only checks
    // the relation holds").
    function findLowLeafIndex(leaves, target) {
        const idx = leaves.findIndex((l) => l.value < target && target < l.nextValue);
        if (idx === -1) throw new Error("no bracketing leaf for target - it's a member, or out of range");
        return idx;
    }

    const sanctions = buildIndexedTree(DEPTH, sortedSanctionedValues);
    const SANCTIONS_ROOT = sanctions.root;

    function sanctionsProofFor(identityCommitment) {
        const leafIndex = findLowLeafIndex(sanctions.leaves, identityCommitment);
        const leaf = sanctions.leaves[leafIndex];
        return {
            identityCommitment,
            value: leaf.value,
            nextValue: leaf.nextValue,
            nextIndex: BigInt(leaf.nextIndex),
            ...sanctions.tree.proof(leafIndex),
        };
    }

    ALICE.sanctionsProof = sanctionsProofFor(ALICE.attrs.identity_commitment);
    BOB.sanctionsProof = sanctionsProofFor(BOB.attrs.identity_commitment);

    return {
        DEPTH,
        CURRENT_EPOCH,
        SCOPE,
        VALID_SET_ROOT,
        JURISDICTION_ROOT,
        ALLOWED_JURISDICTIONS,
        ALICE,
        BOB,
        hash2,
        hash3,
        hash9,
        attrHashOf,
        leafOf,
        SparseMerkleTree,
        FIELD_MAX,
        SANCTIONS_ROOT,
        sortedSanctionedValues,
        sanctions,
        sanctionsProofFor,
    };
}

module.exports = { buildFixtures, SparseMerkleTree, DEPTH };
