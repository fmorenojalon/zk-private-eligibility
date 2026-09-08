pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/comparators.circom";

// Phase 2 (F2.2). Shared range-comparison templates for P1, P2, P3, P7 -
// specs/phase-2/eligibility-circuits.md §4. All four predicates reduce to
// a single 64-bit comparator, matching circuits/range-baseline's pattern
// (F1.4) rather than introducing a new one. P1 and P7 use RangeGte
// (inclusive >=); P2 uses RangeGt (strict >, per credential-protocol.md
// §5's "portfolio_value > 100000"); P3 wires two RangeGte instances
// through circomlib's OR() in the composite circuit files, not here -
// this file only holds the single-comparator building blocks.

template RangeGte(n) {
    signal input value;
    signal input threshold;
    signal output out;

    component gte = GreaterEqThan(n);
    gte.in[0] <== value;
    gte.in[1] <== threshold;
    out <== gte.out;
}

template RangeGt(n) {
    signal input value;
    signal input threshold;
    signal output out;

    component gt = GreaterThan(n);
    gt.in[0] <== value;
    gt.in[1] <== threshold;
    out <== gt.out;
}
