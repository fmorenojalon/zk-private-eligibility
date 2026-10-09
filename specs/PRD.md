# Private Investor Eligibility — PRD

## A greenfield ZK credential system, proven on-device, verified on-chain

---

## 1. Executive Summary

Investing through a regulated platform today means surrendering payslips, bank certificates, tax returns, and identity documents to establish one boolean (*may this person invest, and up to how much?*), after which the platform stores that dossier permanently, a compliance burden and a standing breach risk for data the regulation never actually needed.

This project builds the alternative around three parties: a **holder** (the investor), an **issuer** (their bank, which attests their financial standing), and a **verifier** (the asset management platform offering the investment). The holder generates a zero-knowledge proof (a ZK-SNARK) on their own phone that they qualify as a sophisticated EU investor, without disclosing income, portfolio, employment, or identity, and the verifier checks that proof on-chain, learning nothing beyond yes/no - granting access, letting the holder reuse the same credential unlinkably, and correctly refusing access once the issuer revokes it.

This is a greenfield project: RWA tokenization platforms are building this infrastructure from zero anyway, with no legacy signature format to inherit, so every layer (schema, circuits, revocation, unlinkability, verification) is designed fresh. The MVP narrows this to one proving system (Groth16, circuits written in circom) and a recent consumer phone, answering one question: can such a credential be proven entirely on ordinary consumer hardware and verified on-chain, and at what cost as predicate complexity scales - delivered with measurement on real hardware and documentation of what's still unsolved.

---

## 2. Regulatory Basis

Regulatory realism is a design goal, not a constraint. Where a rule is impractical to model faithfully, it is simplified and the deviation documented.

### 2.1 Spain — *accredited investor* (Law 5/2015, CNMV)

Reference only: this MVP implements the EU regime (§2.2).

Qualifies on **any one** of:

| Criterion | Threshold |
| --- | --- |
| Annual income | > €50,000 |
| Financial assets | > €100,000 |
| Advisory contract | with a CNMV-authorised investment firm |

### 2.2 EU — *sophisticated investor* (ECSPR 2020/1503, Annex II)

Qualifies on **at least two of three** criteria in the full regulation. This MVP implements the first two below; the third (market activity) is dropped for scope reasons.

| # | Criterion | Threshold |
| --- | --- | --- |
| (a) | Gross income or portfolio | ≥ €60,000/yr or portfolio > €100,000 |
| (b) | Professional experience | ≥ 1 yr financial sector in a knowledge-requiring role or ≥ 12 mo executive at a qualifying entity |

---

## 3. Predicate Set

| # | Predicate | Type | Regime |
| --- | --- | --- | --- |
| P1 | income ≥ threshold | range | EU (€60k) |
| P2 | financial assets / portfolio > €100,000 | range | both |
| P3 | ≥1 yr financial sector or ≥12 mo executive | range + set membership | EU (b) |
| P4 | at least 2 of {a, b} hold (2-of-2, generic M-of-N construct) | threshold-of-N | EU — the reference case |
| P5 | jurisdiction ∈ allowed set | set membership | both |
| P6 | subject ∉ sanctions set | set non-membership | both |
| P7 | credential not expired | freshness | both |
| P8 | credential not revoked | Merkle membership in current valid-set root (the root of the set of valid credentials) | both |
| P9 | scope-bound single use | nullifier | both |

### 3.1 Credential & Tree Structure

Single tree, full attributes in the leaf, predicate logic evaluated at proof time.

Each leaf in the valid-set tree is a Poseidon commitment over the holder's complete attested attribute set (income, portfolio, professional-experience data, holder secret). The issuer's only job is attesting raw facts and maintaining one tree. All eligibility logic — including the M-of-N threshold (P4) and every other predicate — is evaluated inside the circuit at proof time, against whichever policy the verifying platform specifies for that offering.

---

## 4. Key Design Decisions

### 4.1 Revocation Without Breaking Unlinkability

A verifier must be able to confirm a credential hasn't been revoked without learning which credential it is, since a stable identifier shown on every presentation would link them all.

