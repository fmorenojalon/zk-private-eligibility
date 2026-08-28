import uniffi.mopro_baseline.*

try {
    var zkeyPath = "./test-vectors/circom/poseidonbaseline_final.zkey"

    val input_str: String = "{\"in\":[\"1\",\"2\"]}"

    // Generate proof
    var generateProofResult = generateCircomProof(zkeyPath, input_str, ProofLib.ARKWORKS)

    // Verify proof
    var isValid = verifyCircomProof(zkeyPath, generateProofResult, ProofLib.ARKWORKS)
    assert(isValid) { "Proof is invalid" }

    assert(generateProofResult.proof.a.x.isNotEmpty()) { "Proof is empty" }
    assert(generateProofResult.inputs.size > 0) { "Inputs are empty" }


} catch (e: Exception) {
    println(e)
    throw e
}
