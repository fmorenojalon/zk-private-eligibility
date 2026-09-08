# Private Investor Eligibility — PRD

## A greenfield ZK credential system, proven on-device, verified on-chain

---

## 1. Executive Summary

**What this is.** An end-to-end system in which a person proves on their own phone that they qualify as a sophisticated investor under EU rules — *without disclosing income, portfolio, employment, or identity* — and an investment platform verifies that claim on-chain, learning nothing beyond a yes/no.

**The problem.** Investing through a regulated platform today means surrendering payslips, bank certificates, tax returns and identity documents to establish a single boolean: *may this person invest, and up to how much?* The platform then stores that dossier permanently — a compliance burden for them and a standing breach risk for the investor. The regulation only ever required the boolean.

**Why now, and why greenfield.** RWA tokenization platforms are building new credential infrastructure from scratch. There is no legacy signature format to inherit, so ZK-friendly primitives can be selected at issuance. Every architectural layer is designed from zero: credential schema, predicate circuits, revocation, unlinkability, on-chain verification.

**Scope discipline.** The MVP is deliberately narrowed to **one proving library (circom), one device (iPhone 14 Pro), one machine (MacBook Pro 2024)**. Extension to a second library is a post-MVP option.

**The research question.** *Can a greenfield, unlinkable, revocable eligibility credential be proven entirely on a four-year-old consumer phone and verified on-chain — and what does it cost as predicate complexity scales?*

**Primary contribution.** A **systems and architecture** contribution: a complete privacy-preserving compliance flow that works, with honest measurement of what it costs on real hardware and honest documentation of which problems remain unsolved.

**Success in one sentence.** A person on an iPhone gains access to a tokenized investment offering by proving eligibility, uses the same credential again without the platform being able to link the two events, and is correctly refused after the issuer revokes them.

---

## 2. Regulatory Basis

Regulatory realism is a **design goal, not a constraint**. Where a rule is impractical to model faithfully, it is simplified and the deviation documented.

### 2.1 Spain — *inversor acreditado* (Ley 5/2015, CNMV)

Qualifies on **any one** of:

| Criterion | Threshold |
| --- | --- |
| Annual income | > €50,000 |
| Financial assets | > €100,000 |
| Advisory contract | with a CNMV-authorised investment firm |

### 2.2 EU — *sophisticated investor* (ECSPR 2020/1503, Annex II)

Qualifies on **at least two of three**:

| # | Criterion | Threshold |
| --- | --- | --- |
| (a) | Gross income **or** portfolio | ≥ €60,000/yr **or** portfolio > €100,000 |
| (b) | Professional experience | ≥ 1 yr financial sector in a knowledge-requiring role **or** ≥ 12 mo executive at a qualifying entity |

### 2.3 Why this regulation suits ZK

The EU structure is a *threshold predicate over heterogeneous sub-conditions* — substantive circuit design rather than a single comparison, even reduced to 2-of-2 for the MVP (§2.2). Modelling it as a generic M-of-N comparator, rather than hardcoding "both," is what keeps this a genuine architectural showcase rather than an AND gate — and is what makes cross-jurisdiction extensibility (re-adding condition (c), or the Spanish regime) a configuration change rather than a rebuild.

---

## 3. Predicate Set

| # | Predicate | Type | Regime |
| --- | --- | --- | --- |
| P1 | income ≥ threshold | range | EU (€60k) |
| P2 | financial assets / portfolio > €100,000 | range | both |
| P3 | ≥1 yr financial sector **or** ≥12 mo executive | range + set membership | EU (b) |
| P4 | at least 2 of {a, b} hold (2-of-2, generic M-of-N construct) | threshold-of-N | EU — the showcase |
| P5 | jurisdiction ∈ allowed set | set membership | both |
| P6 | subject ∉ sanctions set | set non-membership | both |
| P7 | credential not expired | freshness | both |
| P8 | credential not revoked | Merkle membership in current valid-set root | both |
| P10 | scope-bound single use | nullifier | both |

*P9 is retired — the investment ceiling predicate (below max(€1,000, 5% of net worth)) was removed from scope; this project targets sophisticated/accredited investors only, not the non-sophisticated-investor protections that predicate existed for. P10 keeps its number rather than shifting to P9, to avoid renumbering churn across specs.*

