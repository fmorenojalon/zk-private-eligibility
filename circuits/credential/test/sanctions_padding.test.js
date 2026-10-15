const path = require("path");
const assert = require("assert");
const wasm_tester = require("circom_tester").wasm;
const { buildFixtures, SANCTIONS_PADDING } = require("./fixtures");

const CREDENTIAL_DIR = path.join(__dirname, "..");

// Sanctions-tree padding (credential-protocol.md §5.3).
//
// IndexedNonMembership compares field elements with 252-bit comparators, which
// are only correct when the two compared values are within 2^252 of each other
// (the field is ~2^253.6). Without padding, a small or unlucky sanctions list
// leaves gaps wider than that, and honest non-members can no longer prove.
// The issuer therefore seeds the tree with SANCTIONS_PADDING (k * 2^251,
// k = 1..6) so no gap can reach 2^252, whatever the real list looks like.
//
// This suite runs the real circuit against empty, 1-entry, 3-entry and large
// lists, hundreds of honest holders each, and tries every leaf as the claimed
// bracket for sanctioned identities.
describe("sanctions padding (indexed_nonmembership.circom)", function () {
    this.timeout(600000);

    const HOLDERS = 200;
    const GAP_LIMIT = 2n ** 252n;

    let fixtures;
    let circuit;
    let FIELD_P;

    before(async () => {
        fixtures = await buildFixtures();
        FIELD_P = fixtures.FIELD_MAX + 1n;
        circuit = await wasm_tester(path.join(CREDENTIAL_DIR, "indexed_nonmembership.circom"), {
            templateName: "IndexedNonMembership",
            templateParams: [fixtures.DEPTH],
        });
    });

    function inputFor(tree, leafIndex, identityCommitment) {
        const leaf = tree.leaves[leafIndex];
        const proof = tree.tree.proof(leafIndex);
        return {
            identityCommitment,
            value: leaf.value,
            nextValue: leaf.nextValue,
            nextIndex: BigInt(leaf.nextIndex),
            pathElements: proof.pathElements,
            pathIndices: proof.pathIndices,
            sanctionsRoot: tree.root,
        };
    }

    // 1 = accepted, 0 = rejected by the circuit, "fail" = no witness exists.
    async function outcome(input) {
        try {
            const w = await circuit.calculateWitness(input);
            return w[1] === 1n ? 1 : 0;
        } catch (_e) {
            return "fail";
        }
    }

    const randomHolders = () => Array.from({ length: HOLDERS }, (_, i) => fixtures.hash2(4242n, BigInt(i)));
    const realList = (n, seed) => Array.from({ length: n }, (_, i) => fixtures.hash2(seed, BigInt(i)));

    const scenarios = [
        ["empty list", () => []],
        ["1 entry", () => realList(1, 11n)],
        ["3 entries", () => realList(3, 22n)],
        ["large list (60 entries)", () => realList(60, 33n)],
    ];

    for (const [label, makeList] of scenarios) {
        describe(label, () => {
            it("padding keeps every gap between consecutive tree values below 2^252", () => {
                const tree = fixtures.buildIndexedTree(fixtures.DEPTH, makeList());
                for (const leaf of tree.leaves) {
                    assert.ok(leaf.nextValue - leaf.value < GAP_LIMIT, `gap too wide at value ${leaf.value}`);
                }
            });

            it(`all ${HOLDERS} honest non-members are accepted`, async () => {
                const tree = fixtures.buildIndexedTree(fixtures.DEPTH, makeList());
                const results = { 1: 0, 0: 0, fail: 0 };
                for (const id of randomHolders()) {
                    const leafIndex = fixtures.findLowLeafIndex(tree.leaves, id);
                    results[await outcome(inputFor(tree, leafIndex, id))]++;
                }
                assert.deepStrictEqual(results, { 1: HOLDERS, 0: 0, fail: 0 });
            });

            it("a sanctioned identity is never accepted, whichever leaf is claimed as its bracket", async () => {
                // Real list members plus planted ones: small, mid-range and near-top values.
                const real = makeList();
                const planted = [5n, 2n ** 251n + 17n, FIELD_P - 12345n];
                const tree = fixtures.buildIndexedTree(fixtures.DEPTH, [...real, ...planted]);
                const members = [...planted];
                if (real.length) members.push(real[0], real[Math.floor(real.length / 2)], real[real.length - 1]);
                for (const sanctioned of members) {
                    for (let leafIndex = 0; leafIndex < tree.leaves.length; leafIndex++) {
                        const result = await outcome(inputFor(tree, leafIndex, sanctioned));
                        assert.notStrictEqual(result, 1, `sanctioned ${sanctioned} accepted using leaf ${leafIndex}`);
                    }
                }
            });
        });
    }

    it("without padding an empty list locks out honest holders (why the padding exists)", async () => {
        // Characterization of the comparator's range limit: if the circuit is
        // ever made full-width, this test fails and the padding can go.
        const tree = fixtures.buildIndexedTree(fixtures.DEPTH, [], { padding: false });
        let accepted = 0;
        for (const id of randomHolders().slice(0, 40)) {
            const leafIndex = fixtures.findLowLeafIndex(tree.leaves, id);
            if ((await outcome(inputFor(tree, leafIndex, id))) === 1) accepted++;
        }
        assert.strictEqual(accepted, 0);
    });

    it("the padding values are the six multiples of 2^251", () => {
        assert.deepStrictEqual(
            SANCTIONS_PADDING,
            [1n, 2n, 3n, 4n, 5n, 6n].map((k) => k * 2n ** 251n)
        );
    });
});
