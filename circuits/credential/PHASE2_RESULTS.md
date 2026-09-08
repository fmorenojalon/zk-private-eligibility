# Phase 2 — Eligibility Circuit Constraint Counts

Satisfies F2.6/D1's "constraint counts per configuration" requirement, plus the end-to-end proof validation from [`../../specs/phase-2/eligibility-circuits.md` §7](../../specs/phase-2/eligibility-circuits.md#7-f27--test-suite) — all three eligibility configurations, plus the F2.8 leaf-binding addendum (`credential-protocol.md §4.3`), have now gone through a real setup→prove→verify pass, not just witness generation.

**Methodology.** Same as `circuits/BASELINE_RESULTS.md`: desktop measurements (same machine), `circom --r1cs --wasm` for constraint counts, Hermez Powers-of-Tau (reused from `circuits/merkle-baseline/` — power 14 covers `circuit_p1only`/`circuit_condab`, power 16 covers `circuit_full`) + `snarkjs groth16 setup` + one dev contribution, then a single witness-generation → proving → verification pass timed with wall-clock `date +%s%N` deltas. All three ran against Alice's eligible fixture (`test/fixtures.js`) — the case each is expected to accept.

## Results

| Circuit | Non-linear | Linear | Total constraints | ptau power | witness gen | setup | contribute | proving | verify | zkey size |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `circuit_p1only.circom` | 6,044 | 6,919 | 12,963 | 14 | 198 ms | 8,600 ms | 2,096 ms | 1,336 ms | 389 ms | 5.5 MB |
| `circuit_condab.circom` | 6,184 | 6,933 | 13,117 | 14 | 91 ms | 8,473 ms | 2,125 ms | 1,318 ms | 399 ms | 5.6 MB |
| `circuit_full.circom` | 16,799 | 18,243 | 35,042 | 16 | 104 ms | 12,860 ms | 5,954 ms | 2,348 ms | 395 ms | 17 MB |
| `leaf_binding.circom` (F2.8 addendum) | 243 | 274 | 517 | 14 | 52 ms | 773 ms | 465 ms | 804 ms | 372 ms | 252 KB |

