// Generates input_full_epoch6.json - identical to Alice's real input_full.json
// except currentEpoch = CURRENT_EPOCH + 1 (6 instead of 5), everything else
// unchanged (same validSetRoot/path - her own leaf hasn't moved). Simulates
// an epoch bump caused by an unrelated holder's issuance/revocation
// elsewhere in the system, per the audit finding that a nullifier
// depending on epoch defeats replay detection the moment epoch advances
// for any reason. Used by OfferingPolicy.t.sol's cross-epoch replay
// regression test (specs/phase-3/verification-infrastructure.md §7.3
// case 11b).
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

    const fullInputEpoch6 = {
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
        currentEpoch: fixtures.CURRENT_EPOCH + 1n,
        scope: fixtures.SCOPE,
    };

    fs.writeFileSync(
        path.join(__dirname, "input_full_epoch6.json"),
        JSON.stringify(stringify(fullInputEpoch6), null, 2)
    );
    console.log("wrote input_full_epoch6.json");
}

main();
