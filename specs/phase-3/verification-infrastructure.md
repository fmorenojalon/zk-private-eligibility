# Phase 3 — Verification Infrastructure

**Satisfies:** F3.1–F3.7 · **Builds against:** [`../credential-protocol.md`](../credential-protocol.md) (design, already complete) and [`../phase-2/eligibility-circuits.md`](../phase-2/eligibility-circuits.md) (the three circuit configurations this phase deploys and measures)
**Status:** Draft for review — no implementation exists yet.

> Where `credential-protocol.md` defines *what* the registries, epoch model, and nullifier are, and explicitly defers three items to this phase (§9: epoch rotation cadence, sanctions/jurisdiction tree maintenance, `scope` derivation), this document resolves those and defines *how they become contracts and a service*: module layout, interfaces, and the test matrix.

---

## 1. Objective

Stand up the on-chain registries and issuer service that make Phase 2's proofs meaningful: real access control on who can write what, real epoch rotation on revocation, real per-offering policy enforcement (closing the scope/jurisdiction cross-checking gap `credential-protocol.md §5.4` identifies), and real gas measurements across the three circuit configurations — satisfying D2's acceptance bar (an issued credential verifies on-chain; after revocation and epoch rotation the same credential fails; replayed nullifiers are rejected; gas is documented).