**Complexity dial.** Because greenfield primitives are uniformly cheap, the measurement axis is deliberate complexity scaling: Merkle depth (16 → 20 → 32), predicate count (P1 alone → full set), allowlist/sanctions set sizes, and regime (EU 2-of-3).

### 3.1 Credential & Tree Structure

**Single tree, full attributes in the leaf, predicate logic evaluated at proof time.**

Each leaf in the valid-set tree is a Poseidon commitment over the holder's **complete attested attribute set** (income, portfolio, professional-experience data, holder secret). The issuer's only job is attesting raw facts and maintaining one tree. All eligibility logic — including the M-of-N threshold (P4) and every other predicate — is evaluated **inside the circuit at proof time**, against whichever policy the verifying platform specifies for that offering (PR-20).

---

## 4. Core Design Challenges

### 4.1 Unlinkability ⊗ Revocation

Naive revocation publishes revoked credential identifiers; proving you are absent from that list reveals your identifier and destroys unlinkability.

**Approach:** a Merkle allowlist of valid credentials with epoch rotation. The holder proves membership in the current valid-set root without revealing which leaf. Revocation removes the leaf and rotates the root.

**Accepted cost:** revocation takes effect only at an epoch boundary, creating a bounded exposure window. Holders must refresh their Merkle path on each root change.

### 4.2 Cap Enforcement ⊗ Unlinkability

Enforcing a cumulative cap requires per-investor state; unlinkability forbids correlating presentations. These requirements are in direct conflict.

