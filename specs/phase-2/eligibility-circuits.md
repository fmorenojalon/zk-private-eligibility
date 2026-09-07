# Phase 2 — Eligibility Circuit Suite

**Satisfies:** F2.1–F2.7 · **Builds against:** [`../credential-protocol.md`](../credential-protocol.md) (design, already complete — this document is the implementation plan, not a re-derivation)
**Status:** Draft for review — no implementation exists yet.

> Where Phase 1's `credential-protocol.md` defines *what* the credential, predicates, and nullifier are, this document defines *how they become circom files*: module layout, parameterization, and the test matrix. Design decisions already settled in `credential-protocol.md` are referenced, not repeated.

---

## 1. Objective

Implement the credential commitment and the full EU-regime predicate logic (P1–P10) as circom circuits, parameterized per TR-6, with a correctness test suite proving eligible holders produce valid proofs and ineligible ones cannot (D1's acceptance bar).

---

## 2. Module Layout

```
circuits/credential/
├── range_predicates.circom      RangeCheck-based: P1, P2, P3, P7
├── threshold.circom             ThresholdOfN(M, N) - P4
├── indexed_nonmembership.circom IndexedNonMembership - P6 (new, credential-protocol.md §5.3)
├── circuit_p1only.circom        component main - Condition A only (P1∨P2), depth 20
├── circuit_condab.circom        component main - full 2-of-2 threshold (P1-P4), no P5/P6, depth 20
├── circuit_full.circom          component main - full EU 2-of-2 regime, depth 20
└── test/
    ├── fixtures.js               Alice/Bob/Charlie attribute sets, Merkle trees, expected outcomes
    └── eligibility.test.js       circom_tester + Mocha suite (F2.7)
```

P5/P8 need no new file at all — both `include` `circuits/merkle-baseline/template.circom` directly and instantiate `MerkleInclusion` against their own root, reused as-is rather than redefined. P10's nullifier is a single inline `Poseidon(3)` call in each composite circuit file, small enough that a dedicated file would be pure overhead.

**Per-primitive file separation, not one shared template file.** Follows Phase 1's own convention (`range-baseline/`, `merkle-baseline/`, `eddsa-baseline/` as distinct directories, each scoped to one primitive) rather than bundling every new template into a single `predicates.circom`. Each of `range_predicates.circom`, `threshold.circom`, and `indexed_nonmembership.circom` corresponds to one distinct construction with its own reasoning and, eventually, its own constraint-count story — keeping them separate mirrors how Phase 1 measured Poseidon, Merkle, range, and EdDSA as four standalone circuits rather than one combined one, and avoids growing a single file to ten templates of increasingly unrelated shape as Phase 5 adds more.

**Why three circuit files, not a single "predicate count N" parameterized template.** TR-6 says "parameterised over... predicate count," but the predicates aren't interchangeable units a generic integer can select between — P1 is a range check, P8 is Merkle membership, P4 is threshold logic over the other two. A single template taking `N` and picking "the first N predicates" doesn't correspond to any real question the complexity dial wants answered. Concretely: `circuit_p1only.circom`, `circuit_condab.circom`, and `circuit_full.circom` share every sub-template file above and differ only in which of them each top-level circuit instantiates and constrains — that *is* the parameterization TR-6 asks for, just realized as named configurations rather than one integer knob.

**Why three, not two.** Two bookends (minimum, maximum) would only show that cost differs between "P1 alone" and "everything" — not how that difference is distributed. `circuit_condab.circom` sits between them: the full `P4 = ThresholdOfN(2,2)` composition over P1–P4, plus the always-structural P7/P8/P10, but without P5/P6. Once constraint counts are measured, this turns one lump-sum delta into two attributable ones: `cost(circuit_condab) − cost(circuit_p1only)` isolates P3+P4; `cost(circuit_full) − cost(circuit_condab)` isolates P5+P6 — the more interesting number, since P6 (`IndexedNonMembership`) is the one predicate here with no existing baseline to compare against.

Phase 5's fuller complexity-dial sweep (F5.1) can add more named configurations the same way, reusing the same sub-template files.

**Depth is fixed at 20 for Phase 2's own functional testing** — the middle of F1.4's measured range (16/20/32) — not swept here. `MerkleInclusion`, included directly from `circuits/merkle-baseline/template.circom`, remains depth-parameterized there already, so Phase 5 can instantiate 16 and 32 without redesigning anything; Phase 2 just doesn't need more than one depth to prove correctness.

---

## 3. F2.1 — Credential Commitment (binding attributes to `holder_secret`)

Fully specified in `credential-protocol.md §4.2`: `attr_hash = Poseidon(9 attributes)`, `leaf = Poseidon(holder_secret, attr_hash)`. No open design question — this is a direct implementation of an existing formula. One clarification worth stating explicitly here since it affects every circuit variant: **`attr_hash` always takes all nine attributes, regardless of which predicates a given circuit variant checks.** `circuit_p1only.circom` still declares all nine attribute signals as private inputs — it just doesn't constrain most of them against a threshold. There's no "partial credential" concept; the commitment structure is fixed per `credential-protocol.md`, only which *checks* run varies.

---

## 4. F2.2 — Predicate Templates (P1–P10)

Each predicate from `credential-protocol.md §5` becomes an independent, independently-testable circom template, organized into files by primitive per §2's separation:

| Predicate | Template | File | Reuses |
| --- | --- | --- | --- |
| P1, P2 | `RangeCheck` (two instances: income≥60000, portfolio>100000) | `range_predicates.circom` | `circuits/range-baseline`'s `GreaterEqThan` pattern |
| P3 | `RangeCheck` (two instances, OR'd: financial_sector_months≥12 ∨ executive_months≥12) | `range_predicates.circom` | same |
| P4 | `ThresholdOfN(M, N)` over `[condA, condB]`, `M=2, N=2` | `threshold.circom` | `credential-protocol.md §5.2`'s spec |
| P5 | `MerkleInclusion(depth)` against `jurisdictionRoot` | — included directly from `circuits/merkle-baseline/template.circom` | `circuits/merkle-baseline`'s `template.circom`, reused as-is |
| P6 | `IndexedNonMembership` against `sanctionsRoot` — takes the low leaf's `(value, nextValue, nextIndex)` triple plus its Merkle path, not a bare value | `indexed_nonmembership.circom` | new — `credential-protocol.md §5.3`'s embedded-next-pointer construction, not yet built anywhere |
| P7 | inline `GreaterEqThan(expiry_epoch, currentEpoch)` | `range_predicates.circom` | — |
| P8 | `MerkleInclusion(depth)` against `validSetRoot` (on `leaf`) | — included directly from `circuits/merkle-baseline/template.circom` | `circuits/merkle-baseline`'s `template.circom`, reused as-is |
| P10 | `nullifier = Poseidon(holder_secret, epoch, scope)` | inline in `circuit_p1only.circom`/`circuit_full.circom` | direct Poseidon call, no sub-template needed |

*P9 (investment ceiling) is retired — removed from scope, `credential-protocol.md §5`. Not implemented here.*

`MerkleInclusion` gets instantiated **twice** in `circuit_full.circom` (P5 against `jurisdictionRoot`, P8 against `validSetRoot`) — same template, different root/path per call. `IndexedNonMembership` (P6) is the one predicate in this table with no existing baseline to reuse — genuinely new circuit logic, not an adaptation of `circuits/{range,merkle,eddsa}-baseline`.

---

## 5. F2.3 — EU 2-of-2 Regime Composition

`circuit_full.circom` wires: `condA = P1 ∨ P2`, `condB = P3`, then `P4 = ThresholdOfN(2, 2)([condA, condB])`. Per `credential-protocol.md §5`, `P4`'s output plus `P7` (freshness), `P8` (not revoked), and `P10` (nullifier, always computed as output) together constitute a valid presentation. `P5`/`P6` (jurisdiction/sanctions) are included whenever `jurisdictionRoot`/`sanctionsRoot` are supplied as public inputs — always, in `circuit_full.circom`.

`circuit_p1only.circom` wires only `condA = P1 ∨ P2` (no `P4`, no `P3`) alongside the always-structural `P7`/`P8`/`P10` — it proves "income or portfolio clears the bar, and the credential is valid and unrevoked," nothing about professional experience. This is the complexity-dial bookend, not a real regime — the EU regime always requires the full 2-of-2 composition.

`circuit_condab.circom` wires the identical `P4 = ThresholdOfN(2, 2)([condA, condB])` composition as `circuit_full.circom`, plus the always-structural `P7`/`P8`/`P10` — but omits `P5`/`P6` entirely: no `jurisdictionRoot`/`sanctionsRoot` public inputs, no membership/non-membership checks. It exists specifically as the middle point of the complexity dial (§2), isolating P5/P6's cost once constraint counts are measured, rather than to model any real regulatory variant.

---

## 6. F2.4 — Threshold-of-N as a First-Class Construct

`ThresholdOfN(M, N)` takes `N` boolean signals, outputs 1 iff at least `M` are true — a summation constraint (`Σ conditions ≥ M`), not an enumerated OR-of-ANDs, per `credential-protocol.md §5.2`. Used here at `M=2, N=2`.

**Test-suite addition beyond what F2.4 strictly requires:** the PRD (§2.3, post-MVP extension #7) explicitly claims this construct's genericity is what makes reinstating a third condition later "a configuration change, not a redesign." That claim is worth substantiating rather than just asserting — `eligibility.test.js` includes a standalone unit test instantiating `ThresholdOfN(2, 3)` directly (not wired into a full credential circuit, just the isolated template) over three synthetic booleans, confirming 2-of-3 combinations correctly pass and fail. Cheap to add, and it's the difference between claiming genericity and demonstrating it.

---

*F2.5 (investment ceiling) is retired along with P9 — removed from scope, `credential-protocol.md §5`. No section here.*

---

## 7. F2.7 — Test Suite

**Tooling:** [`circom_tester`](https://github.com/iden3/circom_tester) `0.0.24` + Mocha `12.0.0`, both new `devDependencies` in `circuits/package.json`. `circom_tester`'s `wasm_tester(path)` compiles a circuit for testing; `circuit.calculateWitness(inputs)` computes a witness; `circuit.checkConstraints(witness)` asserts it's valid. For inputs that should be **rejected**, the test asserts `calculateWitness` itself throws — this isn't a workaround, it's the literal mechanism PR-4 relies on ("no valid witness exists" for a failing predicate), and it's much faster per-test than F1.4's full setup+prove+verify pattern since no trusted setup or Groth16 proving runs per test case — appropriate here given F2.7 needs dozens of test vectors, not the handful F1.4 measured.

**Fixtures** (`test/fixtures.js`), using the PRD's own personas for narrative continuity with `PRD.md §5`:
- **Alice** — income €70,000, portfolio €150,000, 24 months financial-sector experience, valid jurisdiction, not sanctioned, credential in the current `validSetRoot`, expiry epoch > current epoch. Qualifies on every predicate.
- **Bob** — income €30,000, portfolio €50,000 (per `PRD.md` Flow 5). Fails `condA`, so fails `P4` regardless of `condB`.
- **Charlie** — used for boundary and multi-holder cases (§7 of `credential-protocol.md`'s nullifier illustration): income exactly €60,000 (boundary), and a second legitimate presentation to the same offering Alice used, to prove independent nullifiers don't collide across holders.

**Sanctions list fixture:** a static 10-entry test list, built once in `fixtures.js` per `credential-protocol.md §5.3`'s indexed-tree shape — sort the 10 test `identity_commitment` values, derive each leaf's `nextValue`/`nextIndex` from sorted position, add the two sentinel bounds (`value = 0` below the smallest entry, `nextValue = p - 1` on the largest), then build the Merkle tree over `Poseidon(value, nextValue, nextIndex)` leaves. No dynamic insertion logic is needed — that's Phase 3 issuer-service scope — this is a fixed fixture generated once per test run.

**Test matrix**, derived directly from `credential-protocol.md §8.4`'s attack→mitigation table rather than invented separately — each row there is a test case here:

| # | Case | Expected |
| --- | --- | --- |
| 1 | Alice, full regime, all real values | witness exists, all predicates true |
| 2 | Bob, full regime | `calculateWitness` throws (condA fails) |
| 3 | Alice, income exactly €60,000 (boundary) | witness exists (`≥`, inclusive) |
| 4 | Alice, income €59,999 (boundary − 1) | `calculateWitness` throws |
| 5 | Alice, but wrong `holder_secret` | `calculateWitness` throws (leaf doesn't match Merkle path) |
| 6 | Alice, tampered Merkle path (wrong sibling) | `calculateWitness` throws |
| 7 | Alice, `expiry_epoch` < `currentEpoch` | `calculateWitness` throws (P7) |
| 8 | Alice's leaf removed from tree (revoked), old root supplied | `calculateWitness` throws (P8) |
| 9 | Alice's `identity_commitment` present in `sanctionsRoot` | `calculateWitness` throws (P6) |
| 10 | Alice, `jurisdiction_code` not in `jurisdictionRoot` | `calculateWitness` throws (P5) |
| 11 | Alice presents twice to the same `scope`/`epoch` | second `nullifier` collides with first (registry-level, noted here but actually enforced on-chain per `credential-protocol.md §7` — this circuit-level test only confirms the *value* repeats, not the on-chain rejection, which is Phase 3) |
| 12 | Alice and Charlie, same `scope`/`epoch` | distinct nullifiers (independent `holder_secret`) |
| 13 | Alice, same `holder_secret` and `epoch`, two different `scope`s (Offering A vs. Offering B — `PRD.md` Beat 2) | two nullifiers with no algebraic relationship to each other (PR-6, PR-7) — this is the unlinkability property the whole demo scenario rests on, and the one case in this matrix that isn't from the attack table (it's a positive property, not a rejection case) |
| 14 | Standalone `ThresholdOfN(2,3)` unit test | correctly accepts 2-of-3 and 3-of-3, rejects 1-of-3 and 0-of-3 |
| 15 | `circuit_p1only.circom`, Alice (income only) | witness exists, no `P3`/`P4` signals present |
| 16 | `circuit_p1only.circom`, Bob | `calculateWitness` throws |
| 17 | `circuit_condab.circom`, Alice (full P1–P4, no jurisdiction/sanctions) | witness exists, no `P5`/`P6` signals present |
| 18 | `circuit_condab.circom`, Bob | `calculateWitness` throws (condA fails) |

Cases involving `P1`–`P4` combination logic or `P5`/`P6` (1–4, 9–10) need `circuit_full.circom`; cases 15–16 are explicitly against `circuit_p1only.circom`; cases 17–18 are explicitly against `circuit_condab.circom`; case 14 is a standalone template test, no circuit file. Everything else (5–8, 11–13) exercises `P7`/`P8`/`P10`, which are structural to all three circuits regardless of predicate-count configuration, so it doesn't matter which one runs them — `circuit_full.circom` is the natural default. (P9 would have joined this structural group; it's retired, per §4.)

---

## 8. Toolchain Additions

Added to `circuits/package.json` `devDependencies`, alongside the existing pinned `circomlib`/`circomlibjs`/`snarkjs`:

```json
"circom_tester": "0.0.24",
"mocha": "12.0.0"
```

No other new tools — everything else (circom 2.2.3, the Poseidon/Merkle/comparator primitives) is already pinned per `TOOLCHAIN.md`.

---

## 9. Acceptance Mapping

| Requirement | Satisfied by |
| --- | --- |
| F2.1 | §3 — direct implementation of `credential-protocol.md §4.2`'s formulas |
| F2.2 | §4 — one template per predicate, organized into files by primitive (§2) |
| F2.3 | §5 — `circuit_full.circom`'s and `circuit_condab.circom`'s composition |
| F2.4 | §6 — `ThresholdOfN`, plus the N=3 genericity test |
| F2.5 | *Retired*, along with P9 — investment ceiling removed from scope |
| F2.6 | §2 — three named configurations sharing depth-parameterized sub-templates |
| F2.7 | §7 — 18-case matrix via `circom_tester`, derived from the threat model's attack table (plus the unlinkability property, which isn't an attack-table row) |
| D1 deliverable | All of the above, plus constraint counts per configuration (recorded the same way as `circuits/BASELINE_RESULTS.md`, once built) |