To do this, the issuer keeps a Merkle tree of valid credential commitments and publishes only its root on-chain, where only the issuer can update it. The holder proves in zero knowledge that their commitment is in the tree without revealing which one. Revoking removes the leaf and publishes a new root, which reveals nothing about who was revoked. Verifiers accept only the current root; otherwise a revoked holder's old proof would still pass.

The cost is that every root change forces holders to refresh their Merkle path and re-prove, and revocation takes effect only once the new root is on-chain. Mechanism: `credential-protocol.md §6`.

### 4.2 Single Use per Offering Without Cross-Offering Linkage

Each successful presentation grants access to an offering, so a holder must not be able to present to the same offering twice. A persistent per-holder identifier would prevent that, but it would also link the holder's activity across every offering.

Instead, each presentation emits a nullifier derived from the holder's secret and the offering, and the chain rejects any nullifier already used. The same holder and offering always produce the same value; different offerings produce unrelated ones. The nullifier excludes the epoch, so waiting for a new root doesn't reset it. The holder's secret is also fixed at first issuance, so re-issuing with a fresh one is rejected.

The cost is that limits spanning offerings, such as a cumulative investment cap, can't be enforced without linking presentations. Mechanism: `credential-protocol.md §7`, `§4.3.1`.

---

## 5. Core Demo Scenario

What the entire system exists to demonstrate, told in three scenarios:

**Setup.** *Alice* holds a credential issued by **Demo Bank** attesting her financial standing. **Tokenized Realty** Platform issues a tokenized Spanish commercial real-estate offering restricted to EU sophisticated investors in permitted jurisdictions.

**Scenario 1 — Privacy.** Alice opens the offering, is asked to prove eligibility, and her phone generates a proof on-device. This is possible because of Demo Bank's earlier issuance (Flow 1): Alice already holds her attested attributes and her own secret, and a Merkle path showing her credential's commitment sits in Demo Bank's currently-published root. The platform verifies the proof on-chain and grants access. *The platform learns only that she is eligible and a scope-bound nullifier — not her income, portfolio, employment, jurisdiction detail, identity, or which credential she holds.*

**Scenario 2 — Unlinkability.** Alice invests in a second, unrelated offering using the same credential. *The two presentations cannot be correlated by the platform or by any chain observer* — each offering is its own scope, so the two nullifiers are cryptographically unrelated to each other and to Alice's identity.

**Scenario 3 — Revocation.** Demo Bank revokes Alice's credential. At the next epoch, the same credential fails verification and access is refused.

**Sequencing constraint, surfaced by Phase 3's epoch design (`specs/phase-3/verification-infrastructure.md §1`).** Issuing a credential to *anyone* bumps `currentEpoch`, not just revoking one — there is no way to avoid this, since inserting a leaf changes the valid-set root exactly as removing one does. That means if Demo Bank issues a credential to a different holder between Alice's Scenario 1 and Scenario 2, her Scenario 1 path and proof go stale before Scenario 2, and she needs a path refresh and a fresh proof before presenting again.

---

## 6. User Flows

### Flow 1 — Credential Issuance

**Credential** here means the 9 issuer-attested attribute values (income, portfolio, and the other financial-standing, jurisdiction, and identity facts the issuer attests) paired with the holder's `holder_secret` — nothing derived, nothing else. `attr_hash` and `leaf` are both computed *from* the credential's contents: `attr_hash` hashes the 9 attributes together, and `leaf` hashes that result together with the holder's secret. The Merkle path is different — it isn't derived from what's *in* the credential at all, it's proof that `leaf` is currently registered in the issuer's published tree, i.e. that the credential hasn't been revoked.

