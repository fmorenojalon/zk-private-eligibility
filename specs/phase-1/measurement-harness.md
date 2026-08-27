# Phase 1 — Measurement Harness Specification

**Satisfies:** F1.3, TR-16 through TR-19
**Status:** Draft for review — no implementation exists yet.

---

## 1. Objective

Every measured run — baseline primitive today, full credential circuit from Phase 2 onward — emits one structured record capturing device, circuit configuration, backend versions, and all metrics, reproducibly, without silently losing data if the Mac-side collector is briefly unreachable.

---

## 2. Structured Record Schema

One JSON object per run. Device-agnostic by design (TR-17): the `device` object's shape stays generic so a later platform (Android, out of scope for MVP but not architecturally precluded) needs no schema rework.

```json
{
  "record_id": "uuid-v4",
  "timestamp": "2026-08-25T14:03:11Z",
  "device": {
    "model": "iPhone14,2",
    "os_version": "18.x",
    "chip": "A16 Bionic",
    "is_simulator": false
  },
  "circuit": {
    "name": "poseidon-baseline",
    "git_commit": "<repo commit hash of circuits/ at build time>",
    "parameters": { "arity": 10 },
    "constraint_count": 0
  },
  "backend": {
    "circom_version": "2.2.3",
    "snarkjs_version": "0.7.6",
    "mopro_version": "0.3.7",
    "proving_system": "groth16",
    "curve": "bn254"
  },
  "metrics": {
    "witness_gen_ms": 0,
    "proving_ms": 0,
    "verification_ms": 0,
    "peak_memory_mb": 0,
    "proof_size_bytes": 0,
    "thermal_state_start": "nominal",
    "thermal_state_end": "nominal",
    "battery_level_start_pct": 0,
    "battery_level_end_pct": 0
  },
  "run_context": {
    "run_index": 0,
    "cooldown_seconds_before": 0,
    "network_disabled_during_proving": true
  }
}
```

Field notes:

- `device.is_simulator` **must** be `false` for a record to count toward F1.1/F1.4 acceptance (TR-7). Simulator-origin records are still stored (useful for early development sanity checks) but tagged and excluded from analysis by default.
- `circuit.parameters` is an open object — shape varies by circuit (`{"arity": N}` for Poseidon, `{"depth": N}` for Merkle, `{"predicate_count": N}` from Phase 2 onward).
- `thermal_state_*` uses iOS `ProcessInfo.thermalState` values: `nominal`, `fair`, `serious`, `critical`.
- `run_context.network_disabled_during_proving` records whether TR-8 held for this specific run — an explicit assertion, not an assumption.

---

## 3. On-Device: Persist, Then Sync

**Design decision:** records are never fire-and-forget. Each record is written to durable on-device storage (local file, append-only NDJSON) **immediately** after the run completes — before any network call is attempted. A background sync process then POSTs unsynced records to the measurement collector (§4) and marks them synced only on acknowledged receipt. If the collector is unreachable, unsynced records simply accumulate on-device until the next successful sync — no run is lost to a transient network gap or a collector that's asleep.

This durability requirement exists specifically so that a multi-hour measurement session (F1.4's full parameter sweep, and later Phase 5's sustained-load runs) can't silently drop data partway through.

---

## 4. Emission & Export Path

- **On-device:** the Phase 1 iOS proving harness ([toolchain-baseline.md §6](toolchain-baseline.md#6-ios-native-proving-plumbing-f11)) writes each record to local NDJSON storage per §3, then attempts sync.
- **Collector service:** a new lightweight HTTP service, `measurement/collector`, on the Mac at port `3003` (added to PRD §9.1). Exposes a single ingest endpoint that accepts a batch of NDJSON records, deduplicates by `record_id`, and appends new ones to `measurement/records/`.
- **Sync timing:** only after proof generation completes — never during proving (TR-8). The device may re-enable network specifically to sync, then proceed with the next run.
- **Idempotency:** because sync can retry, the collector must treat re-delivery of an already-seen `record_id` as a no-op, not a duplicate entry.

---

## 5. Analysis Scripts

`measurement/analyze` — Python (pandas), chosen for this project's data-analysis-shaped output (summary tables, later Phase 5 plots) over the JS/TS stack used elsewhere; a discretionary, low-stakes choice, easy to revisit since it only touches offline analysis, not any live service.

Ingests all records in `measurement/records/`, groups by `(circuit.name, circuit.parameters)`, and computes mean/median/p95/stddev per metric, plus device/backend version breakdowns. Output: Markdown and CSV summary tables under `measurement/reports/`.

---

## 6. Reproducibility (TR-19)

- Every record self-describes its full toolchain version set (`backend` object) — no external "what version were we on" lookup needed to interpret historical data.
- Raw NDJSON records and analysis scripts are checked into the repo (`measurement/records/`, `measurement/analyze/`) — plain text, small, no reason to `.gitignore`.
- A `measurement/README.md` (written during Phase 1 implementation, not part of this spec) documents the exact steps to reproduce a clean run from checkout: build circuits, run setup, deploy collector, run the iOS harness, run analysis.

---

## 7. Thermal & Cooldown Handling (TR-18)

Phase 1 does not perform sustained-load characterization itself (that's Phase 5, F5.2), but the harness must be built to support it from the start:

- Each record captures `thermal_state` at both the start and end of the run, so a transition (e.g. `nominal` → `fair`) during a single proof is visible.
- The harness supports running `N` back-to-back proofs with a configurable cooldown between them (`run_context.cooldown_seconds_before`), so Phase 5 can characterize thermal behavior under sustained load without harness changes — only a configuration change.

---

## 8. Acceptance Mapping

| Requirement | Satisfied by |
| --- | --- |
| TR-16 (structured record, all metrics) | §2 |
| TR-17 (device-agnostic schema) | §2 (`device` object design) |
| TR-18 (cooldown + thermal transitions) | §7 |
| TR-19 (reproducibility) | §6 |
| F1.3 | §2–§7 combined |
