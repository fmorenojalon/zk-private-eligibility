//
//  MeasurementRecord.swift
//  MoproApp
//
//  F1.3: structured measurement records per
//  specs/phase-1/measurement-harness.md §2, persisted locally first and
//  synced to the collector afterward (§3) so a transient network gap or a
//  sleeping collector can't lose a run.
//
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct MeasurementRecord: Codable {
  struct Device: Codable {
    let model: String
    let os_version: String
    let chip: String
    let is_simulator: Bool
  }
  struct Circuit: Codable {
    let name: String
    let git_commit: String
    let parameters: [String: Int]
    let constraint_count: Int
  }
  struct Backend: Codable {
    let circom_version: String
    let snarkjs_version: String
    let mopro_version: String
    let proving_system: String
    let curve: String
  }
  struct Metrics: Codable {
    let witness_gen_ms: Int
    let proving_ms: Int
    let verification_ms: Int
    let peak_memory_mb: Int
    let proof_size_bytes: Int
    let thermal_state_start: String
    let thermal_state_end: String
    let battery_level_start_pct: Int
    let battery_level_end_pct: Int
  }
  struct RunContext: Codable {
    let run_index: Int
    let cooldown_seconds_before: Int
    let network_disabled_during_proving: Bool
  }

  let record_id: String
  let timestamp: String
  let device: Device
  let circuit: Circuit
  let backend: Backend
  let metrics: Metrics
  let run_context: RunContext
}

enum DeviceInfo {
  // circuits/ git commit at the time this app was built against the bundled
  // zkey. Not yet wired to an Xcode build-phase script that stamps it
  // automatically on every build - update manually when the circuit changes.
  static let circuitsGitCommit = "c5f3e30b781de44d1bc37154e5422800b3f07630"

  static var isSimulator: Bool {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
  }

  static var modelIdentifier: String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    return machineMirror.children.reduce("") { identifier, element in
      guard let value = element.value as? Int8, value != 0 else { return identifier }
      return identifier + String(UnicodeScalar(UInt8(value)))
    }
  }

  // Small, honest lookup for the devices this project actually targets
  // (TR-21/TR-22: iPhone 14 Pro + MacBook Pro 2024) rather than a general
  // chip-identification library - there is no public iOS API that maps a
  // hardware identifier to a marketing chip name.
  static var chipName: String {
    switch modelIdentifier {
    case "iPhone15,2", "iPhone15,3": return "A16 Bionic"
    default: return "unknown (\(modelIdentifier))"
    }
  }

  static var osVersion: String {
    #if canImport(UIKit)
    return UIDevice.current.systemVersion
    #else
    return ProcessInfo.processInfo.operatingSystemVersionString
    #endif
  }

  static var thermalState: String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  static var batteryLevelPct: Int {
    #if canImport(UIKit)
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    return level < 0 ? -1 : Int(level * 100)
    #else
    return -1
    #endif
  }

  // Resident memory via the Mach task_info API - the standard way to read
  // a process's own memory footprint on iOS; there is no simpler public API.
  static var residentMemoryMB: Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Int(info.resident_size / (1024 * 1024))
  }
}

enum MeasurementStore {
  private static var fileURL: URL {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return dir.appendingPathComponent("measurement_records.ndjson")
  }

  // Persist immediately (§3) - called before any network attempt.
  static func persist(_ record: MeasurementRecord) {
    guard let data = try? JSONEncoder().encode(record),
      let line = String(data: data, encoding: .utf8)
    else { return }
    let entry = line + "\n"
    if let handle = try? FileHandle(forWritingTo: fileURL) {
      handle.seekToEndOfFile()
      handle.write(entry.data(using: .utf8)!)
      handle.closeFile()
    } else {
      try? entry.write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  static func unsyncedCount() -> Int {
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
    return content.split(separator: "\n").count
  }

  // Sync-then-truncate: only clears the local queue once the collector has
  // acknowledged receipt, so a failed/unreachable sync leaves records queued
  // for the next attempt rather than losing them.
  static func sync(collectorURL: URL, completion: @escaping (Result<Int, Error>) -> Void) {
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty else {
      completion(.success(0))
      return
    }
    let lines = content.split(separator: "\n").map(String.init)
    let jsonArray = "[" + lines.joined(separator: ",") + "]"

    var request = URLRequest(url: collectorURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonArray.data(using: .utf8)
    request.timeoutInterval = 10

    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        completion(.failure(NSError(domain: "collector", code: -1)))
        return
      }
      try? "".write(to: fileURL, atomically: true, encoding: .utf8)
      completion(.success(lines.count))
    }.resume()
  }
}
