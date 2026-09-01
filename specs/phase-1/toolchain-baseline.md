# Phase 1 — Toolchain & Baseline Circuits Specification

**Satisfies:** F1.1, F1.2, F1.4
**Status:** Draft for review — no implementation exists yet.

---

## 1. Objective

Prove the full toolchain works end-to-end on real hardware, and establish baseline constraint/timing costs for the four cryptographic primitives the protocol depends on, before Phase 2 builds the actual credential circuit on top of them.

---

## 2. Pinned Toolchain Versions

Recorded here for reproducibility (TR-19); every measurement record also carries these versions per-run (see [measurement-harness.md](measurement-harness.md)).

| Tool | Version | Source |
| --- | --- | --- |
| circom | v2.2.3 | [iden3/circom](https://github.com/iden3/circom) releases |
| snarkjs | v0.7.6 | [iden3/snarkjs](https://github.com/iden3/snarkjs) releases |
| circomlib | commit `35e54ea21da3e8762557234298dbb553c175ea8d` (master) | no tagged releases exist; pinned by commit |
| Foundry (forge, anvil, cast) | v1.7.1 | [foundry-rs/foundry](https://github.com/foundry-rs/foundry) releases |
| Node.js | v22 LTS (22.23.2) | nodejs.org |
| mopro-cli | v0.3.7 | [zkmopro/mopro](https://github.com/zkmopro/mopro) releases |
| Xcode | 26.3 | newest release supporting macOS 15.6 (Sequoia) — the App Store currently defaults to 26.4+, which requires macOS 26.2 (Tahoe); installed directly from developer.apple.com instead |
| Rust/cargo | stable ≥ 1.85 (1.98.0 installed) | mopro-cli's dependency tree requires the `edition2024` Cargo feature (stabilized in 1.85); circom itself only needs any recent stable toolchain |

**Re-pin policy:** if a pinned tool receives a breaking release mid-phase, the spec is updated first (per the project's spec-before-implementation rule), not silently upgraded in code.

---

## 3. Repository Layout

Flat top-level packages, sibling directories:

```
zk-poc/
├── specs/                 (existing)
├── circuits/               circom sources: baseline primitives (Phase 1) + credential/predicate circuits (Phase 2)
├── contracts/               Foundry project: Groth16Verifier (generated), EligibilityRegistry, NullifierRegistry, OfferingPolicy
├── issuer-service/          Node/TS HTTP API (Phase 3)
├── platform-backend/        Node/TS HTTP API (Phase 3/4)
├── platform-frontend/       React + Vite (Phase 4)
├── holder-app-ios/          SwiftUI app — Phase 1 gets a minimal proving harness here; the full holder app (credential storage, consent UI, QR) is Phase 4
└── measurement/             collector service, on-device record schema, analysis scripts
```

Phase 1 touches `circuits/`, `contracts/` (verifier + test harness only), `holder-app-ios/` (minimal harness), and `measurement/`.

---

## 4. Trusted Setup (TR-5)

**Source:** Hermez/Polygon zkEVM perpetual Powers-of-Tau ceremony.

- Base URL: `https://storage.googleapis.com/zkevm/ptau/`
- Naming: `powersOfTau28_hez_final_{power}.ptau` (e.g. `_12.ptau` supports up to ~4k constraints, `_14.ptau` up to ~16k, `_16.ptau` up to ~64k, `_20.ptau` up to ~1M)
- **Selection rule:** for each circuit, pick the smallest `power` such that `2^power ≥` the circuit's constraint count (from `circom --r1cs` output), then run `snarkjs groth16 setup` (circuit-specific Phase 2 ceremony) on top of that file.
- **Recorded per baseline circuit:** chosen `power`, ptau file size, ptau download time, circuit-specific setup time, resulting `.zkey` size — all part of the F1.4 deliverable.

---

## 5. Baseline Primitive Circuits (F1.4)

Four standalone circuits, no credential logic — pure primitive measurement:

| Circuit | Parameters tested | Purpose |
| --- | --- | --- |
| `poseidon-baseline` | arity 2, arity 10 | matches the two Poseidon arities used in the credential commitment ([protocol-spec.md §4.2](protocol-spec.md#42-commitment-structure)) |
| `merkle-baseline` | depth ∈ {16, 20, 32} | matches TR-6's complexity dial; reused directly for P5/P6/P8 in Phase 2 |
| `range-baseline` | single comparator over a 64-bit value | matches the income/net-worth/portfolio field sizes used in P1/P2/P9 |
| `eddsa-baseline` | single EdDSA-Poseidon signature verification | standalone reference number per F1.4 — **not** used in the Phase 2 credential circuit per [protocol-spec.md §3](protocol-spec.md#3-issuer-attestation-membership-only-design-decision), but still required baseline data |

**Per circuit, per parameter set, recorded:**
- Constraint count (`circom --r1cs`)
- Witness generation time (desktop)
- Proving time — desktop **and** iPhone 14 Pro native (TR-7: simulator runs are invalid and excluded)
- Verification time (desktop, snarkjs)
- Proof size
- Trusted setup artifact size (ptau + zkey)

All values go through the measurement harness ([measurement-harness.md](measurement-harness.md)) as structured records, not ad-hoc notes.

**Status: satisfied (desktop for all four; on-device for one).** All four circuits are built, set up, and proven/verified across their full parameter sets — full results, methodology, and reproduction steps in [circuits/BASELINE_RESULTS.md](../../circuits/BASELINE_RESULTS.md). `poseidon-baseline` additionally has real, repeated, device-tagged records via F1.3's now-implemented harness — the other three circuits haven't been wired through mopro on-device yet, so their desktop numbers are still the only data point. Re-baselining the remaining three on real hardware is expected per PRD R5.

---

## 6. iOS Native Proving Plumbing (F1.1)

**Requirement:** "A circom circuit SHALL prove on the iPhone 14 Pro natively."

**Circuit used:** the `poseidon-baseline` (arity 2) circuit — the simplest available, chosen specifically to exercise the *full* toolchain path early (mitigates R2: Phase 4 integration risk, by front-loading the same pipeline with a trivial circuit now).

**Path exercised end-to-end:**

1. circom source → R1CS + WASM witness generator (circom)
2. Trusted setup → proving/verification keys (snarkjs, §4)
3. mopro-cli generates Swift bindings wrapping the native (non-WASM) Groth16 prover
4. Minimal SwiftUI harness app (`holder-app-ios/`, Phase 1 scope only — not the full holder app) invokes the binding, generates a proof **on physical device**
5. Proof + public signals exported off-device (via the measurement collector's sync path, or directly for verification testing)
6. Proof verified against the generated Solidity verifier on Anvil (§7)

**Hard constraint (TR-7):** proofs generated in the iOS Simulator do not count as valid measurements or satisfy F1.1 — must run on the physical iPhone 14 Pro.

**Status: satisfied.** `holder-app-ios/mopro-baseline` wraps the `poseidon-baseline` circuit via mopro, builds and signs against a free personal-team Apple Developer account, and its `MoproAppUITests.testCircomProveVerify` test — which launches the app on the paired iPhone 14 Pro, taps "Prove", and asserts the proof completes — passed running natively on-device (`xcodebuild test -destination "id=<device UDID>"`, physical device confirmed via `devicectl`/`xctrace`, not the Simulator). Toolchain and device setup steps, including several non-obvious build/signing issues encountered getting here, are recorded in [TOOLCHAIN.md §9](../../TOOLCHAIN.md#9-building-an-f11-style-mopro-app-for-a-physical-device-gotchas) for reproducibility (TR-19). Rationale for why this stack (mopro/native bindings) is needed at all is in [TOOLCHAIN.md §7](../../TOOLCHAIN.md#7-why-mopro-rationale-for-the-native-binding-stack).

**No network during proving (TR-8):** the harness app must not require network access while the proof is being generated; the device may go on Wi-Fi only afterward to sync measurement records ([measurement-harness.md §4](measurement-harness.md#4-emission--export-path)).

---

## 7. On-Chain Verification Flow (F1.2)

**Requirement:** "A generated verifier SHALL verify a real proof on the local chain, and reject a tampered one."

**Steps:**

1. `snarkjs zkey export solidityverifier` → `Groth16Verifier.sol` for the `poseidon-baseline` circuit (same circuit as §6, so F1.1 and F1.2 exercise the identical artifact).
2. Deploy `Groth16Verifier.sol` to Anvil via a Foundry script.
3. Foundry test suite:
   a. **Genuine proof:** submit a real proof + correct public inputs generated from §6 → assert the verifier returns `true`.
   b. **Tampered proof:** flip one byte of the proof (`a`, `b`, or `c` component) → assert the verifier returns `false`/reverts.
   c. **Tampered public input:** mutate one public signal while keeping the proof unchanged → assert the verifier returns `false`/reverts.

This is the acceptance test for F1.2 directly — no additional interpretation needed at Phase 1 review.

**Status: satisfied.** `contracts/` (Foundry project) holds the generated `Groth16Verifier.sol`. `forge test` passes all three cases against Foundry's in-memory EVM, using a real proof/public-signal fixture from `circuits/poseidon-baseline/{proof,public}.json`. Independently confirmed against an actual running Anvil process (`anvil --port 8545`, matching the PRD §9.1 Local chain service) via `forge create` + `cast call verifyProof(...)`: the genuine proof returns `true`, a tampered public input returns `false` — not a revert, since the generated verifier's assembly checks the pairing precompile's success flag and returns a bool rather than propagating a raw failure. See `contracts/README.md` for exact reproduction commands.

---

## 8. Acceptance Mapping

| Requirement | Satisfied by |
| --- | --- |
| F1.1 | §6 — proof generated on physical iPhone 14 Pro |
| F1.2 | §7 — genuine proof accepted, tampered proof/inputs rejected on Anvil |
| F1.4 | §5 — four baseline circuits measured across their parameter sets |
| D0 deliverable | §5 + §6 + §7 combined, plus [protocol-spec.md](protocol-spec.md) (F1.5) and [measurement-harness.md](measurement-harness.md) (F1.3) |
