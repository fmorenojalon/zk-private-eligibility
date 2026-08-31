// Builds a test Merkle tree of the given depth using Poseidon(2), matching
// circuits/merkle-baseline/template.circom, and writes input.json for a
// membership proof of leaf index 0.
const path = require("path");
const fs = require("fs");
const circomlibjs = require(path.join(__dirname, "../node_modules/circomlibjs"));

async function main() {
  const depth = parseInt(process.argv[2], 10);
  const poseidon = await circomlibjs.buildPoseidon();
  const F = poseidon.F;

  const hash2 = (a, b) => F.toObject(poseidon([a, b]));

  // leaf 0 is our proof subject; siblings are arbitrary distinct values
  let leaf = 12345n;
  let current = leaf;
  const pathElements = [];
  const pathIndices = [];

  for (let i = 0; i < depth; i++) {
    const sibling = BigInt(1000000 + i);
    // alternate left/right just to exercise both mux branches
    const isRight = i % 2 === 1 ? 1 : 0;
    pathElements.push(sibling.toString());
    pathIndices.push(isRight);
    current = isRight ? hash2(sibling, current) : hash2(current, sibling);
  }

  const input = {
    leaf: leaf.toString(),
    pathElements,
    pathIndices,
    root: current.toString(),
  };

  fs.writeFileSync(
    path.join(__dirname, `input_${depth}.json`),
    JSON.stringify(input, null, 2)
  );
  console.log(`wrote input_${depth}.json, root=${current.toString()}`);
}

main();
