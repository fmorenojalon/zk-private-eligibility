const path = require("path");
const assert = require("assert");
const wasm_tester = require("circom_tester").wasm;
const { buildFixtures } = require("./fixtures");

const CREDENTIAL_DIR = path.join(__dirname, "..");

// Sub-phase 1 (specs/phase-2/eligibility-circuits.md §2): isolated tests
// for range_predicates.circom and threshold.circom, before any composite
// circuit exists. circom_tester auto-generates the `component main`
// wrapper for a named template when the target file has none - no
// separate wrapper .circom files needed.
async function testerFor(file, templateName, templateParams) {
    return wasm_tester(path.join(CREDENTIAL_DIR, file), {
        templateName,
        templateParams,
    });
}

describe("range_predicates.circom", function () {
    this.timeout(60000);

    describe("RangeGte(64) - P1 (income >= 60000), P7 (expiry_epoch >= currentEpoch) shape", () => {
        let circuit;
        before(async () => {
            circuit = await testerFor("range_predicates.circom", "RangeGte", [64]);
        });

        it("value above threshold: out = 1", async () => {
            const w = await circuit.calculateWitness({ value: 70000, threshold: 60000 });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 1 });
        });

        it("value exactly at threshold (boundary, inclusive): out = 1", async () => {
            const w = await circuit.calculateWitness({ value: 60000, threshold: 60000 });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 1 });
        });

        it("value one below threshold (boundary - 1): out = 0", async () => {
            const w = await circuit.calculateWitness({ value: 59999, threshold: 60000 });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 0 });
        });
    });

    describe("RangeGt(64) - P2 (portfolio_value > 100000), strict", () => {
        let circuit;
        before(async () => {
            circuit = await testerFor("range_predicates.circom", "RangeGt", [64]);
        });

        it("value above threshold: out = 1", async () => {
            const w = await circuit.calculateWitness({ value: 150000, threshold: 100000 });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 1 });
        });

        it("value exactly at threshold (boundary, strict - must reject): out = 0", async () => {
            const w = await circuit.calculateWitness({ value: 100000, threshold: 100000 });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 0 });
        });

        it("value one above threshold (boundary + 1): out = 1", async () => {
            const w = await circuit.calculateWitness({ value: 100001, threshold: 100000 });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 1 });
        });
    });
});

describe("threshold.circom", function () {
    this.timeout(60000);

    describe("ThresholdOfN(2, 2) - the actual EU regime configuration", () => {
        let circuit;
        before(async () => {
            circuit = await testerFor("threshold.circom", "ThresholdOfN", [2, 2]);
        });

        it("2-of-2 true: out = 1", async () => {
            const w = await circuit.calculateWitness({ conditions: [1, 1] });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 1 });
        });

        it("1-of-2 true: out = 0", async () => {
            const w = await circuit.calculateWitness({ conditions: [1, 0] });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 0 });
        });

        it("0-of-2 true: out = 0", async () => {
            const w = await circuit.calculateWitness({ conditions: [0, 0] });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 0 });
        });
    });

    // Test matrix case 14 (specs/phase-2/eligibility-circuits.md §7):
    // substantiates the PRD's genericity claim (post-MVP extension #7)
    // that reinstating a third condition is a configuration change
    // (N=3), not a redesign - this is the demonstration, not just the
    // assertion.
    describe("ThresholdOfN(2, 3) - genericity claim (PRD post-MVP extension #7)", () => {
        let circuit;
        before(async () => {
            circuit = await testerFor("threshold.circom", "ThresholdOfN", [2, 3]);
        });

        it("3-of-3 true: out = 1", async () => {
            const w = await circuit.calculateWitness({ conditions: [1, 1, 1] });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 1 });
        });

        it("2-of-3 true: out = 1", async () => {
            const w = await circuit.calculateWitness({ conditions: [1, 1, 0] });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 1 });
        });

        it("1-of-3 true: out = 0", async () => {
            const w = await circuit.calculateWitness({ conditions: [1, 0, 0] });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 0 });
        });

        it("0-of-3 true: out = 0", async () => {
            const w = await circuit.calculateWitness({ conditions: [0, 0, 0] });
            await circuit.checkConstraints(w);
            await circuit.assertOut(w, { out: 0 });
        });
    });
});

