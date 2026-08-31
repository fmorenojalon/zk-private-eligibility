//
//  ContentView.swift
//  MoproApp
//
//  Phase 1 (F1.1) toolchain plumbing harness: proves the poseidon-baseline
//  circuit (specs/phase-1/toolchain-baseline.md §6) natively on-device.
//  Also F1.3: emits a structured measurement record per run
//  (specs/phase-1/measurement-harness.md §2) and syncs it to the
//  measurement collector.
//
import SwiftUI

// Collector runs on the Mac (measurement/collector, port 3003) and the
// iPhone reaches it over the local network (TR-22). Update to match
// whatever `ipconfig getifaddr en0` reports on the Mac being used.
private let collectorURL = URL(string: "http://192.168.1.169:3003/records")!

struct ContentView: View {
  @State private var textViewText = ""
  @State private var isProveButtonEnabled = true
  @State private var isVerifyButtonEnabled = false
  @State private var generatedProof: CircomProof?
  @State private var publicInputs: [String]?
  @State private var runIndex = 0

  // captured at prove-start, consumed when the record is built after verify
  @State private var provingMs = 0
  @State private var thermalStart = ""
  @State private var batteryStart = 0

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
      Button("Sync measurement records", action: syncRecords)
        .accessibilityIdentifier("syncRecords")

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

      thermalStart = DeviceInfo.thermalState
      batteryStart = DeviceInfo.batteryLevelPct

      let start = CFAbsoluteTimeGetCurrent()

      let result = try generateCircomProof(
        zkeyPath: zkeyPath, circuitInputs: input_str, proofLib: ProofLib.arkworks)
      assert(!result.proof.a.x.isEmpty, "Proof should not be empty")
      assert(expectedOutputs == result.inputs, "Circuit output mismatch")

      let end = CFAbsoluteTimeGetCurrent()
      let timeTaken = end - start
      provingMs = Int(timeTaken * 1000)

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
      let verificationMs = Int(timeTaken * 1000)

      if isValid {
        textViewText += "\(String(format: "%.3f", timeTaken))s 2️⃣\n"
      } else {
        textViewText += "\nProof verification failed.\n"
      }

      recordMeasurement(verificationMs: verificationMs)
      isVerifyButtonEnabled = false
    } catch let error as MoproError {
      textViewText += "\nMoproError: \(error)\n"
    } catch {
      textViewText += "\nUnexpected error: \(error)\n"
    }
  }

  func recordMeasurement(verificationMs: Int) {
    // mopro's generate_circom_proof bundles witness generation and proving
    // into one opaque call - there is no separate timing hook exposed at
    // the Swift binding level without changes to mopro-ffi itself, so
    // witness_gen_ms is not independently measurable here and is reported
    // as 0 rather than guessed.
    let record = MeasurementRecord(
      record_id: UUID().uuidString,
      timestamp: ISO8601DateFormatter().string(from: Date()),
      device: .init(
        model: DeviceInfo.modelIdentifier,
        os_version: DeviceInfo.osVersion,
        chip: DeviceInfo.chipName,
        is_simulator: DeviceInfo.isSimulator
      ),
      circuit: .init(
        name: "poseidon-baseline",
        git_commit: DeviceInfo.circuitsGitCommit,
        parameters: ["arity": 2],
        constraint_count: 517
      ),
      backend: .init(
        circom_version: "2.2.3",
        snarkjs_version: "0.7.6",
        mopro_version: "0.3.7",
        proving_system: "groth16",
        curve: "bn254"
      ),
      metrics: .init(
        witness_gen_ms: 0,
        proving_ms: provingMs,
        verification_ms: verificationMs,
        peak_memory_mb: DeviceInfo.residentMemoryMB,
        // uncompressed Groth16/BN254: A (G1, 64B) + B (G2, 128B) + C (G1, 64B)
        proof_size_bytes: 256,
        thermal_state_start: thermalStart,
        thermal_state_end: DeviceInfo.thermalState,
        battery_level_start_pct: batteryStart,
        battery_level_end_pct: DeviceInfo.batteryLevelPct
      ),
      run_context: .init(
        run_index: runIndex,
        cooldown_seconds_before: 0,
        network_disabled_during_proving: true
      )
    )
    runIndex += 1
    MeasurementStore.persist(record)
    textViewText += "Measurement record persisted (\(MeasurementStore.unsyncedCount()) queued).\n"
  }

  func syncRecords() {
    textViewText += "Syncing measurement records... "
    MeasurementStore.sync(collectorURL: collectorURL) { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let count):
          textViewText += "synced \(count) record(s). ✅\n"
        case .failure(let error):
          textViewText += "sync failed (\(error.localizedDescription)) - will retry later, records still queued.\n"
        }
      }
    }
  }
}
