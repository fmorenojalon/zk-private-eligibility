// Generates input_leaf_binding.json for Alice's real (attr_hash, leaf)
// pair - the F2.8 leaf-binding proof's end-to-end validation
// (PHASE2_RESULTS.md).
const fs = require("fs");
const path = require("path");
const { buildFixtures } = require("./test/fixtures");

async function main() {
    const fixtures = await buildFixtures();
    const attrHash = fixtures.attrHashOf(fixtures.ALICE.attrs);
    const input = {
        holder_secret: fixtures.ALICE.holder_secret.toString(),
        attr_hash: attrHash.toString(),
        leaf: fixtures.ALICE.leaf.toString(),
    };
    fs.writeFileSync(path.join(__dirname, "input_leaf_binding.json"), JSON.stringify(input, null, 2));
    console.log("wrote input_leaf_binding.json");
}

main();