// Sub-phase 2 (specs/phase-2/eligibility-circuits.md §5): the first
// composite circuit - condA (P1 v P2) plus the always-structural
// P7/P8/P10. Test matrix cases 15-16.
describe("circuit_p1only.circom", function () {
    this.timeout(60000);

    let fixtures;
    let circuit;

    before(async () => {
        fixtures = await buildFixtures();
        circuit = await wasm_tester(path.join(CREDENTIAL_DIR, "circuit_p1only.circom"));
    });

    function inputFor(person) {
        return {
            income: person.attrs.income,
            portfolio_value: person.attrs.portfolio_value,
            financial_sector_months: person.attrs.financial_sector_months,
            executive_months: person.attrs.executive_months,
            jurisdiction_code: person.attrs.jurisdiction_code,
            identity_commitment: person.attrs.identity_commitment,
            issued_epoch: person.attrs.issued_epoch,
            expiry_epoch: person.attrs.expiry_epoch,
            schema_version: person.attrs.schema_version,
            holder_secret: person.holder_secret,
            pathElements: person.merkleProof.pathElements,
            pathIndices: person.merkleProof.pathIndices,
            currentEpoch: fixtures.CURRENT_EPOCH,
            validSetRoot: fixtures.VALID_SET_ROOT,
            scope: fixtures.SCOPE,
        };
    }

    // Case 15: Alice qualifies on income alone (condA = P1 v P2).
    it("Alice: witness exists, nullifier is deterministic Poseidon(holder_secret, currentEpoch, scope)", async () => {
        const input = inputFor(fixtures.ALICE);
        const w = await circuit.calculateWitness(input);
        await circuit.checkConstraints(w);

        const expectedNullifier = fixtures.hash3(
            fixtures.ALICE.holder_secret,
            fixtures.CURRENT_EPOCH,
            fixtures.SCOPE
        );
        await circuit.assertOut(w, { nullifier: expectedNullifier });
    });

    // Case 16: Bob fails condA (income and portfolio both below threshold) -
    // no valid witness exists, per PR-4's all-or-nothing mechanism.
    it("Bob: calculateWitness throws (condA fails)", async () => {
        const input = inputFor(fixtures.BOB);
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    it("Alice, wrong holder_secret: calculateWitness throws (leaf doesn't match Merkle path)", async () => {
        const input = inputFor(fixtures.ALICE);
        input.holder_secret = fixtures.ALICE.holder_secret + 1n;
        await assert.rejects(() => circuit.calculateWitness(input));
    });
});

// Sub-phase 3 (specs/phase-2/eligibility-circuits.md §4, P6): the one
// genuinely new construction, tested standalone before any composite
// circuit wires it in - no `=== 1` self-enforcement here, matching
// range_predicates.circom's convention of outputting a boolean and
// letting the caller decide whether to force it.
describe("indexed_nonmembership.circom", function () {
    this.timeout(60000);

    let fixtures;
    let circuit;

    before(async () => {
        fixtures = await buildFixtures();
        circuit = await wasm_tester(path.join(CREDENTIAL_DIR, "indexed_nonmembership.circom"), {
            templateName: "IndexedNonMembership",
            templateParams: [fixtures.DEPTH],
        });
    });

    function withRoot(fixtures, proof) {
        return { ...proof, sanctionsRoot: fixtures.SANCTIONS_ROOT };
    }

    it("genuine non-member (Alice's identity_commitment, not sanctioned): out = 1", async () => {
        const proof = fixtures.sanctionsProofFor(fixtures.ALICE.attrs.identity_commitment);
        const w = await circuit.calculateWitness(withRoot(fixtures, proof));
        await circuit.checkConstraints(w);
        await circuit.assertOut(w, { out: 1 });
    });

    it("actual sanctioned value, using its own predecessor leaf: out = 0 (highBound fails)", async () => {
        // The predecessor leaf legitimately brackets values strictly
        // below the sanctioned entry - feeding the sanctioned value
        // itself as identityCommitment makes identityCommitment ==
        // nextValue, failing the strict upper bound. This is the
        // property the whole construction exists to enforce: you
        // cannot claim non-membership for a value that actually is one.
        const sanctionedValue = fixtures.sortedSanctionedValues[3];
        const justBelowIt = fixtures.sortedSanctionedValues[2] + 1n; // brackets to the same leaf sanctionedValue's predecessor owns
        const predecessorProof = fixtures.sanctionsProofFor(justBelowIt);
        const forgedInput = withRoot(fixtures, { ...predecessorProof, identityCommitment: sanctionedValue });
        const w = await circuit.calculateWitness(forgedInput);
        await circuit.checkConstraints(w);
        await circuit.assertOut(w, { out: 0 });
    });

    it("tampered nextValue not matching the tree: out = 0 (Merkle inclusion fails)", async () => {
        const proof = fixtures.sanctionsProofFor(fixtures.ALICE.attrs.identity_commitment);
        const forgedInput = withRoot(fixtures, { ...proof, nextValue: proof.nextValue + 1n });
        const w = await circuit.calculateWitness(forgedInput);
        await circuit.checkConstraints(w);
        await circuit.assertOut(w, { out: 0 });
    });
});

// Sub-phase 4a (specs/phase-2/eligibility-circuits.md §5): the complexity-
// dial midpoint - full P1-P4, no P5/P6. Test matrix cases 17-18.
describe("circuit_condab.circom", function () {
    this.timeout(60000);

    let fixtures;
    let circuit;

    before(async () => {
        fixtures = await buildFixtures();
        circuit = await wasm_tester(path.join(CREDENTIAL_DIR, "circuit_condab.circom"));
    });

    function inputFor(person) {
        return {
            income: person.attrs.income,
            portfolio_value: person.attrs.portfolio_value,
            financial_sector_months: person.attrs.financial_sector_months,
            executive_months: person.attrs.executive_months,
            jurisdiction_code: person.attrs.jurisdiction_code,
            identity_commitment: person.attrs.identity_commitment,
            issued_epoch: person.attrs.issued_epoch,
            expiry_epoch: person.attrs.expiry_epoch,
            schema_version: person.attrs.schema_version,
            holder_secret: person.holder_secret,
            pathElements: person.merkleProof.pathElements,
            pathIndices: person.merkleProof.pathIndices,
            currentEpoch: fixtures.CURRENT_EPOCH,
            validSetRoot: fixtures.VALID_SET_ROOT,
            scope: fixtures.SCOPE,
        };
    }

    // Case 17: Alice qualifies on both condA and condB (full 2-of-2).
    it("Alice: witness exists (full P1-P4, no jurisdiction/sanctions checked)", async () => {
        const w = await circuit.calculateWitness(inputFor(fixtures.ALICE));
        await circuit.checkConstraints(w);
    });

    // Case 18: Bob fails condA (and condB) - P4 has no valid witness.
    it("Bob: calculateWitness throws (condA fails)", async () => {
        await assert.rejects(() => circuit.calculateWitness(inputFor(fixtures.BOB)));
    });
});

// Sub-phase 4b (specs/phase-2/eligibility-circuits.md §5): the complexity-
// dial maximum - the full EU 2-of-2 regime, P1-P8 and P10 (P9 retired).
// Test matrix cases 1-13, 19-21 run against this circuit.
describe("circuit_full.circom", function () {
    this.timeout(60000);

    let fixtures;
    let circuit;

    before(async () => {
        fixtures = await buildFixtures();
        circuit = await wasm_tester(path.join(CREDENTIAL_DIR, "circuit_full.circom"));
    });

    // Any attribute change changes attr_hash, which changes `leaf`, which
    // invalidates a Merkle proof computed for the OLD leaf - P8 would then
    // fail first and mask whatever predicate a test actually means to
    // isolate. presentAs() rebuilds the valid-set tree/proof around the
    // overridden attributes every time, so P8 stays correctly satisfied
    // unless a test is deliberately about P8 itself (case 6, 8).
    function presentAs(person, { attrs: attrOverrides = {}, sanctions: sanctionsOverride, ...otherOverrides } = {}) {
        const newAttrs = { ...person.attrs, ...attrOverrides };
        const newLeaf = fixtures.leafOf(person.holder_secret, newAttrs);

        const tree = new fixtures.SparseMerkleTree(fixtures.DEPTH, fixtures.hash2);
        tree.setLeaf(fixtures.ALICE.merkleIndex, person === fixtures.ALICE ? newLeaf : fixtures.ALICE.leaf);
        tree.setLeaf(fixtures.BOB.merkleIndex, person === fixtures.BOB ? newLeaf : fixtures.BOB.leaf);
        const validSetProof = tree.proof(person.merkleIndex);
        const validSetRoot = tree.root();

        const sanctionsProof = sanctionsOverride ?? person.sanctionsProof;

        return {
            income: newAttrs.income,
            portfolio_value: newAttrs.portfolio_value,
            financial_sector_months: newAttrs.financial_sector_months,
            executive_months: newAttrs.executive_months,
            jurisdiction_code: newAttrs.jurisdiction_code,
            identity_commitment: newAttrs.identity_commitment,
            issued_epoch: newAttrs.issued_epoch,
            expiry_epoch: newAttrs.expiry_epoch,
            schema_version: newAttrs.schema_version,
            holder_secret: person.holder_secret,
            jurisdictionPathElements: person.jurisdictionProof.pathElements,
            jurisdictionPathIndices: person.jurisdictionProof.pathIndices,
            jurisdictionRoot: fixtures.JURISDICTION_ROOT,
            sanctionsValue: sanctionsProof.value,
            sanctionsNextValue: sanctionsProof.nextValue,
            sanctionsNextIndex: sanctionsProof.nextIndex,
            sanctionsPathElements: sanctionsProof.pathElements,
            sanctionsPathIndices: sanctionsProof.pathIndices,
            sanctionsRoot: fixtures.SANCTIONS_ROOT,
            validSetPathElements: validSetProof.pathElements,
            validSetPathIndices: validSetProof.pathIndices,
            validSetRoot,
            currentEpoch: fixtures.CURRENT_EPOCH,
            scope: fixtures.SCOPE,
            ...otherOverrides,
        };
    }

    // Case 1: Alice qualifies on every predicate.
    it("Alice, full regime, all real values: witness exists, all predicates true", async () => {
        const input = presentAs(fixtures.ALICE);
        const w = await circuit.calculateWitness(input);
        await circuit.checkConstraints(w);
        const expectedNullifier = fixtures.hash3(
            fixtures.ALICE.holder_secret,
            fixtures.CURRENT_EPOCH,
            fixtures.SCOPE
        );
        await circuit.assertOut(w, { nullifier: expectedNullifier });
    });

    // Case 2: Bob fails condA (and condB).
    it("Bob, full regime: calculateWitness throws (condA fails)", async () => {
        await assert.rejects(() => circuit.calculateWitness(presentAs(fixtures.BOB)));
    });

    // Cases 3-4: P1 boundary (income), inclusive >=. Portfolio is dropped
    // below P2's own threshold in both, so condA's result depends entirely
    // on P1 - otherwise Alice's baseline portfolio (>€100,000) would keep
    // condA true via P2 regardless of what P1 does, masking either
    // direction of a P1 bug.
    it("Alice, income exactly €60,000 (boundary): witness exists", async () => {
        const input = presentAs(fixtures.ALICE, { attrs: { income: 60000n, portfolio_value: 50000n } });
        const w = await circuit.calculateWitness(input);
        await circuit.checkConstraints(w);
    });

    it("Alice, income €59,999 (boundary - 1): calculateWitness throws", async () => {
        const input = presentAs(fixtures.ALICE, { attrs: { income: 59999n, portfolio_value: 50000n } });
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Case 5: wrong holder_secret - leaf no longer matches the Merkle path
    // (presentAs rebuilds the tree around the REAL holder_secret's leaf,
    // then this overrides only the input's own holder_secret afterward -
    // the mismatch is exactly what's under test).
    it("Alice, wrong holder_secret: calculateWitness throws", async () => {
        const input = presentAs(fixtures.ALICE, { holder_secret: fixtures.ALICE.holder_secret + 1n });
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Case 6: tampered Merkle path (wrong sibling) for the valid-set proof.
    it("Alice, tampered Merkle path (wrong sibling): calculateWitness throws", async () => {
        const input = presentAs(fixtures.ALICE);
        input.validSetPathElements = [...input.validSetPathElements];
        input.validSetPathElements[0] = input.validSetPathElements[0] + 1n;
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Case 7: expired credential (P7).
    it("Alice, expiry_epoch < currentEpoch: calculateWitness throws (P7)", async () => {
        const input = presentAs(fixtures.ALICE, { attrs: { expiry_epoch: fixtures.CURRENT_EPOCH - 1n } });
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Case 21: P7 boundary, inclusive >=.
    it("Alice, expiry_epoch exactly equal to currentEpoch (boundary): witness exists", async () => {
        const input = presentAs(fixtures.ALICE, { attrs: { expiry_epoch: fixtures.CURRENT_EPOCH } });
        const w = await circuit.calculateWitness(input);
        await circuit.checkConstraints(w);
    });

    // Case 8: revoked credential - old root supplied after removal.
    it("Alice's leaf removed from tree (revoked), old root supplied: calculateWitness throws (P8)", async () => {
        const revokedTree = new fixtures.SparseMerkleTree(fixtures.DEPTH, fixtures.hash2);
        revokedTree.setLeaf(fixtures.BOB.merkleIndex, fixtures.BOB.leaf); // Alice's leaf removed
        const input = presentAs(fixtures.ALICE);
        input.validSetRoot = revokedTree.root(); // the new, current root
        // Alice's path/root pairing is now stale - her leaf isn't in the
        // tree this root commits to.
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Case 9: identity_commitment present in sanctionsRoot (P6). Overriding
    // identity_commitment via presentAs keeps P8 correctly satisfied (the
    // valid-set tree is rebuilt around it); the forged sanctions proof is
    // what makes P6 - and only P6 - fail.
    it("Alice's identity_commitment present in sanctionsRoot: calculateWitness throws (P6)", async () => {
        const sanctionedValue = fixtures.sortedSanctionedValues[0];
        const justBelowIt = 1n; // sentinel leaf brackets (0, sortedSanctionedValues[0]) - 0 itself is the sentinel's own value, not a valid bracket target
        const forgedProof = fixtures.sanctionsProofFor(justBelowIt);
        const input = presentAs(fixtures.ALICE, {
            attrs: { identity_commitment: sanctionedValue },
            sanctions: forgedProof,
        });
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Case 10: jurisdiction_code not in jurisdictionRoot (P5). Overriding
    // jurisdiction_code via presentAs keeps P8 satisfied; the ORIGINAL
    // jurisdiction proof (still tied to the old code, now mismatched) is
    // what makes P5 - and only P5 - fail.
    it("Alice, jurisdiction_code not in jurisdictionRoot: calculateWitness throws (P5)", async () => {
        const input = presentAs(fixtures.ALICE, { attrs: { jurisdiction_code: 999n } });
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Cases 11-13: nullifier behavior.
    it("Alice presents twice to the same scope/epoch: same nullifier both times", async () => {
        const input = presentAs(fixtures.ALICE);
        const w1 = await circuit.calculateWitness(input);
        const w2 = await circuit.calculateWitness(input);
        const expectedNullifier = fixtures.hash3(fixtures.ALICE.holder_secret, fixtures.CURRENT_EPOCH, fixtures.SCOPE);
        await circuit.assertOut(w1, { nullifier: expectedNullifier });
        await circuit.assertOut(w2, { nullifier: expectedNullifier });
    });

    it("Alice and Bob, same scope/epoch: distinct nullifiers", async () => {
        const wAlice = await circuit.calculateWitness(presentAs(fixtures.ALICE));
        // Bob fails eligibility (case 2), so his own witness can't be
        // computed through the full circuit - the independence property
        // itself is a pure function of holder_secret and is checked
        // directly here rather than via a second full-circuit run.
        const otherNullifier = fixtures.hash3(fixtures.BOB.holder_secret, fixtures.CURRENT_EPOCH, fixtures.SCOPE);
        const aliceNullifier = fixtures.hash3(fixtures.ALICE.holder_secret, fixtures.CURRENT_EPOCH, fixtures.SCOPE);
        assert.notStrictEqual(aliceNullifier, otherNullifier);
        await circuit.assertOut(wAlice, { nullifier: aliceNullifier });
    });

    it("Alice, same holder_secret and epoch, two different scopes: unrelated nullifiers", async () => {
        const input = presentAs(fixtures.ALICE);
        const otherScope = fixtures.hash2(222n, 0n);
        const w1 = await circuit.calculateWitness(input);
        input.scope = otherScope;
        const w2 = await circuit.calculateWitness(input);

        const n1 = fixtures.hash3(fixtures.ALICE.holder_secret, fixtures.CURRENT_EPOCH, fixtures.SCOPE);
        const n2 = fixtures.hash3(fixtures.ALICE.holder_secret, fixtures.CURRENT_EPOCH, otherScope);
        assert.notStrictEqual(n1, n2);
        await circuit.assertOut(w1, { nullifier: n1 });
        await circuit.assertOut(w2, { nullifier: n2 });
    });

    // Case 19: P2 boundary, strict >, isolated from P1 by dropping income.
    it("Alice, income below P1 and portfolio exactly €100,000 (P2 boundary): calculateWitness throws", async () => {
        const input = presentAs(fixtures.ALICE, { attrs: { income: 30000n, portfolio_value: 100000n } });
        await assert.rejects(() => circuit.calculateWitness(input));
    });

    // Case 20: P3 boundary, inclusive >=.
    it("Alice, financial_sector_months exactly 12, executive_months 0 (P3 boundary): witness exists", async () => {
        const input = presentAs(fixtures.ALICE, { attrs: { financial_sector_months: 12n, executive_months: 0n } });
        const w = await circuit.calculateWitness(input);
        await circuit.checkConstraints(w);
    });
});
