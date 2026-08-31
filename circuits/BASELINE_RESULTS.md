# F1.4 — Baseline Primitive Costs

Satisfies F1.4: "Baseline costs SHALL be established for Poseidon, Merkle inclusion at three depths, range comparison, and EdDSA verification."

**Methodology.** Desktop measurements (MacBook Pro 2024, macOS 15.6.1) using the pinned toolchain (circom 2.2.3, snarkjs 0.7.6, circomlib @ `35e54ea2`) — see [TOOLCHAIN.md](../TOOLCHAIN.md). Each circuit: `circom --r1cs --wasm` for constraint counts, Hermez Powers-of-Tau + `snarkjs groth16 setup` + one dev contribution for the proving/verification keys, then a single witness-generation → proving → verification pass timed with wall-clock `date +%s%N` deltas around each `snarkjs`/`node` invocation. These are **desktop, single-run** numbers. `poseidon-baseline` (arity 2) additionally has real **structured, device-tagged, repeated on-device records** via F1.3's measurement harness (§"On-device" below) — the other three circuits haven't been wired through mopro on-device yet.

## Results

| Circuit | Parameters | Non-linear | Linear | Total constraints | ptau power | witness gen | proving | verify | zkey size |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| poseidon-baseline | arity 2 | 243 | 274 | 517 | 12 | 73 ms | 432 ms | 377 ms | 249 KB |
| poseidon-baseline | arity 10 | 462 | 958 | 1,420 | 12 | 88 ms | 461 ms | 374 ms | 616 KB |
| range-baseline | 64-bit GreaterEqThan | 65 | 4 | 69 | 12 | 60 ms | 417 ms | 375 ms | 40 KB |
| merkle-baseline | depth 16 | 3,938 | 4,385 | 8,323 | 14 | 76 ms | 929 ms | 393 ms | 3.9 MB |
| merkle-baseline | depth 20 | 4,922 | 5,481 | 10,403 | 14 | 65 ms | 875 ms | 383 ms | 4.6 MB |
| merkle-baseline | depth 32 | 7,874 | 8,769 | 16,643 | 16 | 66 ms | 1,181 ms | 386 ms | 7.8 MB |
| eddsa-baseline | EdDSA-Poseidon verify | 7,379 | 707 | 8,086 | 14 | 104 ms | 717 ms | 395 ms | 3.9 MB |

ptau file sizes: power 12 → 4.6 MB, power 14 → 18.1 MB, power 16 → 72.1 MB (downloaded from the Hermez source per [toolchain-baseline.md §4](../specs/phase-1/toolchain-baseline.md#4-trusted-setup)).

### On-device (iPhone 14 Pro, native — F1.3)

Now that the measurement harness exists ([measurement/README.md](../measurement/README.md)), `poseidon-baseline` (arity 2) has real device-tagged records — n=3, via `measurement/analyze/analyze.py`:

| Metric | Mean | Median | p95 |
| --- | --- | --- | --- |
| proving_ms (witness + proof combined) | 34.7 | 36 | 36.0 |
| verification_ms | 12.0 | 12 | 12.9 |
| peak_memory_mb | 106 | 106 | 106.0 |

**Note:** `witness_gen_ms` is 0 in every on-device record — mopro's `generate_circom_proof` bundles witness generation and proving into one opaque FFI call with no separate timing hook exposed to Swift, so the combined time is reported entirely under `proving_ms`. Splitting this would need changes to mopro-ffi itself, out of scope here.

The other three circuits haven't been wired through mopro on-device yet (only `poseidon-baseline` has an iOS harness app built against it, per F1.1).

## Observations

- **Arity 10 costs ~2.7× arity 2 in constraints (1,420 vs 517), not the ~3× a naive per-call model would predict** — consistent with Poseidon's fixed per-permutation overhead (full rounds) being shared across more absorbed inputs at higher arity. This is direct evidence for the [protocol-spec.md §4.2](../specs/phase-1/protocol-spec.md#42-commitment-structure) correction: a single `Poseidon(10)` call for `attr_hash` is cheaper than the originally-drafted 5+5-split design would have been (2× arity-5 + 1× arity-2 calls, paying that fixed overhead three times instead of once).
- **Proving time is roughly flat (~400ms–1.2s) across a wide constraint-count range** (69 to 16,643) — consistent with the PRD's premise that "greenfield primitives are uniformly cheap" on desktop hardware. The jump from depth-16/20 Merkle (~900ms) to depth-32 (~1.2s) is the clearest constraint-count-correlated increase in this batch.
- **EdDSA-Poseidon (8,086 constraints) costs roughly the same as a depth-16/20 Merkle proof** — expensive relative to Poseidon/range, but not dominant. This is the primitive [protocol-spec.md §3](../specs/phase-1/protocol-spec.md#3-issuer-attestation-membership-only-design-decision) deliberately keeps out of the Phase 2 credential circuit's hot path (membership-only attestation instead of in-circuit signature verification) — this baseline number is the cost that decision avoids paying on every proof.
- **zkey size scales with total constraints** roughly linearly, as expected (Groth16 proving keys are dominated by per-constraint group elements).
- **The iPhone 14 Pro proved poseidon-baseline (arity 2) roughly 12× faster than the desktop path measured here** (36ms vs 432ms) — the opposite of the "mobile is slower" assumption stated in an earlier draft of this document. This isn't a real apples-to-apples comparison of hardware, though: the desktop number times `snarkjs`'s WASM-witness-generation-plus-JS-orchestrated proving, while mopro's on-device path uses `rust-witness` (the circuit's wasm transpiled to native code at build time, per [TOOLCHAIN.md §8](../TOOLCHAIN.md#8-building-an-f11-style-mopro-app-for-a-physical-device-gotchas)) driving a native Rust/arkworks prover — a faster *software* path, running on slower *hardware*, netting out ahead. Re-baselining the desktop side through the same native path (rather than snarkjs) would be needed before drawing conclusions about the phone itself; right now this measures two different implementations, not two devices.
- Per PRD R5: "Estimates are unvalidated. Re-baseline after D0 against measured throughput" — the on-device numbers above are that re-baseline for one circuit; the other three still need it once they're wired through mopro.

## Reproducing

Each circuit directory (`poseidon-baseline/`, `range-baseline/`, `merkle-baseline/`, `eddsa-baseline/`) follows the same pattern:

```sh
circom circuit.circom --r1cs --wasm --sym -o . -l ../node_modules
# download the appropriate powersOfTau28_hez_final_<power>.ptau (see table above)
npx --prefix .. snarkjs groth16 setup circuit.r1cs powersOfTau28_hez_final_<power>.ptau circuit_0000.zkey
npx --prefix .. snarkjs zkey contribute circuit_0000.zkey circuit_final.zkey --name="..." -e="$(openssl rand -hex 32)"
npx --prefix .. snarkjs zkey export verificationkey circuit_final.zkey verification_key.json
node circuit_js/generate_witness.js circuit_js/circuit.wasm input.json witness.wtns
npx --prefix .. snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json
npx --prefix .. snarkjs groth16 verify verification_key.json public.json proof.json
```

`merkle-baseline` and `eddsa-baseline` also need `input.json` regenerated from real Poseidon/EdDSA computations (not hand-written — the witness must satisfy real hash/signature constraints), via `gen_input.js` in each directory (uses `circomlibjs`).
