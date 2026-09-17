// Generates input_full_offeringB.json - identical to Alice's real input_full.json
// except scope = SCOPE_OFFERING_B (1) instead of SCOPE (0), for Phase 3's
// verification-infrastructure.md §7 test case 19 (a second, legitimately
// different offering using the same credential).
const fs = require("fs");
const path = require("path");
const { buildFixtures } = require("./test/fixtures");

function stringify(obj) {
    return JSON.parse(
        JSON.stringify(obj, (_k, v) => {
            if (typeof v === "bigint") return v.toString();
            if (Array.isArray(v)) return v.map((x) => (typeof x === "bigint" ? x.toString() : x));
            return v;
        })
    );
}

async function main() {
    const fixtures = await buildFixtures();
    const alice = fixtures.ALICE;

    const fullInputOfferingB = {
        income: alice.attrs.income,
        portfolio_value: alice.attrs.portfolio_value,
        financial_sector_months: alice.attrs.financial_sector_months,
        executive_months: alice.attrs.executive_months,
        jurisdiction_code: alice.attrs.jurisdiction_code,
        identity_commitment: alice.attrs.identity_commitment,
        issued_epoch: alice.attrs.issued_epoch,
        expiry_epoch: alice.attrs.expiry_epoch,
        schema_version: alice.attrs.schema_version,
        holder_secret: alice.holder_secret,
        jurisdictionPathElements: alice.jurisdictionProof.pathElements,
        jurisdictionPathIndices: alice.jurisdictionProof.pathIndices,
        jurisdictionRoot: fixtures.JURISDICTION_ROOT,
        sanctionsValue: alice.sanctionsProof.value,
        sanctionsNextValue: alice.sanctionsProof.nextValue,
        sanctionsNextIndex: alice.sanctionsProof.nextIndex,
        sanctionsPathElements: alice.sanctionsProof.pathElements,
        sanctionsPathIndices: alice.sanctionsProof.pathIndices,
        sanctionsRoot: fixtures.SANCTIONS_ROOT,
        validSetPathElements: alice.merkleProof.pathElements,
        validSetPathIndices: alice.merkleProof.pathIndices,
        validSetRoot: fixtures.VALID_SET_ROOT,
        currentEpoch: fixtures.CURRENT_EPOCH,
        scope: fixtures.SCOPE_OFFERING_B,
    };

    fs.writeFileSync(
        path.join(__dirname, "input_full_offeringB.json"),
        JSON.stringify(stringify(fullInputOfferingB), null, 2)
    );
    console.log("wrote input_full_offeringB.json");
}

main();
