const path = require("path");
const assert = require("assert");
const wasm_tester = require("circom_tester").wasm;
const { buildFixtures } = require("./fixtures");

const CREDENTIAL_DIR = path.join(__dirname, "..");

// Phase 2 addendum (F2.8): closes the gap where the issuer recomputing
// attr_hash alone doesn't confirm the submitted leaf was built from it -
// credential-protocol.md §4.3.
describe("leaf_binding.circom", function () {
    this.timeout(60000);

    let fixtures;
    let circuit;

    before(async () => {
        fixtures = await buildFixtures();
        circuit = await wasm_tester(path.join(CREDENTIAL_DIR, "leaf_binding.circom"));
    });

    it("Alice's real leaf, correctly bound to her real attr_hash: witness exists", async () => {
        const attrHash = fixtures.attrHashOf(fixtures.ALICE.attrs);
        const w = await circuit.calculateWitness({
            holder_secret: fixtures.ALICE.holder_secret,
            attr_hash: attrHash,
            leaf: fixtures.ALICE.leaf,
        });
        await circuit.checkConstraints(w);
    });

    it("fabricated attr_hash (different attributes than what was verified): calculateWitness throws", async () => {
        // Alice's real leaf was built from her real attrs; claiming it
        // corresponds to Bob's attr_hash instead is exactly the attack
        // this circuit exists to catch.
        const bobAttrHash = fixtures.attrHashOf(fixtures.BOB.attrs);
        await assert.rejects(() =>
            circuit.calculateWitness({
                holder_secret: fixtures.ALICE.holder_secret,
                attr_hash: bobAttrHash,
                leaf: fixtures.ALICE.leaf,
            })
        );
    });

    it("fabricated leaf (doesn't match holder_secret + attr_hash): calculateWitness throws", async () => {
        const attrHash = fixtures.attrHashOf(fixtures.ALICE.attrs);
        await assert.rejects(() =>
            circuit.calculateWitness({
                holder_secret: fixtures.ALICE.holder_secret,
                attr_hash: attrHash,
                leaf: fixtures.ALICE.leaf + 1n,
            })
        );
    });

    it("wrong holder_secret with an otherwise-real attr_hash/leaf pair: calculateWitness throws", async () => {
        const attrHash = fixtures.attrHashOf(fixtures.ALICE.attrs);
        await assert.rejects(() =>
            circuit.calculateWitness({
                holder_secret: fixtures.ALICE.holder_secret + 1n,
                attr_hash: attrHash,
                leaf: fixtures.ALICE.leaf,
            })
        );
    });
});
