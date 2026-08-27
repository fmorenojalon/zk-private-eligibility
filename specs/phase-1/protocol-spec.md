# Phase 1 — Protocol Specification

**Satisfies:** F1.5 · **Feeds:** Phase 2 (F2.1–F2.7) circuit implementation
**Status:** Draft for review — no implementation exists yet.

> This document is the design contract for the credential, its predicates, the epoch/revocation model, the nullifier, and the threat model. Per the Phase 1 acceptance criterion, it must be complete enough to implement Phase 2 against without further design decisions. Items that are genuinely deferred are called out explicitly in §8, not left implicit.

---

## 1. Scope

Covers the full protocol design — not just the primitives Phase 1 measures. Phase 2 implements what's specified here; Phase 1 only builds standalone baseline circuits for the four primitives in [toolchain-baseline.md](toolchain-baseline.md).

Reflects the PRD v4.1 scope: EU regime only, 2-of-2 threshold (P4), predicates P1–P10, single-tree credential (§3.1 Option A), no in-circuit issuer-signature verification (decided below).

---

## 2. Cryptographic Primitives

| Primitive | Choice | Rationale |
| --- | --- | --- |
| Field | BN254 scalar field (`Fr`) | circom/Groth16 default (TR-1); every attribute, commitment, and nullifier value is a field element |
| Proof system | Groth16 over BN254 | TR-1 |
| Hash | Poseidon | TR-2; used for commitments, Merkle tree, and nullifier — one hash family everywhere |
| Signature | EdDSA over Baby Jubjub, Poseidon-based variant (circomlib `EdDSAPoseidonVerifier`) | TR-3; kept Poseidon-based for primitive consistency, but per §3 below it is verified **off-circuit**, not inside the eligibility circuit |
| Set membership | Merkle inclusion (Poseidon tree) | TR-4 |
| Set non-membership | Indexed/sorted Merkle tree with adjacency proof | TR-4; construction detailed in §5.3 |

---

## 3. Issuer Attestation: Membership-Only (Design Decision)

**Decision:** the eligibility circuit does **not** verify an EdDSA signature in-circuit. Merkle membership of a credential's leaf in the issuer's valid-set tree *is* the attestation.

**Why this is sufficient:** under §3.1 Option A (single tree, full-attribute leaves), a leaf can only enter the tree through an issuer-authorized transaction — the `EligibilityRegistry` contract (Phase 3, TR-12) accepts leaf insertions only from the issuer's address. Tree membership is therefore already proof that the issuer inserted this exact leaf; requiring an additional in-circuit signature check over the same commitment would prove nothing a malicious circuit couldn't already fake by fabricating both the "signature" and a Merkle path to a leaf it invented — the actual security boundary is the registry's access control, not an in-circuit check.

**Where TR-3's EdDSA requirement is still satisfied:** the issuer signs the *published root* (or a batch manifest) with EdDSA-Poseidon at epoch-rotation time. This signature is verified when the root is published/updated — on-chain, once per epoch, not once per proof. It authenticates "the issuer stands behind this root," which is a coarser but sufficient claim once leaf insertion is already access-controlled.

**Cost consequence:** the eligibility circuit avoids the most expensive of the four F1.4 baseline primitives entirely. The EdDSA baseline circuit is still built and measured in Phase 1 (F1.4 requires it as a standalone reference number), but it does not appear in the Phase 2 credential circuit's constraint count.

