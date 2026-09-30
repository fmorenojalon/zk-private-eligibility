pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/comparators.circom";

// Phase 1 baseline primitive (F1.4). Matches the range-comparison shape
// used by P1/P2 and the retired investment-ceiling predicate (income,
// portfolio, net-worth thresholds, credential-protocol.md §5) - a single
// 64-bit GreaterEqThan comparison.
template RangeBaseline() {
    signal input value;
    signal input threshold;
    signal output out;

    component gte = GreaterEqThan(64);
    gte.in[0] <== value;
    gte.in[1] <== threshold;
    out <== gte.out;
}

component main {public [threshold]} = RangeBaseline();
