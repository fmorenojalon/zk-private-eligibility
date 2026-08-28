import Foundation
import mopro_baseline

do {
    let zkeyPath = "../../../test-vectors/circom/poseidonbaseline_final.zkey"

    // Prepare inputs
    var inputs = [String: [String]]()
    inputs["in"] = ["1", "2"]
    let input_str: String = (try? JSONSerialization.data(withJSONObject: inputs, options: .prettyPrinted)).flatMap {
        String(data: $0, encoding: .utf8)
    } ?? ""

    // Expected output: Poseidon(1, 2), the canonical circomlib test vector
    let outputs: [String] = ["7853200120776062878684798364095072458815029376092732009249414926327459813530"]

    // Generate Proof
    let generateProofResult = try generateCircomProof(
        zkeyPath: zkeyPath, circuitInputs: input_str, proofLib: ProofLib.arkworks)
    assert(!generateProofResult.proof.a.x.isEmpty, "Proof should not be empty")

    // Verify Proof
    assert(
        outputs == generateProofResult.inputs,
        "Circuit outputs mismatch the expected outputs")

    let isValid = try verifyCircomProof(zkeyPath: zkeyPath, proofResult: generateProofResult, proofLib: ProofLib.arkworks)
    assert(isValid, "Proof verification should succeed")

    assert(generateProofResult.proof.a.x.count > 0, "Proof should not be empty")
    assert(generateProofResult.inputs.count > 0, "Inputs should not be empty")

} catch let error as MoproError {
    print("MoproError: \(error)")
    throw error
} catch {
    print("Unexpected error: \(error)")
    throw error
}