Standalone, for reference (from building P6 in isolation — [eligibility-circuits.md §4](../../specs/phase-2/eligibility-circuits.md#4-f22--predicate-templates-p1p10)):

| Template | Non-linear | Linear | Total constraints |
| --- | --- | --- | --- |
| `IndexedNonMembership(20)` | 5,694 | 5,828 | 11,522 |

All three `groth16 verify` runs returned `OK`, against genuine proofs (not witness-only satisfiability) — this is the concrete confirmation of D1's "eligible holders produce valid proofs," not just an inference from `calculateWitness` succeeding.

## Observations

- **`circuit_condab.circom` costs only 154 constraints more than `circuit_p1only.circom`** (13,117 vs 12,963) — that's condB (P3) and P4's threshold composition in full, and it's nearly free. Two extra `RangeGte` range checks and one `ThresholdOfN(2,2)` barely register next to a ~13k-constraint circuit dominated by Poseidon commitments and a Merkle inclusion proof.
- **The jump to `circuit_full.circom` (35,042, +21,925 over `circuit_condab`) is almost entirely P5 and P6, and the two numbers add up almost exactly**: P5 is one more `MerkleBaseline(20)` call, whose cost is already known from Phase 1's own baseline (10,403 constraints at depth 20 — `circuits/BASELINE_RESULTS.md`); P6 is `IndexedNonMembership(20)`, measured standalone above at 11,522. `10,403 + 11,522 = 21,925` — exactly the observed delta. This is the concrete confirmation of the reasoning that justified building `circuit_condab.circom` as a third configuration in the first place ([eligibility-circuits.md §2](../../specs/phase-2/eligibility-circuits.md#2-module-layout), "why three, not two"): the two costs really do compose additively, and P6 — the one predicate here with no prior baseline — turns out to cost about the same as a single Merkle inclusion, not something disproportionately more expensive.
- **P6 was a real unknown going in** (flagged during spec review as the one construction with no existing baseline to reuse) and it resolved cleanly: 11,522 constraints is in the same neighborhood as `circuits/merkle-baseline`'s depth-16 result (8,323) and depth-20 result (10,403), not an order of magnitude beyond either. The two 252-bit range comparators it adds on top of a plain Merkle inclusion are cheap relative to the inclusion proof itself.
- **Proving time stays well within Phase 1's already-observed range** (~400ms–1.2s at up to 16,643 constraints): `circuit_p1only`/`circuit_condab` prove in ~1.3s at ~13k constraints, and `circuit_full` at 35,042 constraints — more than double F1.4's largest baseline circuit — still proves in 2.3s. Consistent with the premise that "greenfield primitives are uniformly cheap" continuing to hold as predicate count grows, not just across Merkle depth.
- **Setup and trusted-setup contribution dominate wall-clock time, not proving** — `circuit_full`'s setup+contribute alone is ~18.8s versus 2.3s to actually prove. This only happens once per circuit version, not once per proof, so it doesn't affect the holder's real experience, but it's worth noting since it's the largest number in the table by far.
- **zkey size roughly triples from `circuit_condab` to `circuit_full`** (5.6MB → 17MB) despite constraints only ~2.7x'ing — consistent with `BASELINE_RESULTS.md`'s own observation that Groth16 proving-key size scales with constraint count.
- **`leaf_binding.circom` (F2.8) lands at exactly 517 constraints — identical to `poseidon-baseline`'s arity-2 circuit** (`BASELINE_RESULTS.md`), confirming the design claim that this fix is a direct reuse of an already-measured primitive with an equality constraint added, not new cryptographic machinery. It's the cheapest circuit in this table by a wide margin, run once per issuance rather than once per presentation, so its cost is structurally irrelevant next to the eligibility circuits above.

## Reproducing

If `circuits/merkle-baseline/powersOfTau28_hez_final_{14,16}.ptau` aren't present, download them first — see [`toolchain-baseline.md §4`](../../specs/phase-1/toolchain-baseline.md#4-trusted-setup) for the source.

From `circuits/credential/`:

```sh
node gen_phase2_inputs.js   # writes input_p1only.json, input_condab.json, input_full.json (Alice's fixture)
bash run_e2e.sh p1only ../merkle-baseline/powersOfTau28_hez_final_14.ptau
bash run_e2e.sh condab ../merkle-baseline/powersOfTau28_hez_final_14.ptau
bash run_e2e.sh full   ../merkle-baseline/powersOfTau28_hez_final_16.ptau
```

`run_e2e.sh` runs `circom --r1cs --wasm --sym`, `snarkjs groth16 setup`, `snarkjs zkey contribute`, `snarkjs groth16 prove`, and `snarkjs groth16 verify` in sequence, timing each step. Reuses the Powers-of-Tau files already downloaded for `circuits/merkle-baseline/` rather than re-fetching — any ptau at least as large as each circuit's constraint count works. `IndexedNonMembership(20)`'s standalone number came from a temporary wrapper circuit (`component main = IndexedNonMembership(20);`), not checked in — `circom_tester`'s `templateName`/`templateParams` options generate this wrapper automatically for the test suite instead.

`leaf_binding.circom` doesn't follow `run_e2e.sh`'s `circuit_<name>.circom` naming convention (it's not one of the three eligibility configurations), so its pipeline was run manually, same steps, same ptau (power 14 - 517 constraints needs nothing larger):

```sh
node gen_leaf_binding_input.js   # writes input_leaf_binding.json (Alice's real attr_hash/leaf pair)
circom leaf_binding.circom --r1cs --wasm --sym -o . -l ../node_modules
node leaf_binding_js/generate_witness.js leaf_binding_js/leaf_binding.wasm input_leaf_binding.json witness_leaf_binding.wtns
npx --prefix .. snarkjs groth16 setup leaf_binding.r1cs ../merkle-baseline/powersOfTau28_hez_final_14.ptau leaf_binding_0000.zkey
npx --prefix .. snarkjs zkey contribute leaf_binding_0000.zkey leaf_binding_final.zkey --name="phase2-dev" -e="$(openssl rand -hex 32)"
npx --prefix .. snarkjs zkey export verificationkey leaf_binding_final.zkey verification_key_leaf_binding.json
npx --prefix .. snarkjs groth16 prove leaf_binding_final.zkey witness_leaf_binding.wtns proof_leaf_binding.json public_leaf_binding.json
npx --prefix .. snarkjs groth16 verify verification_key_leaf_binding.json public_leaf_binding.json proof_leaf_binding.json
```