**Approach:** scope-bound nullifiers derived from (holder secret, epoch, scope). **Scope identifies a specific offering** — the tokenized investment product a holder is proving eligibility for (§5's real-estate offering, for instance). Each presentation to a given offering produces a nullifier unique to that (holder, offering, epoch) combination; presenting to a *different* offering produces an unrelated one.

This solves two problems at once:

- **Reuse within one offering becomes detectable.** Without it, nothing stops a holder from presenting eligibility to the same offering an unlimited number of times, inflating their effective allocation past whatever a single investor is meant to receive. If Alice presents to an offering twice, her second nullifier collides with her first and is rejected on-chain (PR-7, TR-13). Charlie, a different investor presenting to that *same* offering, produces his own independent nullifier — it depends on his own holder secret — so his activity is entirely unaffected by Alice's.
- **Presentations to different offerings stay unlinkable.** Alice investing in two unrelated offerings produces two nullifiers with no discoverable relationship to each other or to her identity (PR-6, PR-7) — this is the mechanism behind §5's Beat 2.

**Accepted cost:** cumulative caps *across* offerings cannot be enforced without linkage. This limitation is stated explicitly in the output rather than papered over.

---

## 5. Core Demo Scenario

The scenario the entire system exists to demonstrate, in three beats.

**Setup.** *Alice* holds a credential issued by **Banco Demo** attesting her financial standing. **Inmobiliaria Tokenizada** Platform issues a tokenized Spanish commercial real-estate offering restricted to EU sophisticated investors in permitted jurisdictions.

**Beat 1 — Privacy.** Alice opens the offering, is asked to prove eligibility, and her phone generates a proof on-device. The platform verifies it on-chain and grants access. *The platform learns only that she is eligible and a scope-bound nullifier — not her income, portfolio, employment, jurisdiction detail, identity, or which credential she holds.*

**Beat 2 — Unlinkability.** Alice invests in a second, unrelated offering using the same credential. *The two presentations cannot be correlated by the platform or by any chain observer* — each offering is its own scope (§4.2), so the two nullifiers are cryptographically unrelated to each other and to Alice's identity.

**Beat 3 — Revocation.** Banco Demo revokes Alice's credential. At the next epoch, the same credential fails verification and access is refused.

**Why these three.** These are the three properties that constitute a working privacy-preserving compliance flow.

---

## 6. User Flows

Five flows define the system's behaviour.

### Flow 1 — Credential Issuance

**Credential** here means the 9 issuer-attested attribute values paired with the holder's `holder_secret` — nothing derived, nothing else. `attr_hash` and `leaf` are computed *from* the credential; the Merkle path is evidence *about* it.

1. Holder initiates issuance with the issuer (customer identification handled out-of-band, simulated — see §11).
2. Issuer looks up its own authoritative records for this holder and discloses the 9 attribute values — the issuer is the *source* of this data, not a checker of a holder's self-reported claims.
3. Issuer computes the expected attribute hash (`attr_hash`) from those same records and sends it alongside.
4. Holder now has both the attribute values and a holder-controlled secret that never leaves the device — the credential is assembled. Holder computes `attr_hash = Poseidon(9 attribute values)` — the same hash the issuer just computed in step 3, which should match — then computes the commitment `leaf = Poseidon(holder_secret, attr_hash)`, binding the credential to a secret only the holder knows. Holder generates a proof that `leaf` was genuinely built from this `attr_hash`, without revealing the secret (PR-23, `credential-protocol.md §4.3`), and sends the issuer `leaf` and the proof.
5. Issuer verifies the proof against the `attr_hash` it computed in step 3, then inserts the commitment into the valid-set tree (access-controlled to the issuer's address — L10).
6. Issuer publishes the updated root for the current epoch and returns the resulting Merkle path to the holder.
7. Holder stores the credential and Merkle path on-device.

**Property:** the holder secret is generated on-device and never leaves it.

### Flow 2 — Eligibility Presentation (core flow)

1. Holder browses an offering on the platform.
2. Platform issues a presentation request specifying scope (this offering, uniquely — §4.2) and epoch.
3. Holder app displays *what will be proven and what will be revealed*, and requests consent.
4. Holder app generates the proof **entirely on-device**.
5. Holder app returns proof and public inputs to the platform.
6. Platform submits the proof for on-chain verification.
7. Chain verifies, checks the nullifier is unused, records it, and returns a result.
8. Platform grants or refuses access.

**Property:** no attribute value is transmitted at any point.

### Flow 3 — Repeat Presentation (unlinkability)

Identical to Flow 2 against a different offering. The resulting nullifier differs and no public value links the two presentations.

### Flow 4 — Revocation

1. Issuer removes the credential's leaf from the valid-set tree.
2. Issuer publishes a new root at the next epoch.
3. Holder's subsequent proof fails the valid-set membership predicate.
4. Platform refuses access.

**Property:** revocation requires no communication with the holder.

### Flow 5 — Refusal (ineligible)

Bob, whose income and portfolio both fall short of the EU regime's thresholds, attempts to present eligibility for the same real-estate offering Alice invested in. His device cannot produce a satisfying witness — no combination of private values makes the circuit's constraints hold, so no proof exists to generate. The platform refuses access and *learns only that the proof was invalid* — not which condition failed.

---

## 7. Product Requirements

### 7.1 Privacy

- **PR-1** No attribute value SHALL leave the holder's device in any flow.
- **PR-2** Proof generation SHALL occur entirely on-device, with no proving service.
- **PR-3** A verifier SHALL learn only: eligible/not eligible, the scope-bound nullifier, and the public inputs required for verification.
- **PR-4** A failed proof SHALL NOT disclose which predicate failed.
- **PR-5** The holder secret SHALL be generated on-device and SHALL NOT be transmitted or recoverable by the issuer.

### 7.2 Unlinkability

- **PR-6** Two presentations by the same holder in different scopes SHALL NOT be correlatable by the verifier or by a chain observer.
- **PR-7** Nullifiers SHALL be scope-bound such that in-scope double use is detectable and cross-scope use is not.
- **PR-8** The system SHALL document precisely which linkages remain possible (§4.2).

### 7.3 Revocation

- **PR-9** The issuer SHALL be able to revoke a credential without holder cooperation.
- **PR-10** A revoked credential SHALL fail verification from the epoch following revocation.
- **PR-11** Revocation SHALL NOT reveal which credential was revoked to verifiers or observers.
- **PR-12** Revocation latency SHALL be bounded and documented.

### 7.4 Regulatory modelling

- **PR-13** The system SHALL support the EU 2-of-3 regime over a single credential.
- **PR-14** — *Retired.* Enforced the investment ceiling predicate (P9, retired — §3) relative to undisclosed net worth; removed along with it, scope now being sophisticated/accredited investors only.
- **PR-15** Deviations from actual regulation SHALL be documented.

### 7.5 Holder experience

- **PR-16** The holder SHALL be shown what will be proven and what will be revealed before consenting.
- **PR-17** Proof generation SHALL surface honest progress and real elapsed time — no artificial delay, no concealed latency.
- **PR-18** The holder SHALL be able to inspect their credential's attributes, issuer, epoch and expiry locally.
- **PR-19** Failures (expired, revoked, ineligible) SHALL be distinguishable to the *holder*, though not to the verifier.

### 7.6 Verifier experience

- **PR-20** The platform SHALL define per-offering eligibility policy (regime, jurisdictions).
- **PR-21** The platform SHALL present a verification result traceable to an on-chain transaction.
- **PR-22** The platform SHALL NOT be capable of storing attribute data, by construction.

### 7.7 Issuance integrity

- **PR-23** The issuer SHALL verify that a submitted credential commitment is bound to the specific attribute values the issuer verified, before inserting it, without the issuer learning the holder secret.

---

## 8. Technical Requirements

### 8.1 Cryptographic

- **TR-1** All circuits SHALL be authored in circom and proven with Groth16 over BN254.
- **TR-2** Commitments and nullifiers SHALL use Poseidon.
- **TR-3** — *Retired.* Called for issuer signatures via EdDSA over Baby Jubjub; this PoC relies on registry access control instead (leaf and root writes both restricted to the issuer's on-chain address) rather than an additional signature — see L10.
- **TR-4** Set membership SHALL use Merkle inclusion proofs; set non-membership SHALL use a documented construction.
- **TR-5** Circuit-specific trusted setup SHALL use a public Powers-of-Tau ceremony file; setup time and artifact size SHALL be recorded.
- **TR-6** Circuits SHALL be parameterised over Merkle depth and predicate count to support the complexity dial.
- **TR-23** The issuer SHALL verify a zero-knowledge proof binding a submitted credential commitment to the issuer-verified attribute hash before insertion (PR-23) — a circuit reusing the same Poseidon/Groth16 primitives as TR-1/TR-2, not a new cryptographic construction.

### 8.2 On-device proving

- **TR-7** Proofs SHALL be generated natively on the iPhone 14 Pro; simulator measurements SHALL be rejected as invalid.
- **TR-8** The app SHALL operate without network access during proof generation.
- **TR-9** Proving assets SHALL be bundled or cached locally; asset size SHALL be measured and reported.
- **TR-10** The app SHALL record proof time, peak memory, thermal state, and battery delta per run.

### 8.3 On-chain verification

- **TR-11** Verification SHALL occur on an EVM chain via a Groth16 verifier contract.
- **TR-12** Registries SHALL maintain: valid-set root per epoch, sanctions root, jurisdiction allowlist root, and consumed nullifiers.
- **TR-13** Nullifier replay within a scope SHALL be rejected on-chain.
- **TR-14** Gas cost SHALL be measured per predicate configuration and projected across L1/L2 price points.
- **TR-15** All chain interaction SHALL run against a local development chain.

### 8.4 Measurement

- **TR-16** Every measured run SHALL emit a structured record including device, circuit configuration, backend version, and all metrics.
- **TR-17** The measurement schema SHALL be device-agnostic to permit later platform extension without rework.
- **TR-18** Sustained-load runs SHALL enforce cooldown and record thermal transitions.
- **TR-19** Results SHALL be reproducible from a clean checkout.

### 8.5 Constraints

- **TR-20** The system SHALL run entirely locally; no cloud service, hosted chain, or third-party API.
- **TR-21** All development SHALL target macOS on the MacBook Pro 2024 as the sole build machine.
- **TR-22** The system SHALL function with the iPhone and Mac on the same local network.

---

## 9. Technical Stack & Service Topology

**Everything runs on the MacBook Pro 2024 except the holder app, which runs on the iPhone 14 Pro. The two communicate over the local network. Nothing is hosted externally.**

### 9.1 Services

| Service | Role | Host | Port |
| --- | --- | --- | --- |
| **Local chain** | EVM dev chain; hosts verifier + registries | MacBook | 8545 |
| **Issuer service** | Credential issuance, Merkle tree custody, revocation, root publication | MacBook | 3001 |
| **Platform backend** | Offering policy, presentation requests, proof intake, on-chain submission | MacBook | 3002 |
| **Platform frontend** | Investor-facing offering UI, QR presentation, result display | MacBook | 5173 |
| **Measurement collector** | Ingests structured measurement records synced from the device (TR-16) | MacBook | 3003 |
| **Holder app** | Credential storage, on-device proving, consent UI, measurement | iPhone 14 Pro | — |

### 9.2 Stack per component

**Circuits**

- circom 2.x; circomlib (Poseidon, EdDSA, comparators, Merkle inclusion)
- snarkjs for setup, desktop proving, verifier export

**Smart contracts**

- Solidity; Foundry for build/test/deploy
- Anvil as the local chain
- Contracts: `Groth16Verifier` (generated), `EligibilityRegistry` (epoch + set roots), `NullifierRegistry`, `OfferingPolicy`

**Issuer service**

- Node.js + TypeScript, HTTP API
- circomlibjs (Poseidon, EdDSA), incremental Merkle tree library
- SQLite for credential and tree state
- Holds the issuer keypair; publishes roots to the chain

**Platform backend**

- Node.js + TypeScript, HTTP API
- viem or ethers for chain interaction
- Generates presentation requests (regime, scope, epoch, nonce); receives proofs; submits verification transactions

**Platform frontend**

- React + Vite
- QR rendering for presentation requests
- Reads verification results from the chain

**Holder app (iOS)**

- SwiftUI; Swift 5.9+
- mopro-generated bindings wrapping the circom/Groth16 prover
- Keychain for holder secret and credential storage
- Camera for QR capture
- Embedded measurement instrumentation emitting structured records

**Measurement**

- Structured records persisted on-device first, then synced to the measurement collector on the Mac — durable queue, not fire-and-forget, so a run survives the collector being briefly unreachable
- Analysis scripts on the Mac producing summary tables

### 9.3 Transport bindings

- **Issuance:** holder app → issuer service over local HTTP.
- **Presentation request:** platform frontend → holder app via QR code.
- **Proof delivery:** holder app → platform backend over local HTTP.
- **Verification:** platform backend → local chain. *The platform submits the transaction, not the holder — this matches real RWA compliance flows and avoids requiring a funded account on the phone.*
- **Measurement sync:** holder app / on-device harness → measurement collector over local HTTP. Records are written to durable on-device storage immediately after each run, then synced; the client retries until the collector acknowledges receipt, so no record is lost to a transient network or collector outage. Sync happens after proof generation completes, never during it (TR-8).

### 9.4 Trust boundaries

| Boundary | Crosses it | Never crosses it |
| --- | --- | --- |
| Issuer → Device | attribute values, expected attribute hash *(issuance only)* | — |
| Device → Issuer | commitment, leaf-binding proof (PR-23) | holder secret, attribute values *(never re-disclosed, only consumed locally)* |
| Device → Platform | proof, public inputs, nullifier | attribute values, holder secret, credential |
| Platform → Chain | proof, public inputs | anything holder-identifying |

---

## 10. Phased Delivery

Five phases, each ending in a demonstrable deliverable. Requirements only — sequencing within a phase is left open.

### Phase 1 — Foundations & Feasibility — done

**Objective:** prove the toolchain works end-to-end and establish measurement capability.

**Requirements**

- F1.1 A circom circuit SHALL prove on the iPhone 14 Pro natively. — done
- F1.2 A generated verifier SHALL verify a real proof on the local chain, and reject a tampered one. — done
- F1.3 The measurement harness SHALL emit structured records satisfying TR-16 to TR-19. — done
- F1.4 Baseline costs SHALL be established for Poseidon, Merkle inclusion at three depths, range comparison, and EdDSA verification. — done
- F1.5 A protocol specification SHALL define the credential schema, all predicates in circuit terms, the epoch and revocation model, the nullifier construction, and the threat model. — done

**Deliverable D0 — Feasibility Baseline:** working toolchain, on-device proof, on-chain verification, measurement harness, baseline primitive costs, protocol specification. — done

**Acceptance:** a proof generated on the iPhone verifies on the local chain; the harness produces reproducible records; the specification is complete enough to implement against without further design decisions.

---

### Phase 2 — Credential & Eligibility Circuits — done

**Objective:** implement the credential and the full predicate logic.

**Requirements**

- F2.1 The credential SHALL bind all §2 attributes to a holder secret via a Poseidon commitment (TR-2). — done
- F2.2 Circuits SHALL implement P1–P10 (P9 retired — §3). — done
- F2.3 The EU 2-of-3 regime SHALL be satisfiable from a single credential (PR-13). — done
- F2.4 The threshold-of-N predicate (P4) SHALL be implemented as a first-class construct. — done
- F2.5 — *Retired,* along with P9 (§3): the investment ceiling requirement no longer applies now that scope is sophisticated/accredited investors only.
- F2.6 Circuits SHALL be parameterised per TR-6. — done
- F2.7 A test suite SHALL demonstrate correct acceptance and rejection across eligible, ineligible, boundary, and malformed inputs. — done
- F2.8 A leaf-binding proof SHALL let the issuer verify a submitted commitment is bound to the issuer-verified attribute hash, without learning the holder secret (PR-23, TR-23) — added as an addendum after a design review surfaced the gap; see `credential-protocol.md §4.3`. — done

**Deliverable D1 — Eligibility Circuit Suite:** parameterised circuits covering the EU regime, with a correctness test suite and constraint counts across the complexity dial. — done

**Acceptance:** eligible holders produce valid proofs and ineligible ones cannot, under the EU regime; constraint counts are documented per configuration.

---

### Phase 3 — On-Chain Verification & Issuer Service

**Objective:** stand up the infrastructure that makes proofs meaningful.

**Requirements**

- F3.1 Registry contracts SHALL maintain all roots and consumed nullifiers per TR-12.
- F3.2 Nullifier replay within a scope SHALL be rejected on-chain (TR-13).
- F3.3 The issuer service SHALL expose issuance and revocation over local HTTP, and SHALL publish roots to the chain; both leaf insertion and root publication SHALL be restricted to the issuer's on-chain address (access control — TR-3 retired, L10).
- F3.4 The issuer SHALL maintain the valid-set tree with epoch rotation per §4.1.
- F3.5 Revocation SHALL cause proof failure from the following epoch (PR-10) without holder cooperation (PR-9).
- F3.6 Per-offering eligibility policy SHALL be configurable on-chain (PR-20).
- F3.7 Gas SHALL be measured across predicate configurations (TR-14).

**Deliverable D2 — Verification Infrastructure:** deployed contracts, working issuer service, functioning epoch rotation and revocation, gas measurements.

**Acceptance:** an issued credential verifies on-chain; after revocation and epoch rotation the same credential fails; replayed nullifiers are rejected; gas is documented.

---

### Phase 4 — Holder App & End-to-End Demo

**Objective:** the complete system, demonstrable to a non-technical observer.

**Requirements**

- F4.1 The holder app SHALL obtain and store credentials per Flow 1, satisfying PR-5.
- F4.2 The holder app SHALL generate eligibility proofs on-device per PR-1, PR-2, TR-7, TR-8.
- F4.3 The app SHALL present consent showing what is proven and what is revealed (PR-16), with honest progress (PR-17).
- F4.4 The platform frontend and backend SHALL implement Flow 2 end-to-end.
- F4.5 All five user flows (§6) SHALL execute successfully.
- F4.6 The three demo beats (§5) SHALL be demonstrable in a single session.
- F4.7 Unlinkability SHALL be evidenced by showing no public value correlates two presentations (PR-6).

**Deliverable D3 — Working System:** iOS holder app, platform frontend and backend, all five flows operating, the three-beat demo runnable end-to-end.

**Acceptance:** an observer can watch Alice gain access privately, invest again unlinkably, and be refused after revocation — without the platform ever receiving an attribute value.

---

### Phase 5 — Measurement & Synthesis

**Objective:** convert the working system into a defensible, publishable result.

**Requirements**

- F5.1 Proving cost SHALL be measured across the full complexity dial (§3).
- F5.2 Sustained-load thermal and battery behaviour SHALL be characterised (TR-18).
- F5.3 UX acceptability bands SHALL be defined per interaction model and each configuration classified against them.
- F5.4 On-chain cost SHALL be projected across L1/L2 price points (TR-14).
- F5.5 The architecture, its design rationale, and its trade-offs SHALL be documented.
- F5.6 Unresolved tensions (§4) SHALL be stated explicitly, including what the design cannot enforce.
- F5.7 All limitations in §11 SHALL be stated plainly.
- F5.8 Results SHALL be reproducible from a clean checkout (TR-19).

**Deliverable D4 — Synthesis Report:** complete measurements, UX classification, architecture write-up, honest limitations, reproducible artifacts.

**Acceptance:** the report answers the research question with evidence, and every claim survives specific technical challenge.

---

### Summary

| Phase | Deliverable | Status |
| --- | --- | --- |
| 1 | D0 — Feasibility Baseline | done |
| 2 | D1 — Eligibility Circuit Suite | done |
| 3 | D2 — Verification Infrastructure | |
| 4 | D3 — Working System | |
| 5 | D4 — Synthesis Report | |

---

## 11. Known Limitations

To be stated plainly in all output.

- **L1 — Issuer trust is out of scope.** A single operator runs both issuer and holder. The hardest real-world problem — why anyone should trust the issuer's attestation — is not addressed. The contribution is cryptographic and architectural, not trust bootstrapping.
- **L2 — Revocation has a bounded exposure window** by construction (§4.1).
- **L3 — Cross-scope cumulative caps cannot be enforced** without linkage (§4.2).
- **L4 — Regulatory modelling is a good-faith approximation**, not legal compliance.
- **L5 — Single device, single library.** Results characterise circom/Groth16 on an A16-class device. No claim is made about other stacks or hardware.
- **L6 — Not production-hardened.** No security audit, no key management discipline, no adversarial testing.
- **L7 — EU regime is 2-of-2, not 2-of-3.** Condition (c) (market activity, P5) was dropped as the most expensive sub-condition. The threshold predicate is built as a generic M-of-N construct (F2.4), so this is a configuration limit rather than an architectural one — but the MVP result characterises 2-of-2, not the full regulation.
- **L8 — Spanish regime not implemented.** Retained in §2.1 as regulatory reference only. Its unique predicate, P3 (advisory-contract membership), is consequently out of scope too.
- **L9 — Merkle trees have fixed capacity, set by depth at deploy time.** Every tree in this system (valid-set, jurisdiction, sanctions) holds at most `2^depth` leaves; exceeding it means a full rebuild at greater depth, not an incremental add. This is cheaper to absorb than it sounds — F1.4's baseline shows constraint cost scales linearly with depth while capacity scales exponentially (depth 32 costs ~2× depth 16's constraints for 65,536× the capacity), so depth 20 alone (Phase 2's default) already covers over a million entries at already-measured cost. The actual open question is operational, not cryptographic: no validated estimate exists for real-world sanctions/jurisdiction list sizes against that ceiling, and a rebuild event (new root, all cached low-leaf lookups invalidated) has no defined procedure yet.
- **L10 — Root and leaf authenticity rest entirely on registry access control, not a signature.** TR-3 originally called for the issuer to sign published roots with EdDSA; this PoC retires that and relies solely on the `EligibilityRegistry` contract restricting leaf insertion and root publication to the issuer's on-chain address. This is sufficient under L1's trust model (a single operator runs both issuer and holder, and issuer honesty is already assumed) but means authenticity depends entirely on that one contract's access-control logic being correct — there is no independent, contract-logic-free way to verify a root came from the issuer, the way a signature would provide. A real multi-operator deployment would need to reconsider this.

---

## 12. Out of Scope

**Excluded from the MVP:**

- Additional proving libraries. *Post-MVP option.*
- Android or any second device.
- Legacy credential formats (passports, national eID, RSA/ECDSA-P256 issuance).
- Confidential amounts or encrypted balances.
- GPU/Metal proving acceleration.
- Recursion or proof aggregation.
- Public testnet or mainnet deployment.
- Real KYC, real issuer integration, production security.

**Post-MVP extensions**, in rough order of value:

1. A second proving library, once circom is established end-to-end.
2. ERC-3643 / ERC-7943 integration — plugging the proof into a standard compliance-before-transfer flow.
3. Cryptographic accumulators for constant-time revocation without epoch latency.
4. Cross-scope cap enforcement without linkage — the unsolved half of §4.2.
5. Android and cross-device measurement.
6. Delegated attestation from real financial institutions.
7. Reinstate EU condition (c) (P5) and/or the Spanish regime (P3), if Phase 2 constraint counts show headroom — the M-of-N construct (F2.4) is built to make this a configuration change, not a redesign.
8. Reinstate TR-3's issuer EdDSA signature over published roots (retired for the MVP — L10), giving root authenticity an independently-verifiable guarantee beyond the registry contract's own access control — relevant once more than one party needs to trust the same infrastructure. `circuits/eddsa-baseline`'s Phase 1 measurement already covers the cost.
