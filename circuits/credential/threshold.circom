pragma circom 2.2.3;

include "../node_modules/circomlib/circuits/comparators.circom";

// Phase 2 (F2.4). Generic M-of-N threshold: given N boolean signals,
// output 1 iff at least M are true. A summation constraint
// (sum(conditions) >= M), not an enumerated OR-of-ANDs -
// credential-protocol.md §5.2. Reinstating a third EU sub-condition
// later is instantiating this with N=3 instead of N=2, a configuration
// change rather than a redesign (PRD post-MVP extension #7) - the
// standalone ThresholdOfN(2,3) test in test/eligibility.test.js exists
// specifically to demonstrate that, not just assert it.
//
// conditions[i] is assumed boolean (0 or 1) by every caller in this
// project - each is always the output of a comparator or another
// ThresholdOfN, never a raw signal - so it isn't re-constrained here.
//
// 8 bits is a fixed, deliberately oversized bound for the sum: N is at
// most a handful in this project (2 or 3), so 8 bits (M, N <= 255) is
// safe headroom, not a computed-to-fit value - no reason to make this
// another template parameter for numbers this small.
template ThresholdOfN(M, N) {
    signal input conditions[N];
    signal output out;

    signal sums[N + 1];
    sums[0] <== 0;
    for (var i = 0; i < N; i++) {
        sums[i + 1] <== sums[i] + conditions[i];
    }

    component gte = GreaterEqThan(8);
    gte.in[0] <== sums[N];
    gte.in[1] <== M;
    out <== gte.out;
}
