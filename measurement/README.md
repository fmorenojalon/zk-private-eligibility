# Measurement Harness

F1.3 (TR-16–TR-19). See [specs/phase-1/measurement-harness.md](../specs/phase-1/measurement-harness.md) for the full design.

## Reproducing a clean run

1. **Start the collector** (Mac):
   ```sh
   cd measurement/collector
   node server.js
   ```
   Listens on `:3003` on all interfaces (not just localhost) so the iPhone can reach it over the local network (TR-22).

2. **Find the Mac's local IP** and make sure it matches `collectorURL` in `holder-app-ios/mopro-baseline/ios/MoproApp/ContentView.swift`:
   ```sh
   ipconfig getifaddr en0
   ```
   Update and rebuild the app if the Mac's IP has changed (DHCP leases aren't permanent).

3. **Build and run the app on the physical iPhone** (TR-7 — simulator runs are invalid):
   ```sh
   cd holder-app-ios/mopro-baseline/ios
   xcodebuild test -project MoproApp.xcodeproj -scheme MoproApp \
     -destination "id=<device UDID from xcrun xctrace list devices>" \
     -allowProvisioningUpdates \
     -only-testing:MoproAppUITests/MoproAppUITests/testCircomProveVerify
   ```
   This launches the app, taps Prove → Verify → Sync automatically, and asserts the sync completed — see [TOOLCHAIN.md §9](../TOOLCHAIN.md#9-building-an-f11-style-mopro-app-for-a-physical-device-gotchas) for the underlying build/signing/permission setup this depends on.

   **First run on a fresh device/install:** iOS will prompt for Local Network permission the first time the app tries to reach the collector. If a UI test's interruption monitor doesn't catch that system alert in time, the permission gets recorded as denied and iOS won't ask again — check Settings → Privacy & Security → Local Network → MoproApp and toggle it on manually if sync keeps timing out with no error on either side.

4. **Records accumulate on-device until synced** — the app persists every record locally first (`MeasurementStore.persist`) and only clears its local queue once the collector acknowledges receipt (`MeasurementStore.sync`). If the collector was unreachable for a while (as happened during this project's own local-network-permission debugging - see git history), the next successful sync flushes everything that queued up, not just the latest run.

5. **Analyze** (run from the repo root — `measurement/analyze/analyze.py` is a relative path, so if your shell is `cd`'d somewhere else, e.g. into an `.xcresult` bundle after inspecting test logs, the shell won't find the script and reports a confusing "No such file or directory" nested inside that unrelated path):
   ```sh
   cd /path/to/repo-root   # wherever you cloned this - the local folder name need not match the repo name
   python3 measurement/analyze/analyze.py
   ```
   Reads `measurement/records/records.ndjson`, groups by `(circuit, parameters, device)`, and writes `measurement/reports/summary.{md,csv}`.

## Files

- `collector/server.js` — plain Node HTTP service, no dependencies. `POST /records` (idempotent on `record_id`), `GET /health`.
- `records/records.ndjson` — one JSON record per line, append-only. Committed to the repo as real collected data, not gitignored — small, human-readable, and part of the reproducible result set (TR-19).
- `analyze/analyze.py` — stdlib-only (no pandas dependency, despite the original spec draft's mention of it — wasn't worth adding a Python dependency for this data volume).
- `reports/` — generated output, regenerate anytime with `analyze.py`.
