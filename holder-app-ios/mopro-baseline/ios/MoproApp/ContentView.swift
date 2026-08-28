//
//  ContentView.swift
//  MoproApp
//
//  Phase 1 (F1.1) toolchain plumbing harness: proves the poseidon-baseline
//  circuit (specs/phase-1/toolchain-baseline.md §6) natively on-device.
//
import SwiftUI

struct ContentView: View {
  @State private var textViewText = ""
  @State private var isProveButtonEnabled = true
  @State private var isVerifyButtonEnabled = false
  @State private var generatedProof: CircomProof?
  @State private var publicInputs: [String]?
  private let zkeyPath = Bundle.main.path(forResource: "poseidonbaseline_final", ofType: "zkey")!

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "globe")
        .imageScale(.large)
        .foregroundStyle(.tint)
      Button("Prove poseidon-baseline", action: runProveAction).disabled(!isProveButtonEnabled)
        .accessibilityIdentifier("proveCircom")
      Button("Verify poseidon-baseline", action: runVerifyAction).disabled(!isVerifyButtonEnabled)
        .accessibilityIdentifier("verifyCircom")

      ScrollView {
        Text(textViewText)
          .padding()
          .accessibilityIdentifier("proof_log")
      }
      .frame(height: 200)
    }
    .padding()
  }
}

extension ContentView {
  func runProveAction() {
    textViewText += "Generating poseidon-baseline proof... "
    do {
      // Poseidon(1, 2) - matches circuits/poseidon-baseline/input.json
      let input_str: String = "{\"in\": [\"1\", \"2\"]}"

      // Expected output: the canonical circomlib Poseidon(1,2) test vector
      let expectedOutputs: [String] = [
        "7853200120776062878684798364095072458815029376092732009249414926327459813530"
      ]

      let start = CFAbsoluteTimeGetCurrent()

      let result = try generateCircomProof(
        zkeyPath: zkeyPath, circuitInputs: input_str, proofLib: ProofLib.arkworks)
      assert(!result.proof.a.x.isEmpty, "Proof should not be empty")
      assert(expectedOutputs == result.inputs, "Circuit output mismatch")

      let end = CFAbsoluteTimeGetCurrent()
      let timeTaken = end - start

      generatedProof = result.proof
      publicInputs = result.inputs

      textViewText += "\(String(format: "%.3f", timeTaken))s 1️⃣\n"
      isVerifyButtonEnabled = true
    } catch {
      textViewText += "\nProof generation failed: \(error.localizedDescription)\n"
    }
  }

  func runVerifyAction() {
    guard let proof = generatedProof,
      let inputs = publicInputs
    else {
      textViewText += "Proof has not been generated yet.\n"
      return
    }

    textViewText += "Verifying poseidon-baseline proof... "
    do {
      let start = CFAbsoluteTimeGetCurrent()

      let isValid = try verifyCircomProof(
        zkeyPath: zkeyPath, proofResult: CircomProofResult(proof: proof, inputs: inputs),
        proofLib: ProofLib.arkworks)

      let end = CFAbsoluteTimeGetCurrent()
      let timeTaken = end - start

      if isValid {
        textViewText += "\(String(format: "%.3f", timeTaken))s 2️⃣\n"
      } else {
        textViewText += "\nProof verification failed.\n"
      }
      isVerifyButtonEnabled = false
    } catch let error as MoproError {
      textViewText += "\nMoproError: \(error)\n"
    } catch {
      textViewText += "\nUnexpected error: \(error)\n"
    }
  }
}
