// Generates a real EdDSA-Poseidon (Baby Jubjub) keypair and signature,
// matching circuits/eddsa-baseline/circuit.circom, and writes input.json.
const path = require("path");
const fs = require("fs");
const circomlibjs = require(path.join(__dirname, "../node_modules/circomlibjs"));

async function main() {
  const eddsa = await circomlibjs.buildEddsa();
  const F = eddsa.F;
  const Buffer = require("buffer").Buffer;

  const privKey = Buffer.from(
    "0001020304050607080900010203040506070809000102030405060708090a",
    "hex"
  );
  const pubKey = eddsa.prv2pub(privKey);

  const msg = F.e(12345);
  const signature = eddsa.signPoseidon(privKey, msg);

  const input = {
    Ax: F.toObject(pubKey[0]).toString(),
    Ay: F.toObject(pubKey[1]).toString(),
    S: signature.S.toString(),
    R8x: F.toObject(signature.R8[0]).toString(),
    R8y: F.toObject(signature.R8[1]).toString(),
    M: F.toObject(msg).toString(),
  };

  fs.writeFileSync(
    path.join(__dirname, "input.json"),
    JSON.stringify(input, null, 2)
  );
  console.log("wrote input.json");
  console.log(input);
}

main();