1. The holder (Alice) initiates issuance with the issuer (Demo Bank) — customer identification handled out-of-band, simulated (the issuer's customer records are loaded manually, `specs/phase-3/verification-infrastructure.md §4.2`).
2. Issuer looks up its own authoritative records for this holder and discloses the 9 attribute values — the issuer is the *source* of this data, not a checker of a holder's self-reported claims.
3. Issuer computes the expected attribute hash (`attr_hash`) from those same records and sends it alongside.
4. Holder now has both the attribute values and a holder-controlled secret that never leaves the device — the credential is assembled. Holder computes `attr_hash = Poseidon(9 attribute values)` — the same hash the issuer just computed in step 3, which should match — then computes the commitment `leaf = Poseidon(holder_secret, attr_hash)`, binding the credential to a secret only the holder knows. Holder generates a proof that `leaf` was genuinely built from this `attr_hash`, without revealing the secret (`credential-protocol.md §4.3`), and sends the issuer `leaf` and the proof.
5. Issuer verifies the proof against the `attr_hash` it computed in step 3, then inserts the commitment into the valid-set tree, within its own service.
6. Issuer publishes the updated root for the current epoch and returns the resulting Merkle path to the holder.
7. The holder (Alice) stores the credential and Merkle path on their phone.

### Flow 2 — Eligibility Presentation (core flow)

1. The holder (Alice) browses an offering on the platform (Tokenized Realty Platform).
2. Platform issues a presentation request specifying scope (this offering, uniquely), epoch, and the offering's registered `jurisdictionRoot`.
3. Holder app displays *what will be proven and what will be revealed*, and requests consent.
4. Holder app fetches from the issuer, fresh right before proving (never reusing a value cached from an earlier presentation, since both rotate independently of this offering and often): its Merkle path against the *current* valid-set root and epoch (`GET /credentials/:holderId/path`, which returns path, epoch, and root together — `specs/phase-3/verification-infrastructure.md §4.1`), and its non-membership witness against the *current* `sanctionsRoot` (`GET /sanctions/path/:identityCommitment`, same spec). It also fetches its path for this offering's `jurisdictionRoot` if it doesn't already have one cached for that specific root (`GET /jurisdictions/:root/path/:jurisdictionCode`) — a holder whose jurisdiction isn't in this offering's approved set gets no path back and can't produce a satisfying witness. Holder app then generates the proof **entirely on-device**.
5. Holder app returns proof and public inputs to the platform.
6. Platform submits the proof for on-chain verification.
7. Chain verifies the proof cryptographically, cross-checks its public inputs (`validSetRoot`, `jurisdictionRoot`, `sanctionsRoot`, `currentEpoch`, `scope`) against this offering's own recorded values — proof validity alone doesn't confirm the proof was generated *for this offering*, or that its public inputs are still current (`credential-protocol.md §5.4`) — checks the nullifier is unused, records it, and returns a result.
8. The platform (Tokenized Realty Platform) grants or refuses access to Alice.

### Flow 3 — Presentation to a Second Offering (unlinkability)

Identical to Flow 2 against a different offering from Tokenized Realty Platform. The resulting nullifier differs and no public value links the two presentations.

### Flow 4 — Credential Revocation

1. The issuer (Demo Bank) removes the credential's leaf from the valid-set tree — e.g. because a change in Alice's financial conditions no longer satisfies one of the predicates.
2. The issuer (Demo Bank) publishes a new root at the next epoch.
3. Alice presents again using the proof she already had — not re-fetching a fresh path and re-proving the way Flow 2 step 4 expects — and it fails: the proof still names the epoch from before revocation, which no longer matches the registry's current one.
4. The platform (Tokenized Realty Platform) refuses access.

### Flow 5 — Eligibility Refusal

Identical to Flow 2 through step 3. Bob, whose income and portfolio both fall short of the EU regime's thresholds, attempts to present eligibility for the same real-estate offering Alice invested in. At step 4, his device cannot produce a satisfying witness — no combination of private values makes the circuit's constraints hold, so no proof exists to generate, and the flow never proceeds further. Nothing is ever submitted for Tokenized Realty Platform to reject; Bob's app simply reports that he doesn't currently qualify, and *Tokenized Realty Platform learns nothing beyond an incomplete session* — not which condition failed, not even that ineligibility was specifically determined.

### Flow 6 — Financial Conditions Change & Re-issuance

When Alice's financial conditions change at Demo Bank, nothing happens on-chain automatically. This flow composes Flow 1 (Credential Issuance) and Flow 4 (Credential Revocation) into two independent actions that may or may not both run, depending on Demo Bank's own judgement call in step 2 — the two resulting cases differ in how many root rotations they cost.

1. Demo Bank updates one or more of Alice's attribute values in its own records (e.g. income or employment changes). This step alone has no on-chain effect — Alice's existing credential is untouched and remains exactly as provable as before, since nothing has yet touched the valid-set tree.
2. Demo Bank decides, on its own judgement, whether this change is significant enough to revoke Alice's credential immediately — the system never infers or triggers this automatically. Two cases follow:
   - **Demo Bank revokes now** (Flow 4): one root rotation happens right away. Alice's credential stops verifying from the next epoch, same as any other revocation — she can't present again until she re-issues, step 3 below.
   - **Demo Bank does not revoke**: nothing changes yet. Alice's existing credential stays fully valid and provable until she herself chooses to re-issue.
3. Whenever Alice next wants to present using her updated attributes, she runs Flow 1 again in full: request the (now-updated) attribute values and hash, assemble a new commitment, and submit it for insertion. This step can only be Alice-initiated — the commitment binds to `holder_secret`, which Demo Bank never learns, so Demo Bank has no way to construct or insert a new leaf on her behalf, regardless of how urgently the update matters. What happens on-chain here depends on which case step 2 took:
   - If Demo Bank already revoked, Alice's old leaf is already gone — this submission is a plain fresh insertion, one more rotation, bringing the total for this whole episode to **two**.
   - If Demo Bank did not revoke, Alice still has a non-revoked leaf at submission time — this single call atomically revokes the old leaf and inserts the new one together, **one** rotation total for the whole episode, never a moment with zero valid leaves.

If Alice cannot reproduce her original `holder_secret` (lost or replaced device), step 3 is blocked by design (`credential-protocol.md §4.3.1`) — there's no in-product recovery; Demo Bank would need to manually clear the stored binding directly in its database before her next submission could succeed.

---

## 7. Product Requirements

### 7.1 Privacy

- **PR-1** No attribute value MUST be transmitted from the holder's device to the platform or any other party — the issuer, as the source of these facts, is the only party that legitimately holds them outside of the holder's device.
- **PR-2** Proof generation MUST occur entirely on-device, with no external proving service.
- **PR-3** A verifier MUST learn only: eligible/not eligible, the scope-bound nullifier, and the public inputs required for verification.
- **PR-4** A failed proof MUST NOT disclose which predicate failed.
- **PR-5** The holder secret MUST be generated on-device and MUST NOT be transmitted or recoverable by the issuer.

### 7.2 Unlinkability

- **PR-6** Two presentations by the same holder in different scopes MUST NOT be correlatable by the verifier or by a chain observer.
- **PR-7** Nullifiers MUST be scope-bound such that in-scope double use is rejected on-chain and cross-scope use is not.
### 7.3 Revocation

- **PR-8** The issuer MUST be able to revoke a credential without holder cooperation.
- **PR-9** A revoked credential MUST fail verification from the epoch following revocation.
- **PR-10** Revocation MUST NOT reveal which credential was revoked to verifiers or observers.
- **PR-11** An update to a holder's attribute values MUST NOT, by itself, revoke, replace, or trigger re-issuance of an existing credential — each needs its own explicit trigger.

### 7.4 Regulatory Scope

- **PR-12** The system MUST support the EU regime over a single credential — 2-of-2 in practice.
### 7.5 Holder experience

- **PR-13** Before consenting, the holder MUST be shown which predicates will be proven (e.g. "income is at least X") and which public values will be revealed to the verifier.
- **PR-14** Proof generation SHOULD show the holder an estimate of total proving time, based on prior on-device measurement for that circuit configuration.
- **PR-15** The holder SHOULD be able to inspect their credential's attributes, issuer, epoch and expiry locally.
- **PR-16** The holder SHOULD be informed why a presentation failed — expired, revoked, or ineligible — for their own troubleshooting.

### 7.6 Verifier experience

- **PR-17** The platform MUST define per-offering eligibility policy (jurisdictions).
- **PR-18** The platform MUST present a verification result traceable to an on-chain transaction.
### 7.7 Issuance integrity

- **PR-19** The issuer MUST verify, using a zero-knowledge proof, that a submitted commitment is bound to the attribute values the issuer verified, before inserting it, without learning the holder secret.

---

## 8. Technical Requirements

### 8.1 Cryptographic

- **TR-1** All circuits MUST be authored in circom and proven with Groth16 over BN254.
- **TR-2** Commitments, nullifiers, and Merkle/indexed-tree hashing MUST use Poseidon.
- **TR-3** Set membership MUST use Merkle inclusion proofs, giving a constant on-chain footprint (one root), hidden member identity, and revocation by root rotation (`credential-protocol.md §6`). Set non-membership MUST use an indexed Merkle tree (sorted leaves with next-value pointers), giving constant-size proofs and an adjacency guarantee the prover cannot falsify (`credential-protocol.md §5.3`).
- **TR-4** Circuit-specific trusted setup MUST use a public Powers-of-Tau ceremony file; setup time and artifact size MUST be recorded.
- **TR-5** Circuits MUST be parameterised over Merkle depth (16, 20, 32) and predicate count (P1 alone up to the full set), so proving cost can be measured as complexity scales.

### 8.2 On-device proving

- **TR-6** Proofs MUST be generated natively on a physical mobile device.
- **TR-7** The app MUST generate proofs without any network access, with all inputs fetched beforehand.
- **TR-8** The app MUST emit one structured record per measured run, containing the device, circuit configuration, proving-toolchain versions, and the run's metrics (proof time, peak memory, and thermal state and battery level at the start and end); the size of the proving assets MUST be reported.

### 8.3 On-chain verification

- **TR-9** Eligibility proofs MUST be verified on an EVM chain by a generated Groth16 verifier contract.
- **TR-10** On-chain state MUST let the verifier check that a proof's roots and epoch are current and issuer-approved, and that its nullifier is unused; only the issuer can update the roots (`specs/phase-3/verification-infrastructure.md §3`).
- **TR-11** On-chain gas cost MUST be measured for each circuit configuration and projected across L1 and L2 price points.
- **TR-12** The issuer service's local database MUST NOT get ahead of on-chain state, even under failed chain calls or concurrent requests, and it MUST detect any divergence on startup and refuse to serve (`specs/phase-3/verification-infrastructure.md §4.4`).

### 8.4 Constraints

- **TR-13** Results MUST be reproducible from a clean checkout.
- **TR-14** The system MUST run entirely locally; no cloud service, hosted chain, or third-party API.

---

## 9. Technical Stack & Service Topology

**Everything runs on a local machine except the holder app, which runs on a mobile device. The two communicate over the local network. Nothing is hosted externally.**

### 9.1 Services

| Service | Role | Host | Port |
| --- | --- | --- | --- |
| **Local chain** | EVM dev chain; hosts verifier + registries | local machine | 8545 |
| **Issuer service** | Credential issuance, Merkle tree custody, revocation, sanctions and jurisdiction root maintenance, root publication | local machine | 3001 |
| **Platform backend** | Offering policy, presentation requests, proof intake, on-chain submission | local machine | 3002 |
| **Platform frontend** | Investor-facing offering UI, QR presentation, result display | local machine | 5173 |
| **Measurement collector** | Ingests structured measurement records synced from the device | local machine | 3003 |
| **Holder app** | Credential storage, on-device proving, consent UI, measurement | mobile device | — |

### 9.2 Stack per component

**Circuits**

- circom 2.x; circomlib (Poseidon, comparators, Merkle inclusion)
- snarkjs for setup, desktop proving, verifier export

**Smart contracts**

- Solidity; Foundry for build/test/deploy
- Anvil as the local chain
- Contracts: a generated Groth16 verifier, `EligibilityRegistry` (epoch + set roots), `NullifierRegistry`, `OfferingPolicy`

**Issuer service**

- Node.js + TypeScript, HTTP API
- circomlibjs (Poseidon), incremental Merkle tree library
- snarkjs (verifies leaf-binding proofs)
- SQLite for credential and tree state
- Holds the issuer's on-chain account key; publishes roots to the chain

**Platform backend**

- Node.js + TypeScript, HTTP API
- viem or ethers for chain interaction
- Generates presentation requests (scope, epoch, jurisdiction root); receives proofs; submits verification transactions

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

- Structured records persisted on-device first, then synced to the measurement collector on the local machine — durable queue, not fire-and-forget, so a run survives the collector being briefly unreachable
- Analysis scripts on the local machine producing summary tables

### 9.3 Transport bindings

| Connection | Transport | Used for |
| --- | --- | --- |
| Holder app ↔ Issuer service | local HTTP | credential issuance, witness fetch (Flows 1, 2) |
| Holder app → Platform backend | local HTTP | proof delivery (Flow 2) |
| Platform frontend → Holder app | QR code | presentation request (Flow 2) |
| Platform frontend ↔ Platform backend | local HTTP | creating presentation requests, showing results (Flow 2) |
| Holder app → Measurement collector | local HTTP | measurement sync, after proof generation (§9.2) |
| Issuer service → Local chain | local JSON-RPC | root publication, jurisdiction approvals (Flows 1, 4) |
| Platform backend → Local chain | local JSON-RPC | offering registration, proof verification (Flow 2) |
| Platform frontend → Local chain | local JSON-RPC (read) | verification results (Flow 2) |

The platform submits the verification transaction, not the holder — this matches real RWA compliance flows.

### 9.4 Trust boundaries

What information crosses each boundary, and what never does, is specified in `credential-protocol.md §8.3`.

---

## 10. Phased Delivery

### Phase 1 — Foundations & Feasibility

**Requirements**

- F1.1 A circom circuit MUST prove on the iPhone 14 Pro natively.
- F1.2 A generated verifier MUST verify a real proof on the local chain, and reject a tampered one.
- F1.3 The measurement pipeline MUST emit structured records.
- F1.4 Baseline costs MUST be established for Poseidon, Merkle inclusion at three depths, range comparison, and EdDSA verification.
- F1.5 A protocol specification MUST define the credential schema, all predicates in circuit terms, the epoch and revocation model, the nullifier construction, and the threat model.

**Deliverable:** working toolchain, on-device proof, on-chain verification, measurement pipeline, baseline primitive costs, protocol specification. — done

**Acceptance:** the iPhone's proof verifies on the device, and a proof of the same circuit verifies against the generated verifier on the local chain, while a tampered one is rejected; the pipeline produces reproducible records; the specification is complete enough to implement against without further design decisions. — passed

---

### Phase 2 — Credential & Eligibility Circuits

**Requirements**

- F2.1 The credential MUST bind all attributes to a holder secret via a Poseidon commitment.
- F2.2 Circuits MUST implement P1–P9.
- F2.3 The EU 2-of-2 regime (condition (c) dropped) MUST be satisfiable from a single credential.
- F2.4 The threshold-of-N predicate (P4) MUST be implemented as a first-class construct.
- F2.5 Circuits MUST be parameterised.
- F2.6 A test suite MUST demonstrate correct acceptance and rejection across eligible, ineligible, boundary, and malformed inputs.
- F2.7 A leaf-binding proof MUST let the issuer verify a submitted commitment is bound to the issuer-verified attribute hash, without learning the holder secret (`credential-protocol.md §4.3`).

**Deliverable:** parameterised circuits covering the EU regime, with a correctness test suite and constraint counts across the complexity parameters. — done

**Acceptance:** eligible holders produce valid proofs and ineligible ones cannot, under the EU regime; constraint counts are documented per configuration. — passed

---

### Phase 3 — On-Chain Verification & Issuer Service

**Requirements**

- F3.1 The on-chain registries MUST hold the issuer's current roots (the set of valid credentials, sanctions, approved jurisdiction sets) and every consumed nullifier, and MUST accept root updates only from the issuer. — done
- F3.2 Nullifier replay within a scope MUST be rejected on-chain. — done
- F3.3 The issuer service MUST be able to issue and revoke credentials, and MUST publish the resulting roots to the chain.
- F3.4 The issuer MUST maintain the set of valid credentials with epoch rotation, the sanctions set, and the approved jurisdiction sets.
- F3.5 Revocation MUST cause proof failure from the following epoch without holder cooperation.
- F3.6 Per-offering eligibility policy MUST be configurable on-chain, limited to jurisdiction sets the issuer has approved, and an access grant MUST require the proof's jurisdiction set and scope to match the offering's registered values. — done
- F3.7 Gas MUST be measured across predicate configurations. — done
- F3.8 Re-issuance under a different holder secret MUST be detected by the issuer, without the issuer learning the secret.
- F3.9 The issuer's records MUST never get ahead of on-chain state, even under failed chain calls or concurrent requests, and any divergence MUST be detected on startup.

**Deliverable:** deployed contracts, working issuer service, functioning epoch rotation and revocation, gas measurements.

**Acceptance:** an issued credential verifies on-chain; after revocation and epoch rotation the same credential fails; replayed nullifiers are rejected; gas is documented.

---

### Phase 4 — Holder App & End-to-End Demo

**Requirements**

- F4.1 The holder app MUST be able to obtain and store credentials.
- F4.2 The holder app MUST be able to generate eligibility proofs on-device.
- F4.3 The app MUST present consent showing what is proven and what is revealed, and SHOULD show an estimate of proving time while the proof is generated.
- F4.4 All six user flows MUST behave as specified.
- F4.5 The three demo scenarios MUST be demonstrable in a single session.
- F4.6 Unlinkability MUST be evidenced by showing no public value correlates two presentations.

**Deliverable:** iOS holder app, platform frontend and backend, all six flows operating, the three-scenario demo runnable end-to-end.

**Acceptance:** an observer can watch Alice gain access privately, invest again unlinkably, and be refused after revocation — without the platform ever receiving an attribute value.

---

### Phase 5 — Measurement & Synthesis

**Requirements**

- F5.1 Proving cost MUST be measured across the full set of complexity parameters.
- F5.2 Sustained-load thermal and battery behaviour MUST be characterised.
- F5.3 UX acceptability bands for proving time MUST be defined, and each circuit configuration classified against them.
- F5.4 On-chain cost MUST be projected across L1/L2 price points.
- F5.5 A synthesis report MUST document the architecture, its design rationale and trade-offs, and state the design's limitations and unresolved tensions plainly, including what it cannot enforce.

**Deliverable:** a synthesis report covering complete measurements, UX classification, the architecture write-up and limitations, plus the reproducible artifacts behind it.

**Acceptance:** the report answers, with evidence, whether such a credential can be proven on consumer hardware and verified on-chain, and at what cost as complexity scales; every claim survives specific technical challenge.

---

## 11. Known Limitations

- **L1 — Issuer trust is out of scope.** A single operator runs both issuer and holder.
- **L2 — Regulatory modelling is a simplified model of the criteria**, not legal compliance.
- **L3 — Root authenticity rests on registry access control alone; leaf authenticity rests on the issuer service.** The `EligibilityRegistry` accepts roots only from the issuer's on-chain address, and the chain never sees individual leaves. Both are sufficient under L1's single-operator trust model; a multi-operator deployment would need an independent check, such as a signed root.
- **L4 — Credential expiry (P7) counts events, not elapsed time.** The epoch advances on every issuance and revocation, with no timer, so a credential's lifetime depends on system activity, not on the calendar. Real-time expiry would need a timestamp or a timer.
- **L5 — Re-issuance requires the original holder secret, and a lost or compromised secret has no in-product recovery.** The issuer enforces that a holder reuses the same secret, without ever learning it, so a lost or replaced phone cannot re-issue and recovery is a manual operator step. The PoC also assumes one device, and therefore one secret, per person; several accounts or devices per person are out of scope. One grant per offering holds per credential; one credential per person relies on the issuer.
- **L6 — Recovery from a crash mid-update is manual.** If the issuer service crashes after a root is confirmed on-chain but before its own records are updated, the records fall behind the chain, which is the safe direction because proofs are checked against the chain. The service detects the mismatch on startup, and an operator resolves it by hand.
- **L7 — A granted proof isn't bound to any recipient address.** The proof commits to what is proven (jurisdiction, sanctions, validity, epoch, offering) but not to an investor account, so it cannot yet drive a token-compliance flow (ERC-3643 style, §12) that needs eligibility tied to an address. Binding it means adding the recipient to the proof, which requires a circuit change and a new trusted setup.
- **L8 — Jurisdiction approvals and sanctions entries can only be added, never withdrawn.** An offering therefore keeps working against its approved jurisdiction set even if one of those jurisdictions is later restricted.
- **L9 — Not quantum-safe; a migration path exists but is not built.** A large quantum computer breaks Groth16/BN254, so an attacker could forge valid proofs. It also breaks the issuer's ECDSA account, so an attacker could publish roots. Poseidon holds up. Privacy is preserved: Groth16 proofs are perfectly zero-knowledge, so past proofs stay private, even against a future quantum attacker. The risk is forgery from that point on, so migrating before such a machine exists is enough. The verifier, the issuer address and the nullifier registry's authorized caller are all fixed at deploy time, so migration means a fresh deployment, in three steps:
  1. Move all circuits to a hash-based proving backend.
  2. Create a new issuer account with post-quantum signatures, through Ethereum's account abstraction.
  3. Redeploy `EligibilityRegistry`, `NullifierRegistry` and `OfferingPolicy`, seeded from the issuer database and the old chain: valid-set, sanctions and jurisdiction roots, registered offerings, consumed nullifiers and the current epoch. The epoch must carry over, or P7 expiries shift. Consumed nullifiers must carry over, or a holder could use the same offering twice.

  If the new backend keeps BN254 and circomlib's Poseidon, existing trees and leaves stay valid. Otherwise, every holder must re-bind, because only the holder knows `holder_secret`.

---

## 12. Out of Scope

**Excluded from the MVP:**

- Additional proving libraries, and Android or any second device.
- Legacy credential formats (passports, national eID, RSA/ECDSA-P256 issuance).
- GPU/Metal proving acceleration.
- Public testnet or mainnet deployment.
- Real KYC, real issuer integration, production security.
- Protections for non-sophisticated retail investors (e.g. investment ceilings). The MVP targets sophisticated investors only, as the EU regime in §2.2 requires.

**Post-MVP extensions:**

1. A second proving library, once circom is established end-to-end. The preferred candidate is a hash-based, post-quantum library with mobile support, for example World's ProveKit (Noir → Spartan + WHIR, BN254, no trusted setup). Benchmark it against the Groth16 results on the same predicates and device. This is also the first step of L9's migration. On-chain, ProveKit currently needs a Groth16 wrapper, so the quantum gap stays open until that wrapper is removed.
2. ERC-3643 / ERC-7943 integration — plugging the proof into a standard compliance-before-transfer flow. Requires proofs bound to a recipient address (L7).
3. Lower-cost revocation: let holders update their membership proof locally instead of re-fetching a path on every root change (for example with accumulator-based schemes).
4. Cumulative per-investor limits across offerings without linkage — the unsolved half of §4.2.
5. Android and cross-device measurement.
6. Multiple real issuers: accept attestations from several institutions, each publishing its own roots, with each platform choosing which issuers it trusts.
7. An issuer signature over published roots, so root authenticity no longer rests on registry access control alone (L3). `circuits/eddsa-baseline` already measures its cost; a post-quantum signature is part of L9's migration.
