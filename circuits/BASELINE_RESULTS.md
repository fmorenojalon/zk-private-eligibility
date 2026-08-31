# F1.4 — Baseline Primitive Costs

Satisfies F1.4: "Baseline costs SHALL be established for Poseidon, Merkle inclusion at three depths, range comparison, and EdDSA verification."

**Methodology.** Desktop measurements (MacBook Pro 2024, macOS 15.6.1) using the pinned toolchain (circom 2.2.3, snarkjs 0.7.6, circomlib @ `35e54ea2`) — see [TOOLCHAIN.md](../TOOLCHAIN.md). Each circuit: `circom --r1cs --wasm` for constraint counts, Hermez Powers-of-Tau + `snarkjs groth16 setup` + one dev contribution for the proving/verification keys, then a single witness-generation → proving → verification pass timed with wall-clock `date +%s%N` deltas around each `snarkjs`/`node` invocation. These are **desktop, single-run** numbers, not the structured, repeated, on-device records [measurement-harness.md](measurement-harness.md) specifies — that harness isn't built yet (F1.3). `poseidon-baseline` additionally has a confirmed **native iPhone 14 Pro** proof (F1.1); the other three circuits have not yet been run through mopro on-device.

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

## Observations

- **Arity 10 costs ~2.7× arity 2 in constraints (1,420 vs 517), not the ~3× a naive per-call model would predict** — consistent with Poseidon's fixed per-permutation overhead (full rounds) being shared across more absorbed inputs at higher arity. This is direct evidence for the [protocol-spec.md §4.2](../specs/phase-1/protocol-spec.md#42-commitment-structure) correction: a single `Poseidon(10)` call for `attr_hash` is cheaper than the originally-drafted 5+5-split design would have been (2× arity-5 + 1× arity-2 calls, paying that fixed overhead three times instead of once).
- **Proving time is roughly flat (~400ms–1.2s) across a wide constraint-count range** (69 to 16,643) — consistent with the PRD's premise that "greenfield primitives are uniformly cheap" on desktop hardware. The jump from depth-16/20 Merkle (~900ms) to depth-32 (~1.2s) is the clearest constraint-count-correlated increase in this batch.
- **EdDSA-Poseidon (8,086 constraints) costs roughly the same as a depth-16/20 Merkle proof** — expensive relative to Poseidon/range, but not dominant. This is the primitive [protocol-spec.md §3](../specs/phase-1/protocol-spec.md#3-issuer-attestation-membership-only-design-decision) deliberately keeps out of the Phase 2 credential circuit's hot path (membership-only attestation instead of in-circuit signature verification) — this baseline number is the cost that decision avoids paying on every proof.
- **zkey size scales with total constraints** roughly linearly, as expected (Groth16 proving keys are dominated by per-constraint group elements).
- These are single-run desktop timings, not repeated/averaged, and **not yet from the physical iPhone 14 Pro** except `poseidon-baseline`. Re-baselining on-device once the other three circuits are wired through mopro (or once F1.3's harness exists) is expected to shift absolute numbers — mobile proving is typically several times slower than an M-series desktop — but the *relative* ordering between circuits should be a reasonable early signal.
- Per PRD R5: "Estimates are unvalidated. Re-baseline after D0 against measured throughput" — these numbers are exactly that early baseline, to be revisited once F1.3's structured harness produces repeated, device-tagged measurements.

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