**Three design decisions this phase resolves, previously left open (`credential-protocol.md §9`):**
- **Epoch increments on every valid-set root change — issuance or revocation, not revocation alone.** No fixed timer. `EligibilityRegistry.publishValidSetRoot` increments the epoch every time it's called, and it's called whenever the valid-set tree's root changes: on issuance (a new leaf inserted, Flow 1 step 6) exactly as much as on revocation (a leaf zeroed, Flow 4). This isn't a compromise, it's forced by the tree structure — inserting a leaf into a fixed-depth tree changes the root exactly the way zeroing one does, so there is no way to issue a credential without invalidating every other holder's cached path against the old root. Treating only revocation as epoch-worthy would let issuance silently change the root *under the same epoch number*, making `validSetRootAt[currentEpoch]` ambiguous — two different roots claiming one epoch. The simplest correct rule is: any root change is a new epoch, full stop. (This has a real consequence for what an epoch *means* — see L11 on P7's expiry semantics, `specs/PRD.md §11`.)
- **The sanctions indexed tree and the issuer's canonical jurisdiction tree both support real dynamic insertion — by different mechanisms.** The sanctions tree implements the actual splice procedure `credential-protocol.md §5.3` specifies (locate the low leaf, update its `nextValue`/`nextIndex`, insert the new leaf) — not a fixture rebuilt from scratch each time; that algorithm is already fully specified, so this phase is implementation, not new design. The jurisdiction tree is a plain Merkle tree (§4.1), so growing it is ordinary leaf insertion at the next empty index, no splice needed. Each offering's approved subset tree is different again — built fresh from scratch per `/jurisdictions/approve-subset` request (§4.1), since it's a new, distinct tree every time, not something that grows incrementally.
- **`scope = offeringId`, directly — no hashing.** `offeringId` is a `uint256` assigned sequentially by `OfferingPolicy` when a platform registers a new offering (`registerOffering`, §3.3), and is used as `scope` as-is. `scope` is already a public, verifier-visible input (`credential-protocol.md §5.1`) — there is nothing to hide by hashing it, and a sequential counter is unique by construction, for free, with no separate uniqueness bookkeeping needed. (A caller-supplied `scope = Poseidon(offeringId)` value at registration would admit two offerings registering the same `scope` by mistake or malice, silently colliding their nullifier spaces — using `offeringId` itself removes the parameter, and the risk, entirely.)
- **`jurisdictionRoot` is issuer-approved, not platform-invented.** `jurisdiction_code` is one of the nine issuer-attested attributes (`credential-protocol.md §4`), so the tree P5 checks it against needs the same issuer backing `validSetRoot`/`sanctionsRoot` already have — a platform-chosen value with no connection to anything the issuer attested would let a platform register an offering against jurisdiction codes that never went through any issuer process at all. The issuer maintains one canonical tree of every jurisdiction code it recognizes (`/jurisdictions/add`, §4.1) and separately approves the specific subset roots offerings are allowed to use (`EligibilityRegistry.approveJurisdictionRoot`, §3.1) — a platform selects among issuer-approved roots at registration (§3.3), it never constructs and registers one of its own. This resolves an inconsistency that previously ran through `credential-protocol.md §5.4`, `PRD.md TR-12`, and `F3.6`, each describing `jurisdictionRoot` a different, incompatible way.

---

## 2. Contract Layout

```
contracts/src/
├── Groth16Verifier.sol           (existing, Phase 1 — poseidon-baseline)
├── verifiers/
│   ├── Groth16VerifierP1Only.sol   generated from circuit_p1only's verification key
│   ├── Groth16VerifierCondAB.sol   generated from circuit_condab's verification key
│   └── Groth16VerifierFull.sol     generated from circuit_full's verification key
├── EligibilityRegistry.sol       validSetRoot (per-epoch), sanctionsRoot, approved jurisdictionRoots
│                                   — global, issuer-controlled
├── NullifierRegistry.sol         consumed-nullifier set — global, flat
└── OfferingPolicy.sol            per-offering jurisdictionRoot, constrained to issuer-approved
                                    values (scope is the offeringId itself, §1); the single entry
                                    point that ties verification + recorded-value cross-checks +
                                    nullifier consumption together atomically
```

**Why `jurisdictionRoot` is split across two contracts.** `EligibilityRegistry` holds *which* `jurisdictionRoot` values the issuer has actually approved — an issuer-maintained fact, the same as `validSetRoot`/`sanctionsRoot`. `OfferingPolicy` holds *which one* of those approved roots a given offering uses — a platform policy choice (different offerings can legitimately restrict to different jurisdiction subsets), but constrained to roots the issuer already vouched for, never an arbitrary value the platform invents. This two-tier split is what makes P5 trustworthy: `jurisdiction_code` is an issuer-attested attribute, so the tree it's checked against needs the same issuer backing, not an unrelated platform-chosen value with no connection to what was actually attested — matching how `credential-protocol.md` already treats the valid-set tree and the nullifier record as separate structures with separate owners (§7).

**Why one generated verifier contract per circuit configuration.** Each of the three Phase 2 circuits (`circuit_p1only`, `circuit_condab`, `circuit_full`) has its own trusted setup and therefore its own verification key — `snarkjs zkey export solidityverifier` produces one `.sol` file per key, exactly as Phase 1 did for `poseidon-baseline`. This is what makes F3.7's "gas measured across predicate configurations" possible: three deployed verifiers, three real gas numbers, not an estimate.

**Caveat, matching the class of thing `TOOLCHAIN.md` already documents for `rust_witness`'s underscore-stripping:** `snarkjs zkey export solidityverifier` always emits a contract literally named `contract Groth16Verifier`, regardless of the output filename — three files each declaring the same contract name won't compile together in one Foundry project. After exporting each one, rename the contract declaration itself (not just the file) to match — `Groth16VerifierP1Only`, `Groth16VerifierCondAB`, `Groth16VerifierFull` — before adding it to the build.

---

## 3. F3.1, F3.2, F3.6 — Contract Interfaces

### 3.1 `EligibilityRegistry`

```solidity
address public immutable issuer;

uint256 public currentEpoch;                        // starts at 0
mapping(uint256 => bytes32) public validSetRootAt;   // epoch => root, full history retained
bytes32 public sanctionsRoot;                        // single current value, no per-epoch history
mapping(bytes32 => bool) public approvedJurisdictionRoots;  // issuer-vouched-for roots only

event ValidSetRootPublished(uint256 indexed epoch, bytes32 root);
event SanctionsRootPublished(bytes32 root);
event JurisdictionRootApproved(bytes32 root);

modifier onlyIssuer() { require(msg.sender == issuer, "not issuer"); _; }

function publishValidSetRoot(bytes32 newRoot) external onlyIssuer {
    currentEpoch += 1;
    validSetRootAt[currentEpoch] = newRoot;
    emit ValidSetRootPublished(currentEpoch, newRoot);
}

function publishSanctionsRoot(bytes32 newRoot) external onlyIssuer {
    sanctionsRoot = newRoot;
    emit SanctionsRootPublished(newRoot);
}

function approveJurisdictionRoot(bytes32 root) external onlyIssuer {
    approvedJurisdictionRoots[root] = true;
    emit JurisdictionRootApproved(root);
}
```

**Why `approveJurisdictionRoot` records approval as a set, not a single current value.** Unlike `validSetRoot`/`sanctionsRoot`, there is no one "current" jurisdiction root — different offerings legitimately use different subsets at the same time (a real-estate offering restricted to EU jurisdictions, a different offering with a different allowlist, both live simultaneously). `approvedJurisdictionRoots` is therefore a set of everything the issuer has ever vouched for, not a slot that gets overwritten; `OfferingPolicy.registerOffering` (§3.3) checks a specific root's membership in this set, and old approvals never expire or block new ones. The issuer builds each subset root off-chain (`/jurisdictions/approve-subset`, §4.1) from codes drawn from its own canonical tree (`/jurisdictions/add`, §4.1) before ever approving it on-chain — the approval is what lets `OfferingPolicy` trust a root without re-deriving it itself.

**`validSetRootAt` keeps full history for analysis, not for the security check itself.** The security property `credential-protocol.md §6`'s bounded-exposure-window mitigation requires is currency: "a proof against a stale root is simply a proof against a public input the on-chain verifier rejects as non-current" — recorded *for the epoch the registry currently recognizes as current*, not for whatever epoch a proof happens to claim. §3.3 below enforces this directly with `require(publicSignals[epoch] == currentEpoch())`, checked before any lookup into `validSetRootAt` at all. Keeping full history in the mapping is still useful on its own terms — "which root was recorded at epoch N" is a reasonable question to be able to answer later for off-chain analysis or audit — it just isn't what the security check itself depends on; that check only ever needs the *current* entry. `sanctionsRoot` has no epoch concept (§5.3's indexed tree isn't tied to the credential epoch cycle at all), so it's a single mutable value — but see "The `sanctionsRoot` gap this closes" in §3.3 below: it still needs the *current-only* check, just without the epoch dimension.

Constructor takes `issuer` (the deploying address, matching L10/TR-3-retired's access-control model — no signature, access control is the entire security boundary).

### 3.2 `NullifierRegistry`

```solidity
mapping(uint256 => bool) public consumed;
address public immutable deployer;   // captured at construction, gates setAuthorized only
address public authorized;           // set once, to OfferingPolicy's address, after it's deployed

event NullifierConsumed(uint256 indexed nullifier);

constructor() {
    deployer = msg.sender;
}

function setAuthorized(address a) external {
    require(msg.sender == deployer, "not deployer");
    require(authorized == address(0), "already set");
    authorized = a;
}

modifier onlyAuthorized() { require(msg.sender == authorized, "not authorized"); _; }

function consumeIfUnused(uint256 nullifier) external onlyAuthorized {
    require(!consumed[nullifier], "nullifier already used");
    consumed[nullifier] = true;
    emit NullifierConsumed(nullifier);
}
```

**Why `consumeIfUnused` needs access control, not just scope-binding.** `credential-protocol.md §7`'s point that `scope` is already baked into `nullifier`'s value explains why no *separate scope-tracking structure* is needed — a flat lookup suffices instead of a per-scope tree — but that's a different property from who is allowed to *call* `consumeIfUnused`. Scope-binding stops cross-scope linkage; it does nothing to stop unauthorized consumption. Concretely: anyone watching the mempool for a pending `presentEligibility` transaction can read `publicSignals[0]` (the nullifier — §3.3) straight out of the calldata, front-run it with a direct `consumeIfUnused` call, and the legitimate holder's real presentation reverts on "already used" even though they never got access. They can't forge a *valid* nullifier without `holder_secret`, but they don't need to — they only need to grief a value they can already see.

**Why `setAuthorized` is gated to `deployer`, not just callable once.** Being one-time-only isn't enough by itself: without a caller restriction, anyone could front-run the legitimate deployment and call `setAuthorized(attacker)` first, permanently bricking the contract — `OfferingPolicy` could never be wired in, and the attacker could write arbitrary values into `consumed` forever. Capturing `deployer` at construction (`immutable`, so it can't be reassigned) and gating `setAuthorized` to it directly closes this: the deployment sequence is deploy `NullifierRegistry` (deployer = the deploying account), deploy `OfferingPolicy` passing its address, then the *same* deployer account calls `nullifiers.setAuthorized(address(offeringPolicy))` once (§7.4's integration tests use this exact sequence). This function is **not** `view`/`pure` — it mutates `consumed` and is expected to be called mid-transaction from `OfferingPolicy.presentEligibility`, reverting the whole transaction (including any state `OfferingPolicy` already touched) if the nullifier is already used. No separate scope-tracking structure — matching §7's "flat lookup, not a tree" design exactly.

### 3.3 `OfferingPolicy`

```solidity
struct Offering {
    bytes32 jurisdictionRoot;
    bool exists;
    // no separate `scope` field - the mapping key (offeringId) IS the scope, §1
}

address public immutable platform;
EligibilityRegistry public immutable registry;
NullifierRegistry public immutable nullifiers;
Groth16VerifierFull public immutable verifier;   // circuit_full only - see note below

uint256 public nextOfferingId;
mapping(uint256 => Offering) public offerings;

event OfferingRegistered(uint256 indexed offeringId, bytes32 jurisdictionRoot);
event EligibilityGranted(uint256 indexed offeringId, uint256 indexed nullifier);

modifier onlyPlatform() { require(msg.sender == platform, "not platform"); _; }

function registerOffering(bytes32 jurisdictionRoot) external onlyPlatform returns (uint256 offeringId) {
    require(registry.approvedJurisdictionRoots(jurisdictionRoot), "jurisdictionRoot not issuer-approved");
    offeringId = nextOfferingId++;
    offerings[offeringId] = Offering(jurisdictionRoot, true);
    emit OfferingRegistered(offeringId, jurisdictionRoot);
}

function presentEligibility(
    uint256 offeringId,
    uint256[2] calldata pA,
    uint256[2][2] calldata pB,
    uint256[2] calldata pC,
    uint256[6] calldata publicSignals
    // [nullifier, jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope] -
    // outputs first (circom's universal R1CS wire layout), then circuit_full's declared
    // public inputs in order. Verified two independent ways:
    //   1. The authoritative source: circuit_full.circom's literal declaration line -
    //      `component main {public [jurisdictionRoot, sanctionsRoot, validSetRoot,
    //      currentEpoch, scope]} = CircuitFull(20);` - names this exact order for the
    //      five declared public inputs.
    //   2. A value-based cross-check against the real artifact: each named field's
    //      VALUE in circuits/credential/input_full.json (looked up by key, e.g.
    //      input.jurisdictionRoot - not by the file's textual key order, which proves
    //      nothing on its own) equals the value sitting at public_full.json's index
    //      1-5 in this exact order; index 0 is the one value in public_full.json with
    //      no corresponding named field in input_full.json at all - the nullifier
    //      output. Both checks agree.
    // Getting this wrong is severe: consumeIfUnused must consume the nullifier
    // (index 0), never `scope` (index 5) - scope is identical across every holder of
    // a given offering, so consuming it would permanently lock out every
    // presentation after the first.
) external returns (bool granted) {
    Offering memory o = offerings[offeringId];
    require(o.exists, "unknown offering");

    // Recorded-value cross-checks (credential-protocol.md §5.4) - BEFORE the expensive
    // cryptographic verification, so a mismatched offering fails cheaply.
    require(publicSignals[1] == uint256(o.jurisdictionRoot), "wrong jurisdictionRoot for this offering");
    require(publicSignals[2] == uint256(registry.sanctionsRoot()), "stale or wrong sanctionsRoot");
    require(publicSignals[4] == registry.currentEpoch(), "stale epoch");
    require(publicSignals[3] == uint256(registry.validSetRootAt(publicSignals[4])), "wrong validSetRoot for the current epoch");
    require(publicSignals[5] == offeringId, "wrong scope for this offering");

    // Cryptographic binding (credential-protocol.md §5.4) - the proof itself.
    require(verifier.verifyProof(pA, pB, pC, publicSignals), "invalid proof");

    // Atomic with verification - no window for a second presentation to slip
    // through between "verified" and "recorded" (credential-protocol.md §7).
    nullifiers.consumeIfUnused(publicSignals[0]);
    emit EligibilityGranted(offeringId, publicSignals[0]);

    granted = true;
}
```

**Why `presentEligibility` checks `publicSignals[epoch] == registry.currentEpoch()` before using it to index `validSetRootAt`.** Since `currentEpoch` is a public input the prover freely chooses at proving time (Groth16 only guarantees the proof is valid for *some* self-consistent set of public inputs, never that they're the *current* ones — `credential-protocol.md §5.4`, cryptographic binding vs. recorded-value cross-checking), a lookup indexed by whatever epoch the *prover's own proof claims* — without first confirming that epoch is actually current — would defeat three things at once: (1) **revocation (P8)** — a revoked holder simply re-presents their original proof, still naming the old epoch, and `validSetRootAt(oldEpoch)` faithfully returns the old root, matching; (2) **replay protection (P10)** — since `nullifier = Poseidon(holder_secret, epoch, scope)`, a holder able to name any epoch they like can mint a fresh, unconsumed nullifier for the *same* scope simply by varying which past epoch they claim, defeating TR-13/PR-7 within a single offering; (3) **expiry (P7)** — an expired holder (`expiry_epoch < currentEpoch`) simply claims an earlier epoch where `expiry_epoch ≥ currentEpoch` was still true, and the in-circuit check (correctly implemented, Phase 2 cases 7/21) faithfully verifies a self-consistent but stale claim. The circuit itself is correct; nothing on-chain binds its `currentEpoch` input to reality without this check. Checking `publicSignals[4]` (the epoch) against `registry.currentEpoch()` directly, *before* using it to index `validSetRootAt`, closes all three — the historical mapping stays useful for analysis (§3.1) but the security property comes from currency, not lookup.

**Why `presentEligibility` checks `o.jurisdictionRoot` against the proof, not against `registry.approvedJurisdictionRoots` again.** The approval check already happened once, at `registerOffering` time (§3.1) — `o.jurisdictionRoot` can only ever hold a root the issuer approved, since `registerOffering` refuses anything else. Re-checking approval on every presentation would be redundant work for a value that can't change after registration; what `presentEligibility` still needs to check is that *this proof* was built against *this offering's* root, exactly the same "does the proof match what this offering actually configured" question the `sanctionsRoot`/`scope` checks below answer for their own public inputs.

**The `sanctionsRoot` gap this closes.** `credential-protocol.md §5.4`'s opening line says every public input needs recorded-value cross-checking, but its elaboration only worked through `validSetRoot`, `jurisdictionRoot`, and `scope` concretely — `sanctionsRoot` was covered by the general principle but never got its own explicit mitigation spelled out, and had no implementation to enforce it until now. The check above closes it: a proof built against a `sanctionsRoot` that isn't the registry's *current* value is rejected, the same "stale root" protection `validSetRoot` gets, extended to the one public input that was missing it. Without this check, someone newly added to the sanctions list could still present using a non-membership proof generated before they were added — exactly the exposure-window problem §6 already solved for revocation, just unsolved here until this contract exists.

**Why `presentEligibility` is hardwired to `circuit_full`, not generic across configurations.** Each generated verifier's `verifyProof` has a *fixed-size* public-signals array sized to that exact circuit's public input count (confirmed against the real Phase 1 contract: `uint[1]` for `poseidon-baseline`'s single public input); `circuit_p1only`/`circuit_condab` have 4 public signals, `circuit_full` has 6 — these are incompatible Solidity types, not interchangeable through one generic interface or a dynamic `uint256[] calldata`, so a single shared signature across all three configurations would not compile. This isn't a loss: `circuit_p1only`/`circuit_condab` are Phase 2's complexity-parameter range endpoints, never a live regime (`eligibility-circuits.md §5`) — no real offering ever presents against them, so `OfferingPolicy` never needed to accept them. §6 covers how they still get gas-measured, just not through this contract.

---

## 4. F3.3, F3.4 — Issuer Service

```
issuer-service/
├── src/
│   ├── server.ts              HTTP API (Node's built-in http module - see ARCHITECTURE.md's
│   │                            "prefer built-ins" precedent; no framework needed for this surface)
│   ├── attributeStore.ts       SQLite-backed lookup of the issuer's own attribute records per holder
│   │                            (this PoC's stand-in for "the issuer's real banking records")
│   ├── merkleTree.ts           incremental Merkle tree for the valid-set tree and both jurisdiction
│                            trees (canonical + per-offering subsets, §4.1) - all plain inclusion
│                            trees, no indexed/linked-list structure needed (unlike sanctions)
│   ├── indexedTree.ts          the sanctions indexed tree specifically, with real splice-based
│   │                            insertion (credential-protocol.md §5.3) - extends the SparseMerkleTree
│   │                            logic already built for Phase 2's test fixtures (test/fixtures.js)
│   │                            rather than starting over
│   ├── leafBinding.ts          verifies the F2.8 leaf-binding proof (snarkjs groth16 verify against
│   │                            circuits/credential/verification_key_leaf_binding.json)
│   └── chain.ts                submits publishValidSetRoot/publishSanctionsRoot/
│                                 approveJurisdictionRoot transactions,
│                                 signed by the issuer's account
├── db/
│   └── schema.sql              §4.2
└── test/
    └── *.test.ts               node:test (built-in, zero dependencies - see toolchain note below)
```

### 4.1 HTTP API surface

| Method & path | Request | Response | Behavior |
| --- | --- | --- | --- |
| `POST /credentials/request` | `{ holderId }` | `{ attrs: {...9 fields}, attrHash }` | Looks up the issuer's own attribute records for this holder (SQLite `attributeStore`), computes `attr_hash = Poseidon(9 attributes)`, returns both. No verification of anything yet — this is the issuer *disclosing* its own records (Flow 1, step 2). |
| `POST /credentials/submit` | `{ holderId, leaf, proof, publicSignals }` | `{ accepted: true, epoch, root }` or `4xx` | Verifies the F2.8 leaf-binding proof against the `attrHash` this holder was issued in the prior call; if valid, inserts `leaf` into the valid-set tree, recomputes the root, calls `EligibilityRegistry.publishValidSetRoot` (Flow 1, steps 4–6). Rejects if the proof doesn't verify, or if `attrHash` doesn't match what was actually issued to this `holderId`. |
| `GET /credentials/:holderId/path` | — | `{ pathElements, pathIndices, epoch, root }` | Returns the current Merkle path for this holder's leaf against the *current* root — needed both right after issuance (Flow 1, step 7) and again on every path-refresh after an epoch rotation (`credential-protocol.md §6`). |
| `POST /revoke` | `{ holderId }` | `{ epoch, root }` | Removes the holder's leaf from the valid-set tree (sets it back to the empty/sentinel value at its index), recomputes the root, publishes it — one new epoch (Flow 4, steps 1–2). |
| `POST /sanctions/add` | `{ identityCommitment }` | `{ root }` | Real dynamic insertion into the indexed sanctions tree: locate the low leaf, update its `nextValue`/`nextIndex`, insert the new leaf, recompute and publish `sanctionsRoot`. |
| `POST /jurisdictions/add` | `{ jurisdictionCode }` | `{ root }` | Grows the issuer's one canonical tree of every jurisdiction code it recognizes (a plain Merkle tree, not indexed — `credential-protocol.md §5`'s P5 uses ordinary inclusion, not non-membership). This tree is never presented against directly; it's the source set §4.1's next row draws from. |
| `POST /jurisdictions/approve-subset` | `{ jurisdictionCodes }` | `{ root }` | Builds a *separate*, offering-scoped tree from exactly the requested codes, checking each one is actually present in the canonical tree above; calls `EligibilityRegistry.approveJurisdictionRoot(root)` (§3.1) so `OfferingPolicy.registerOffering` (§3.3) can later accept it. This is what makes a platform's per-offering jurisdiction allowlist a set the issuer vouched for, not one the platform invented. |
| `GET /jurisdictions/:root/path/:jurisdictionCode` | — | `{ pathElements, pathIndices }` or `404` | Returns this jurisdiction code's Merkle path *within the specific approved subset tree at `:root`* — what a holder's device needs to satisfy P5 when presenting to an offering that uses this particular root (not necessarily the canonical tree). `404` if the code isn't actually a member of that subset — the holder doesn't qualify for offerings using it, which is correct behavior, not an error condition. Reconstructs the tree on demand from `jurisdiction_subset_trees` (§4.2); a root alone can't answer this, since a Merkle root reveals nothing about its own contents. |

All local HTTP, no auth beyond what TR-20's "runs entirely locally" already implies — matching the measurement collector's own precedent of a minimal, dependency-free local service (`ARCHITECTURE.md`).

### 4.2 SQLite Schema

```sql
CREATE TABLE holder_attributes (
    holder_id       TEXT PRIMARY KEY,
    income          TEXT NOT NULL,  -- field elements stored as decimal strings (BigInt-safe)
    portfolio_value TEXT NOT NULL,
    financial_sector_months TEXT NOT NULL,
    executive_months TEXT NOT NULL,
    jurisdiction_code TEXT NOT NULL,
    identity_commitment TEXT NOT NULL,
    issued_epoch    INTEGER NOT NULL,
    expiry_epoch    INTEGER NOT NULL,
    schema_version  TEXT NOT NULL
);

CREATE TABLE issued_attr_hashes (
    holder_id  TEXT PRIMARY KEY REFERENCES holder_attributes(holder_id),
    attr_hash  TEXT NOT NULL,       -- computed and returned at /credentials/request time
    issued_at  TEXT NOT NULL
);

CREATE TABLE valid_set_leaves (
    tree_index INTEGER PRIMARY KEY,
    holder_id  TEXT NOT NULL REFERENCES holder_attributes(holder_id),
    leaf       TEXT NOT NULL,       -- 0 (the sentinel/empty value) once revoked, never deleted -
                                     -- index reuse would change other holders' path indices
    revoked    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE indexed_tree_nodes (
    tree        TEXT NOT NULL,      -- 'sanctions' | 'jurisdiction'
    leaf_index  INTEGER NOT NULL,
    value       TEXT NOT NULL,
    next_value  TEXT NOT NULL,
    next_index  INTEGER NOT NULL,
    PRIMARY KEY (tree, leaf_index)
);

CREATE TABLE jurisdiction_subset_trees (
    root              TEXT NOT NULL,   -- the approved subset root this row belongs to
    jurisdiction_code TEXT NOT NULL,
    tree_index        INTEGER NOT NULL,
    PRIMARY KEY (root, tree_index)
);
```

**Column types split by what each value actually is, not applied uniformly.** `income`, `portfolio_value`, `financial_sector_months`, `executive_months`, `jurisdiction_code`, `identity_commitment`, `attr_hash`, `leaf`, `value`, `next_value` are BN254 field elements or Poseidon hash outputs — up to ~254 bits, which overflows SQLite's native `INTEGER` (a signed 64-bit type) outright, and would also silently lose precision if read back into a JS `Number` (safe only up to 2^53). `TEXT`, holding a decimal string round-tripped through JS `BigInt`, is the correct representation for these, and matches how every `snarkjs` output file in this project already represents field elements. `tree_index`, `leaf_index`, `next_index`, `issued_epoch`, `expiry_epoch` are different in kind — small counters and tree positions (a depth-20 tree tops out around 2^20), nowhere near either limit. Using `TEXT` for these too wouldn't just be imprecise: `GET /credentials/:holderId/path`'s `ORDER BY tree_index DESC` (below) sorts `TEXT` lexicographically, not numerically, so it would return the wrong "most recent" row as soon as more than nine leaves existed (`'9' > '11'` as strings). `INTEGER` for these five columns avoids that outright rather than relying on query-time care.

**The same risk exists one level up, in `indexedTree.ts`'s splice logic, and needs enforcing in code rather than left implicit.** `credential-protocol.md §5.3` requires locating the leaf whose `value < identity_commitment < nextValue`; that logic reads `value`/`next_value` back from the `TEXT` columns above. Those columns are correctly `TEXT` — but `indexedTree.ts` and `merkleTree.ts` must parse every such value to `BigInt` immediately on read from SQLite and perform every relational comparison (locating the low leaf, maintaining ascending order per §5.3) on the `BigInt` values, never on the raw `TEXT` strings. Comparing the strings directly would reproduce the exact same lexicographic-ordering bug just fixed above, except here it corrupts P6's non-membership guarantee itself — a sanctioned entry could end up bracketed incorrectly, letting a non-membership proof through for someone who shouldn't pass — rather than just returning a stale path on one query. `circuits/credential/test/fixtures.js`'s existing sanctions-list construction (§4.3 below) already gets this right, sorting real `BigInt` values throughout; this note exists because the SQLite round-trip is new in Phase 3 and has no equivalent precedent to inherit from within this codebase.

**`jurisdiction_subset_trees` is what makes `GET /jurisdictions/:root/path/:jurisdictionCode` (§4.1) possible.** `/jurisdictions/approve-subset` builds a tree and hands back its root, but a root alone can't answer a path query later — it's a hash, and reveals nothing about what went into it. Without recording which codes went into which root, at which index, the issuer service would have no way to reconstruct any subset tree after the fact. Rebuilding the exact same `SparseMerkleTree` (same depth, same `hash2`, same `(code, index)` pairs) from these rows reproduces the identical root deterministically, so a path request is just: look up this root's rows, rebuild the tree in memory, call `proof(index)`.

One consequence worth being explicit about, not a blocker: this table grows with the number of *distinct code combinations* ever approved, not with the number of codes themselves — unlike the canonical tree above (one row per code, ever), a new offering requesting a jurisdiction mix nobody's requested before adds a whole new set of rows, retained for as long as any offering might still reference that root. No eviction policy is defined, and nothing here bounds how many distinct combinations could accumulate — in practice this is likely to stay small, since platforms tend to reuse a handful of common allowlists (e.g. "EU only" vs. "all recognized"), but that's an operational expectation, not something enforced.

**`issued_attr_hashes` is what makes test case 22 (§7.5) implementable.** `/credentials/submit` looks up `issued_attr_hashes.attr_hash` for the claimed `holder_id` and compares it against the `attrHash` implied by the submitted leaf-binding proof's public input — if they don't match, the submission is rejected before the proof is even verified, since it's already claiming to be bound to attributes this holder was never issued. Without this table, the service would have no record of what it told each holder, and couldn't distinguish a proof correctly bound to their real `attr_hash` from one bound to an arbitrary fabricated value.

**Why `valid_set_leaves` never deletes a row on revocation, just marks it.** Every other holder's Merkle path depends on *where* leaves sit in the tree (`pathIndices`) — physically removing a row would shift every subsequent index and invalidate every other holder's cached path, not just the revoked one. Revocation sets `leaf = 0` (the same empty/sentinel value unused slots already hold) at the existing index and recomputes the root; the index itself is retired, never reused, matching `credential-protocol.md §6`'s revocation model exactly (a rotation event, not a compaction).

**Re-issuance produces more than one row per `holder_id` — by design, not by accident.** `holder_id` is not the primary key (`tree_index` is), so a holder revoked and later re-issued a fresh credential legitimately gets a second row at a new index; the old row stays, permanently marked `revoked = 1`. `GET /credentials/:holderId/path` must therefore query `WHERE holder_id = ? AND revoked = 0 ORDER BY tree_index DESC LIMIT 1` — the most recent non-revoked row — rather than assuming one row per holder. This is a query-discipline note, not a schema gap: the schema already permits what re-issuance needs.

### 4.3 Why `merkleTree.ts` and `indexedTree.ts` extend, not replace, the Phase 2 test logic

`circuits/credential/test/fixtures.js`'s `SparseMerkleTree` class already implements the zero-hash construction and proof generation this service needs — it was built for one-shot fixture construction (Phase 2 never needed to *update* a tree after building it once). The issuer service needs the same tree shape plus real mutation: `insertLeaf(index, value)` and recomputation after each call, rather than a single `setLeaf` pass followed by one `root()`/`proof()` read. `indexedTree.ts` additionally needs the splice procedure `credential-protocol.md §5.3` and this project's own earlier design walkthrough specify: given a new value, find the leaf whose `(value, nextValue)` range brackets it, write a new leaf inheriting the old `nextValue`/`nextIndex`, and update the old leaf to point at the new one.

---

## 5. F3.4, F3.5 — Epoch & Revocation, Concretely

Per §1's resolved decision (epoch increments on any root change), a revocation's sequence is exactly Flow 4:

1. `POST /revoke` removes the leaf from the in-memory/SQLite-backed tree.
2. The service recomputes the root over the now-updated tree.
3. `chain.ts` calls `EligibilityRegistry.publishValidSetRoot(newRoot)`, which increments `currentEpoch` and stores the new root at that epoch — one new epoch per revocation (and, per §1, per issuance too), keeping "which epoch did this change happen in" unambiguous for later gas/timing analysis.
4. Any subsequent presentation of the revoked credential fails at `OfferingPolicy.presentEligibility`'s recorded-value cross-check — specifically the epoch-freshness check (§3.3): the holder's original proof still names the *old* epoch as its `currentEpoch` public input, but `registry.currentEpoch()` has since moved forward, so `require(publicSignals[epoch] == registry.currentEpoch())` reverts the transaction directly. This is deliberate: the check must compare against the registry's live `currentEpoch()`, never look up `validSetRootAt` indexed by whatever epoch the *proof* claims — the latter would trust a prover-supplied index and let a stale proof pass (§3.3). §7.3 case 15 and §7.4 case 18 test this directly, submitting Alice's literal original proof object unmodified — not a proof regenerated with a bumped epoch, which would silently stop the test from exercising this check at all.

PR-9 ("without holder cooperation") and PR-11 ("revocation SHALL NOT reveal which credential was revoked") both hold by construction here: the holder is never contacted, and the new root reveals nothing about which leaf index changed — same reasoning `credential-protocol.md §8.4` already gives, now backed by a real contract instead of a design intention.

---

## 6. F3.7 — Gas Measurement

**A prediction, stated before measuring rather than discovered after.** Groth16 `verifyProof` gas is dominated by one fixed pairing check plus one scalar multiplication per public input — it does not scale with constraint count the way proving time and `zkey` size do (`BASELINE_RESULTS.md`'s own observations). `circuit_full` has 2.7× `circuit_condab`'s constraints (35,042 vs. 13,117, per `eligibility-circuits.md`'s complexity parameters) but only two more public inputs (6 vs. 4) — so the three `verifyProof` gas numbers below are expected to land within a few thousand gas of each other, *not* to reproduce Phase 2's constraint-count curve on-chain. That's not a null result: it's the measured confirmation that Phase 2's complexity parameters scale *proving cost*, not *verification cost* — proving cost scales with predicates, on-chain verification cost scales with public-input count instead, and having both numbers, not just one, is what makes that contrast a real finding rather than an assumption (relevant to Phase 5's cost-tradeoff framing). The `presentEligibility` − `verifyProof` delta, isolated separately below, is expected to be dominated by `NullifierRegistry`'s `SSTORE` (~20k gas for a zero→nonzero write) plus the handful of cold `SLOAD`s reading `EligibilityRegistry`'s state (`sanctionsRoot`, `validSetRootAt`, `currentEpoch`) — not by the `require` comparisons themselves, which are cheap calldata/stack operations.

Two different things get measured, matched to what each circuit configuration actually is (§3.3):

**`circuit_p1only` and `circuit_condab` — bare `verifyProof` gas, no `OfferingPolicy` involved.** These never present against a real offering (they're Phase 2's complexity-parameter range endpoints), and their 4-element public-signals array is a different, incompatible type from `circuit_full`'s 6-element one (§3.3) — there's no `OfferingPolicy` call to route them through even if there were a reason to. For each: `snarkjs zkey export solidityverifier` against its `_final.zkey` (already built in Phase 2) → deploy the standalone verifier → call `verifyProof` directly with Alice's real proof for that configuration (`circuits/credential/proof_{p1only,condab}.json`) → record gas via `forge test --gas-report`.

**`circuit_full` — both bare `verifyProof` and the full `presentEligibility` call.** Deploy the full stack (`Groth16VerifierFull` + `EligibilityRegistry` + `NullifierRegistry` + `OfferingPolicy`) to a local Anvil instance, register one offering, publish Phase 2's known fixture `validSetRoot` directly via `EligibilityRegistry.publishValidSetRoot` (a hardcoded `bytes32` constant, taken straight from `public_full.json` — no contract in this stack computes Poseidon or derives a root from a leaf; the chain only ever stores and compares roots it's handed, exactly as `credential-protocol.md §7` describes for the issuer service generally), then measure both: `Groth16VerifierFull.verifyProof` alone, and the complete `presentEligibility` call (recorded-value cross-checks + verification + nullifier consumption) using Alice's real proof (`circuits/credential/proof_full.json`). The gap between these two numbers is the actual, measured cost of the cross-checking layer this spec adds — not asserted, read off `forge test --gas-report`.

Results recorded in `contracts/PHASE3_RESULTS.md`, same table format as `PHASE2_RESULTS.md` — a `gas` column added per configuration, extending Phase 2's own complexity-parameter measurement (constraint counts) with the on-chain cost of the same three circuits, plus the separate `presentEligibility` row for `circuit_full` showing the cross-checking overhead explicitly rather than folding it into one combined number.

---

## 7. Test Suite

Three test surfaces, each exercising what only it can exercise — Foundry can't test the issuer service's TypeScript logic, and `node:test` can't cheaply exercise Solidity revert semantics against a real EVM. Integration tests run in Foundry (against a real deployed stack) since that's where "does the whole chain of contracts behave correctly together" actually needs an EVM to answer.

**Fixture proofs.** Foundry can't generate a Groth16 proof — every proof the test matrix uses has to already exist. Two cover everything below, both bound to Alice's real Phase 2 credential (same `holder_secret`, same 9 attributes, same tree state), differing only in `scope`:

- `circuits/credential/proof_full.json` / `public_full.json` (Phase 2 output, already exists) — `scope = 0`, i.e. generated assuming it will be presented to "Offering A." Used by every case in §7.3/§7.4 except case 19's second half.
- `proof_full_offeringB.json` / `public_full_offeringB.json` (new — generated the same way as Phase 2's fixture, `scope` set to `1` instead of `0`, everything else identical). Used only by case 19.

Cases 13, 14, 15, and 18 (jurisdictionRoot/sanctionsRoot/epoch mismatches) need **no new proof at all** — the mismatch is created by registering or publishing a *different* on-chain recorded value against the one fixed `proof_full.json`, not by varying the proof's own public inputs. Case 12 (cross-offering scope mismatch) is the same: it presents `proof_full.json` (baked-in `scope = 0`) to a *different*, legitimately-registered offering, so it needs no second proof either — only case 19 needs a proof that's *validly* bound to a second offering, since it must actually succeed there. This means the test suite must register offerings in a specific, deterministic order: "Offering A" registered first (receiving `offeringId = 0`, matching `proof_full.json`'s baked-in `scope`) and "Offering B" second (receiving `offeringId = 1`, matching `proof_full_offeringB.json`'s). `OfferingPolicy.nextOfferingId`'s sequential counter makes this automatic as long as the registration order in the test matches the order assumed when the fixtures were generated — case 19's test must register in that exact order.

### 7.1 `EligibilityRegistry` (Foundry, `contracts/test/EligibilityRegistry.t.sol`)

| # | Case | Expected |
| --- | --- | --- |
| 1 | Non-issuer calls `publishValidSetRoot` | reverts |
| 2 | Non-issuer calls `publishSanctionsRoot` | reverts |
| 3 | Issuer publishes a validSetRoot | `currentEpoch` increments by exactly 1; `validSetRootAt[currentEpoch]` equals the new root |
| 4 | Issuer publishes two validSetRoots in sequence | both are retrievable at their respective epochs — `validSetRootAt[1]` and `validSetRootAt[2]` both correct, old one not overwritten |
| 5 | Issuer publishes a sanctionsRoot | `sanctionsRoot()` returns the new value; no epoch change |
| 5b | Non-issuer calls `approveJurisdictionRoot` | reverts |
| 5c | Issuer approves a jurisdictionRoot | `approvedJurisdictionRoots(root)` returns `true`; a second, different root the issuer never approved still returns `false` |

### 7.2 `NullifierRegistry` (Foundry, `contracts/test/NullifierRegistry.t.sol`)

Deployed standalone (not through `OfferingPolicy`) for these unit tests, so the test contract calls `setAuthorized(address(this))` once in `setUp()` before exercising `consumeIfUnused` directly — exactly the one-time wiring §3.2 describes, just with the test contract standing in for `OfferingPolicy`.

| # | Case | Expected |
| --- | --- | --- |
| 6 | Fresh nullifier, called by the authorized address | `consumeIfUnused` succeeds, `consumed[n]` becomes true |
| 7 | Same nullifier submitted twice | second call reverts (TR-13, PR-7 — the core replay-rejection requirement) |
| 8 | Two distinct nullifiers | both succeed independently, no false collision |
| 8b | A non-authorized address calls `consumeIfUnused` | reverts — confirms the access-control gate from §3.2 |
| 8c | `setAuthorized` called a second time (by anyone, including the original caller) | reverts — the one-time-set invariant holds |
| 8d | A non-deployer address calls `setAuthorized` before the real deployer does | reverts — confirms `setAuthorized` is gated to `deployer` (§3.2): without this, whoever calls first wins regardless of who deployed the contract |

### 7.3 `OfferingPolicy` (Foundry, `contracts/test/OfferingPolicy.t.sol`)

Uses Alice's real fixture proofs for `circuit_full` (`proof_full.json`/`public_full.json` and `proof_full_offeringB.json`/`public_full_offeringB.json` — see the Fixtures note above) as the base cases, exactly as `Groth16Verifier.t.sol` reused real Phase 1 fixture data rather than mocking a proof. `setUp()` must call `registry.approveJurisdictionRoot(...)` with the exact `jurisdictionRoot` baked into each fixture proof's public signals *before* registering any offering against it — `registerOffering` now rejects anything the issuer hasn't approved (§3.1/§3.3), so an un-approved fixture root would fail registration before any of the cases below ever run.

| # | Case | Expected |
| --- | --- | --- |
| 9 | Non-platform calls `registerOffering` | reverts |
| 9b | Platform calls `registerOffering` with a `jurisdictionRoot` the issuer never approved | reverts — confirms the issuer-approval gate (§3.1/§3.3), tested at the point a platform would actually hit it |
| 10 | Alice's genuine proof, correct offering, all roots and epoch current | `presentEligibility` returns `true`; nullifier now consumed |
| 11 | Same call submitted a second time | reverts at the nullifier check — TR-13 enforced end-to-end, not just at the `NullifierRegistry` unit level |
| 12 | Alice's genuine `proof_full.json` (baked-in `scope = 0`, i.e. Offering A) submitted against a *different*, legitimately-registered Offering B (`offeringId = 1`) | reverts at the recorded-value `scope` check (`publicSignals[5] == offeringId`), **before** `verifyProof` runs — no second proof needed, since the mismatch is between the proof's fixed scope and the offering it's presented to, not anything about the proof itself. This is the exact scope-tampering fix `credential-protocol.md §5.4`/§7 exists for, tested end-to-end for the first time |
| 13 | Alice's genuine proof, but the offering's registered `jurisdictionRoot` doesn't match the proof's | reverts at the recorded-value `jurisdictionRoot` check |
| 14 | Alice's genuine proof, but `EligibilityRegistry.sanctionsRoot` has since changed (simulate a new sanctions entry added after the proof was generated) | reverts at the recorded-value `sanctionsRoot` check — the gap this spec closes (§3.3), verified end-to-end |
| 15 | Alice's genuine, *unmodified* original proof, submitted after a revocation has advanced `registry.currentEpoch()` past the epoch the proof names | reverts at the recorded-value **epoch-freshness** check (`publicSignals[4] == registry.currentEpoch()`, §3.3) — the proof must be the literal original object, not regenerated with a bumped epoch, or this test would silently stop exercising the check at all |
| 16 | A tampered proof (flip one byte of `pA`), otherwise-correct public signals | reverts at `verifyProof` (cryptographic binding) — confirms recorded-value checks passing doesn't substitute for real cryptographic verification |

### 7.4 Full-stack integration (Foundry, `contracts/test/Integration.t.sol`)

Deploys the entire stack (all four contracts) fresh, matching the real deployment sequence Phase 3 will actually use.

| # | Case | Expected |
| --- | --- | --- |
| 17 | Publish Phase 2's known fixture `validSetRoot` as a hardcoded constant (no contract here computes Poseidon or derives a root from a leaf — see §6), register Alice's offering, present her real proof | access granted — the full happy path, D2's first acceptance line ("an issued credential verifies on-chain") |
| 18 | Simulate Alice's revocation by publishing a second, different hardcoded `validSetRoot` via `EligibilityRegistry.publishValidSetRoot` (no on-chain leaf removal or Poseidon computation — same reasoning as case 17, §6), then present her *original*, unmodified `proof_full.json` again (not a regenerated one — see the Fixtures note) | rejected — D2's second acceptance line ("after revocation and epoch rotation the same credential fails"), exercised through the real epoch-bump → stale-epoch-rejection chain (§3.3, §5 step 4), not each piece tested in isolation |
| 19 | Register Offering A then Offering B in that order (so `offeringId` 0/1 match the fixtures' baked-in `scope`), present `proof_full.json` to Offering A, then present `proof_full_offeringB.json` (same credential, legitimately different `scope`, hence a different `nullifier`) to Offering B | both succeed independently — confirms the cross-offering rejection (case 12) isn't accidentally blocking legitimate multi-offering use, only mismatched submissions |

### 7.5 Issuer service (`node:test`, `issuer-service/test/*.test.ts`)

| # | Case | Expected |
| --- | --- | --- |
| 20 | `POST /credentials/request` for a known holder | returns the 9 attributes and a correctly-computed `attrHash` matching an independently-computed `Poseidon(9 attributes)` |
| 21 | `POST /credentials/submit` with a valid leaf-binding proof | accepted; the resulting on-chain root (simulated/mocked chain call in this unit-level test) matches an independently-recomputed tree root |
| 22 | `POST /credentials/submit` with a leaf-binding proof built against a *different* `attrHash* than what was issued | rejected — mirrors `leaf_binding.circom`'s own test (Phase 2) but at the service layer, confirming the service actually enforces the check rather than trusting the client |
| 23 | `GET /credentials/:id/path` immediately after issuance | returns a path that validates against the just-published root |
| 24 | `POST /revoke`, then `GET /credentials/:id/path` for the revoked holder | the tree no longer contains that leaf; a fresh path request for it returns not-found or the empty-slot path, not a stale valid one |
| 25 | `POST /sanctions/add` for a new `identityCommitment`, then a non-membership check for a value now bracketed by the new entry | correctly fails non-membership (the new entry is real, the tree wasn't just re-fixtured) — this is the dynamic-insertion decision (§1) verified concretely, not just implemented |
| 26 | `POST /sanctions/add` twice, then a non-membership check for a value between the two newly-added entries | correctly fails — confirms the splice procedure maintains adjacency correctly after *multiple* insertions, not just one |
| 27 | Restart the service process, then `GET /credentials/:id/path` for a holder issued before the restart | still returns a correct, current path — SQLite persistence actually persists, not just an in-memory convenience |
| 28 | `POST /jurisdictions/add` for a new code, then `POST /jurisdictions/approve-subset` requesting exactly that code | succeeds, calls `EligibilityRegistry.approveJurisdictionRoot` with the resulting subset root |
| 29 | `POST /jurisdictions/approve-subset` requesting a code never added to the canonical tree | rejected — confirms the "each requested code is actually present in the canonical tree" check (§4.1) is real, not just described |
| 30 | `GET /jurisdictions/:root/path/:jurisdictionCode` for a code genuinely in that approved subset | returns a path that validates against `:root` |
| 31 | `GET /jurisdictions/:root/path/:jurisdictionCode` for a code *not* in that subset (but present in the canonical tree, or in a different subset) | `404` — confirms a holder outside this offering's approved set gets no path, not a stale or wrong one |

### 7.6 What's deliberately not tested here

Gas measurement (§6) is a measurement pass, not a pass/fail test — it has no row in this matrix, the same way Phase 2's constraint counts weren't part of its 41-case test suite either. Platform-backend and holder-app behavior (presentation-request generation, QR flow, consent UI) are Phase 4 scope — this suite tests the contracts and issuer service Phase 3 actually delivers, not the parts of Flow 2 that live in front of them.

---

## 8. Toolchain Additions

- `issuer-service/package.json`: `better-sqlite3` (synchronous SQLite, no separate driver process — matches "runs entirely locally," TR-20) and `viem` (chain interaction, per `PRD.md §9.2`'s already-stated choice). No test framework dependency — `node:test` is built into Node 22 LTS (already pinned, `TOOLCHAIN.md §2`), verified on this project's exact pinned version (`v22.23.2`) to run `.ts` test files directly with zero flags or build step.
- No new contracts tooling — Foundry, already pinned (`TOOLCHAIN.md §3`), covers everything in §7.1–7.4.

---

## 9. Acceptance Mapping

| Requirement | Satisfied by |
| --- | --- |
| F3.1 | §3.1–3.2 — `EligibilityRegistry` and `NullifierRegistry`, tested in §7.1–7.2 |
| F3.2 | §3.2 `NullifierRegistry.consumeIfUnused`, tested in §7.2 case 7 and §7.3 case 11 |
| F3.3 | §4 — issuer service HTTP surface, access control per L10 (both leaf insertion and root publication gated to the issuer's address, §3.1/§4.1) |
| F3.4 | §4.1 (`/revoke`, `/sanctions/add`, `/jurisdictions/add`, `/jurisdictions/approve-subset`, `/jurisdictions/:root/path/:jurisdictionCode`), §5 — epoch rotation and tree maintenance, tested in §7.5 cases 24–26, 28–31 |
| F3.5 | §5 — revocation causes failure from the following epoch without holder cooperation, tested end-to-end in §7.4 case 18 |
| F3.6 | §3.3 `OfferingPolicy.presentEligibility`'s recorded-value cross-checks, tested in §7.3 cases 12–15; `jurisdictionRoot`'s issuer-approval gate at registration (§3.1/§3.3) tested in §7.1 cases 5b–5c and §7.3 case 9b |
| F3.7 | §6 — gas measurement across all three circuit configurations, recorded in `contracts/PHASE3_RESULTS.md` |
| D2 deliverable | All of the above — deployed contracts (§2–3), working issuer service (§4–5), gas measurements (§6), full test suite (§7) |