**Revisit trigger:** if a future requirement needs per-credential non-repudiation independent of registry access control (e.g., the issuer's registry key is later shared across multiple write paths), this decision should be revisited — noted here so the reasoning survives.

---

## 4. Credential Schema

### 4.1 Attributes

| Field | Type | Predicate(s) | Notes |
| --- | --- | --- | --- |
| `income` | uint (EUR, whole units) | P1 | annual gross income |
| `portfolio_value` | uint (EUR) | P2 | financial assets / portfolio |
| `financial_sector_months` | uint | P3 | months in a knowledge-requiring financial-sector role |
| `executive_months` | uint | P3 | months as executive at a qualifying entity |
| `jurisdiction_code` | uint (ISO 3166-1 numeric) | P5 | |
| `identity_commitment` | field element | P6 | `Poseidon(kyc_identity_hash, issuer_salt)`, computed at issuance; the value checked against the sanctions non-membership tree — kept separate from the KYC identity itself so the credential never carries the raw identity |
| `net_worth` | uint (EUR) | P9 | |
| `issued_epoch` | uint | — | epoch at issuance |
| `expiry_epoch` | uint | P7 | |
| `schema_version` | uint | — | constant per circuit version, allows future schema migration without ambiguity |
| `holder_secret` | field element | P8, P10 | generated on-device (PR-5); **never a circuit input to any other party's process, always private** |

### 4.2 Commitment Structure

Two steps, not one flat hash — because the issuer and the holder each compute a different part, and neither can compute the other's part:

```
attr_hash = Poseidon(income, portfolio_value, financial_sector_months, executive_months,
                      jurisdiction_code, identity_commitment, net_worth,
                      issued_epoch, expiry_epoch, schema_version)
leaf      = Poseidon(holder_secret, attr_hash)
```

`attr_hash` is a single 10-input Poseidon call — circomlib (pinned commit, [toolchain-baseline.md §2](toolchain-baseline.md#2-pinned-toolchain-versions)) ships reference-derived round constants for Poseidon state widths up to `t=17` (i.e. up to 16 inputs), so arity 10 is exactly as standard and audited as arity 2; there is no benefit to splitting it into smaller groups, and doing so would cost more constraints (each additional Poseidon call pays its own full-round overhead) for no robustness gain.

The two-*step* structure itself (`attr_hash`, then `leaf`) is load-bearing, not arity-driven: at issuance the issuer receives the raw attribute values to verify them out-of-band (Flow 1) and must be able to independently recompute `attr_hash` to confirm the holder isn't misrepresenting what's bound into the credential — but per PR-5 the issuer must never learn `holder_secret`. Only the holder, who alone holds the secret, can compute `leaf`. The holder computes it locally and sends the issuer the opaque `leaf` value (a hash, not a secret preimage) for insertion into the tree.

`leaf` is what the issuer inserts into the valid-set tree (§5). This grouping is a Phase 1 design choice, not yet constraint-measured — if F1.4's Poseidon baseline shows a different arity is meaningfully cheaper, this structure may be revised before Phase 2 implementation (flagged in §8).

---

## 5. Predicates in Circuit Terms

The regulation's two live EU sub-conditions map onto composite booleans built from the raw predicates:

- **Condition A** (income or portfolio) = P1 ∨ P2
- **Condition B** (professional experience) = P3

P4 (the M-of-N showcase) evaluates `sum(ConditionA, ConditionB) ≥ M`, with `M = 2, N = 2` for the current MVP — implemented as a generic parameterized construct, not a hardcoded AND, so a third condition (reinstating market activity or another regime) is a configuration change, not a circuit rewrite (F2.4, PRD post-MVP extension #7).

| # | Predicate | Circuit inputs | Logic |
| --- | --- | --- | --- |
| P1 | income ≥ €60,000 | private: `income` | `income ≥ 60000` via comparator (GreaterEqThan) |
| P2 | portfolio > €100,000 | private: `portfolio_value` | `portfolio_value > 100000` |
| P3 | ≥1yr financial sector OR ≥12mo executive | private: `financial_sector_months`, `executive_months` | `financial_sector_months ≥ 12 ∨ executive_months ≥ 12` |
| P4 | ≥2 of {A, B} hold | derived: `condA = P1 ∨ P2`, `condB = P3` | generic `ThresholdOfN(M=2, N=2)` over `[condA, condB]` |
| P5 | jurisdiction ∈ allowed set | private: `jurisdiction_code`, Merkle path; public: `jurisdictionRoot` | Merkle inclusion proof |
| P6 | subject ∉ sanctions set | private: `identity_commitment`, adjacency witness; public: `sanctionsRoot` | indexed-tree non-membership, §5.3 |
| P7 | credential not expired | private: `expiry_epoch`; public: `currentEpoch` | `expiry_epoch ≥ currentEpoch` |
| P8 | credential not revoked | private: `leaf`, Merkle path; public: `validSetRoot` | Merkle inclusion of `leaf` |
| P9 | investment ≤ max(€1,000, 5%×net worth) | private: `net_worth`; public: `investmentAmount` | `investmentAmount ≤ 1000 ∨ investmentAmount × 100 ≤ net_worth × 5` (multiplication avoids in-circuit division) |
| P10 | scope-bound single use | private: `holder_secret`; public: `epoch`, `scope` → output `nullifier` | `nullifier = Poseidon(holder_secret, epoch, scope)`, §6 |

### 5.1 Public vs. Private Inputs (summary)

**Public (verifier-visible):** `validSetRoot`, `jurisdictionRoot`, `sanctionsRoot`, `currentEpoch`, `scope`, `investmentAmount`, `nullifier` (output).
**Private (never leave the device):** all attribute values, `holder_secret`, all Merkle witnesses.

This is the concrete enumeration PR-3 requires ("a verifier SHALL learn only: eligible/not eligible, the scope-bound nullifier, and the public inputs required for verification").

### 5.2 Threshold-of-N Construct (P4, F2.4)

A first-class, reusable circuit component: given `N` boolean signals and a threshold `M`, output `1` iff at least `M` are true. Implemented as a summation (`Σ conditions ≥ M`) rather than an enumerated OR-of-ANDs, so `N` and `M` are template parameters — extending to 2-of-3 later (post-MVP extension #7) means instantiating with `N=3`, not rewriting the predicate.

### 5.3 Non-Membership Construction (P6, TR-4)

Indexed Merkle tree: sanctioned identity commitments are stored sorted by value. Non-membership of `identity_commitment` is proven by exhibiting two **adjacent** leaves `low` and `high` such that:

1. `low < identity_commitment < high`
2. Both `low` and `high` are valid members of `sanctionsRoot` (standard Merkle inclusion)
3. `low` and `high` are tree-adjacent (no leaf value lies between them) — enforced by the issuer's insertion procedure maintaining sorted, gapless adjacency, attested implicitly by tree well-formedness

This is the same category of construction used by indexed-tree accumulators elsewhere (e.g. Aztec's indexed Merkle trees); chosen over a bitmap or flat-list scan because it stays constant-size regardless of sanctions-list size, matching the "allowlist/sanctions set sizes" complexity dial (§3, PRD).

---

## 6. Epoch & Revocation Model

- **Epoch:** a monotonically increasing integer, issuer-controlled. Each epoch has exactly one `validSetRoot`, published on-chain by `EligibilityRegistry` (TR-12).
- **Rotation trigger:** any revocation forces a new root and epoch (issuer removes the leaf, recomputes the tree, publishes). Exact rotation cadence policy (e.g. whether epochs also rotate on a fixed timer independent of revocation) is an issuer-service configuration decision, deferred to Phase 3 (§8).
- **Witness refresh:** holders must re-fetch their Merkle witness against the current root each epoch to keep proving membership — an explicit, accepted UX cost (PRD §4.1).
- **Bounded exposure window (L2):** between a revocation event and the next root publication, a credential whose witness still validates against the *previous* root can still produce a proof if the verifier accepts stale roots. **Mitigation:** the platform's presentation request specifies `currentEpoch`/`validSetRoot` explicitly (Flow 2, step 2), and the circuit's public input for `validSetRoot` must match what the verifier contract holds as canonical for that epoch — a proof against a stale root is simply a proof against a public input the on-chain verifier rejects as non-current. The exposure window is therefore bounded by *root publication latency*, not by holder behavior.

---

## 7. Nullifier Construction

```
nullifier = Poseidon(holder_secret, epoch, scope)
```

- `epoch`: the current epoch, public input, matches the epoch of `validSetRoot` used in the same proof.
- `scope`: a field element uniquely identifying the presentation context, chosen by the platform backend and included in the presentation request (Flow 2, step 2) — e.g. `Poseidon(offering_id)`. Two different offerings ⇒ two different `scope` values ⇒ unrelated nullifiers, even for the same `holder_secret` and `epoch` (PR-6, PR-7).
- **Replay check:** on-chain `NullifierRegistry` rejects any `nullifier` it has already recorded (TR-13). Because `scope` is baked into the nullifier itself, no separate scope-tracking is needed on-chain — the replay check is a flat "have I seen this exact value" lookup, which is naturally scope-bound by construction.
- **Cross-scope linkage (L3):** explicitly not solvable by this construction — the same `holder_secret` across two different `scope`s produces unrelated nullifiers, so cumulative caps across scopes cannot be enforced without additional linkage. Stated in PRD §4.2 / PR-8 and repeated here since it's directly a nullifier-design consequence.

---

## 8. Threat Model

### 8.1 Assets

- Attribute values (income, portfolio, experience, jurisdiction, net worth)
- `holder_secret`
- Linkage between two presentations by the same holder
- Which specific credential (leaf) a given proof corresponds to

### 8.2 Adversaries

| Adversary | Capability | Must not learn / must not succeed at |
| --- | --- | --- |
| Platform (honest-but-curious) | Sees proof, public inputs, nullifier, investment amount, offering scope | Attribute values; linking two nullifiers from different scopes to the same holder (PR-3, PR-6) |
| Chain observer | Sees all on-chain state: roots, nullifiers, transactions | Correlating nullifiers across scopes to a holder; recovering attribute values or which leaf produced a proof |
| Malicious holder | Controls their own device, credential, and circuit inputs | Producing a valid proof without qualifying attributes; replaying a nullifier within a scope; proving membership after revocation and root rotation |
| Compromised/malicious issuer | Out of scope (L1) — the author operates both issuer and holder | N/A; not addressed by this protocol |

### 8.3 Trust Boundaries

Reuses PRD §9.4 verbatim — repeated here for a self-contained threat model:

| Boundary | Crosses it | Never crosses it |
| --- | --- | --- |
| Device → Issuer | attribute values *(issuance only)*, commitment | holder secret |
| Device → Platform | proof, public inputs, nullifier | attribute values, holder secret, credential |
| Platform → Chain | proof, public inputs | anything holder-identifying |

### 8.4 Attack → Mitigation Map

| Attack | Mitigation | Requirement |
| --- | --- | --- |
| Forge eligibility without qualifying attributes | Predicate logic is enforced in-circuit; Groth16 soundness | PR-1–PR-4 |
| Steal/replay another holder's proof | Proof is bound to `holder_secret` via `leaf` and `nullifier`; without the secret, no valid witness exists | PR-5 |
| Correlate two presentations by the same holder | Scope-bound nullifier (§7); no shared public value across scopes | PR-6, PR-7 |
| Replay a nullifier within one scope | On-chain `NullifierRegistry` rejects duplicates | PR-7, TR-13 |
| Use a revoked credential | `validSetRoot` public input pinned to current epoch; revoked leaf absent from current tree | PR-9, PR-10 |
| Determine which credential was revoked from chain data alone | Root rotation reveals only a new root hash, not which leaf changed | PR-11 |
| Learn which predicate failed from a failed proof | Groth16 proofs are all-or-nothing; no partial-validity signal | PR-4 |
| Platform stores attribute data | Impossible by construction — attributes never transmitted (PR-1, PR-22) | PR-22 |

---

## 9. Open Items Deferred to Phase 2/3

- **Epoch rotation cadence policy** — issuer-service configuration, decided during Phase 3 implementation (F3.4).
- **Sanctions/jurisdiction tree maintenance procedure** — issuer-service implementation detail (insertion, sorting, adjacency upkeep for §5.3), Phase 3.
- **Exact `scope` derivation from `offering_id`** — Phase 3 platform-backend implementation detail; the protocol only requires it be a field element unique per offering.
