// Generates input_p1only.json, input_condab.json, input_full.json for
// Alice's eligible fixture, matching each circuit's exact signal names -
// specs/phase-2/eligibility-circuits.md §7's end-to-end proof validation
// (PHASE2_RESULTS.md). BigInts are stringified since JSON has no bigint
// type, matching merkle-baseline/eddsa-baseline's gen_input.js convention.
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

    const p1onlyInput = {
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
        pathElements: alice.merkleProof.pathElements,
        pathIndices: alice.merkleProof.pathIndices,
        currentEpoch: fixtures.CURRENT_EPOCH,
        validSetRoot: fixtures.VALID_SET_ROOT,
        scope: fixtures.SCOPE,
    };

    // Identical shape to p1only - circuit_condab.circom declares the same
    // signals.
    const condabInput = { ...p1onlyInput };

    const fullInput = {
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
        scope: fixtures.SCOPE,
    };

    const outputs = {
        "input_p1only.json": p1onlyInput,
        "input_condab.json": condabInput,
        "input_full.json": fullInput,
    };

    for (const [filename, data] of Object.entries(outputs)) {
        fs.writeFileSync(path.join(__dirname, filename), JSON.stringify(stringify(data), null, 2));
        console.log(`wrote ${filename}`);
    }
}

main();
