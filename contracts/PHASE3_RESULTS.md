# Phase 3 — Gas Measurement

Satisfies F3.7, per [`../specs/phase-3/verification-infrastructure.md` §6](../specs/phase-3/verification-infrastructure.md#6-f37--gas-measurement) — bare `verifyProof` gas across all three circuit configurations, plus the full `presentEligibility` call for `circuit_full`, isolated so the cross-checking layer's own cost is a real, separately-measured number rather than folded into one combined figure.

**Methodology.** Desktop measurement (same machine as `circuits/BASELINE_RESULTS.md`/`PHASE2_RESULTS.md`), against Foundry's in-memory EVM via `forge test --gas-report`, using Alice's real Phase 2 fixture proofs (`proof_{p1only,condab,full}.json`) — not mocked calldata. Each number comes from a dedicated test in `test/GasMeasurement.t.sol`, kept separate from the correctness suites (`EligibilityRegistry.t.sol` etc.) so this file's numbers map directly onto that one file's output, uncluttered by unrelated tests' gas. `circuit_p1only`/`circuit_condab` are measured via a bare, freshly-deployed verifier only — they never present against a real offering (`verification-infrastructure.md §3.3`) and their 4-element public-signals array is incompatible with `OfferingPolicy`'s fixed 6-element signature. `circuit_full` is measured both ways: bare `verifyProof`, and the complete `presentEligibility` call through a fully deployed stack (`EligibilityRegistry` + `NullifierRegistry` + `OfferingPolicy` + `Groth16VerifierFull`), issuer/platform state set up identically to `contracts/README.md`'s live Anvil walkthrough.

## Results

| Circuit | Constraints (Phase 2) | Public signals | `verifyProof` gas | `presentEligibility` gas |
| --- | --- | --- | --- | --- |
| `circuit_p1only` | 12,963 | 4 | 209,067 | — (never presents against a real offering) |
| `circuit_condab` | 13,117 | 4 | 209,067 | — (never presents against a real offering) |
| `circuit_full` | 35,042 | 6 | 222,361 | 302,719 |

Deployment costs, for reference: `Groth16VerifierP1Only` 439,141 gas (1,813 bytes runtime), `Groth16VerifierCondAB` 439,333 gas (1,814 bytes), `Groth16VerifierFull` 479,078 gas (1,998 bytes), `OfferingPolicy` 1,214,667 gas (6,217 bytes) — all one-time costs, paid once at deploy, not per presentation.

## Observations

- **The prediction from `verification-infrastructure.md §6` holds, with one number worth being precise about.** `circuit_full` has 2.7× `circuit_condab`'s constraints (35,042 vs. 13,117) but its `verifyProof` gas is only 6% higher (222,361 vs. 209,067) — nowhere near a proportional increase. Verification cost tracks public-input count, not constraint count, exactly as predicted: `circuit_p1only` and `circuit_condab` (4 public signals each) land on the *identical* gas figure, 209,067, despite `circuit_condab` costing 154 more constraints than `circuit_p1only` in Phase 2 — constraint count is, correctly, invisible to on-chain verification cost.
- **The actual per-signal cost is larger than the spec's original "a few thousand gas" estimate, though the qualitative finding is unaffected.** Two extra public inputs cost 13,294 gas (222,361 − 209,067), roughly 6,650 gas per additional signal — each one is a scalar multiplication (`ecMul`) plus a point addition (`ecAdd`) against the verification key's `IC` points, folded into `vk_x` before the single `ecPairing` call (`contracts/README.md`'s "How verification actually happens" section). 6,650 gas per signal is a reasonable, expected cost for that operation pair; the spec's "a few thousand" was in the right direction but on the low side. What the prediction got right regardless: if gas scaled with constraints the way proving time does, `circuit_full` would cost roughly 2.7× `circuit_condab`'s gas — over 560,000 — not 6% more. The contrast itself (proving cost scales with predicates, verification cost scales with public-input count) is confirmed, not assumed.
- **The `presentEligibility` − `verifyProof` delta is 80,358 gas — larger than the spec's back-of-envelope estimate, and the breakdown explains why.** The prediction named `NullifierRegistry`'s `SSTORE` (~20k for a zero→nonzero write) plus a handful of cold `SLOAD`s as the dominant cost. Both are real contributors, but there's a third the original estimate didn't itemize: five separate cross-contract calls into `EligibilityRegistry` (`sanctionsRoot()`, `currentEpoch()`, `validSetRootAt()`) and `NullifierRegistry` (`consumeIfUnused`), each paying Solidity's external-call overhead (`CALL` opcode, ~2,600 gas base plus argument/return-data handling) on top of the state read itself — five external calls is a meaningfully larger fixed cost than the single `SSTORE` the spec's prediction focused on. This is a real, measured number now (80,358), not the loose estimate the spec stated before measuring; it isn't broken down further here since doing so would need per-opcode tracing, out of scope for this pass.
- **Every gas figure here is deterministic across repeated runs** — Foundry's in-memory EVM against the same fixture proof and the same contract bytecode reproduces identical numbers every time (confirmed: `verifyProof`'s `# Calls: 2` row for `circuit_full` shows the exact same 222,361 both times it's called, once standalone and once inside `presentEligibility`). Unlike proving time (wall-clock, machine-dependent), on-chain gas is not a measurement with sampling noise — one run is definitive, which is why this table has no mean/median/p95 columns the way `BASELINE_RESULTS.md`'s on-device section does.

## L1/L2 Cost Projection (informal preview of F5.4)

`PRD.md F5.4` defers a full "on-chain cost projected across L1/L2 price points" pass to Phase 5 — this is an early, informal look using the gas figures above, real ETH/gas-price data as of 2026-09-21, not a substitute for that later pass.

| Network | Gas price | `verifyProof` (222,361 gas) | `presentEligibility` (302,719 gas) |
| --- | --- | --- | --- |
| Ethereum mainnet — live, 2026-09-21 (unusually quiet) | 0.1 gwei | $0.06 | $0.08 |
| Ethereum mainnet — typical/moderately busy (illustrative) | 15 gwei | $8.84 | $12.03 |
| Ethereum mainnet — congested (illustrative) | 50 gwei | $29.46 | $40.11 |
| Base — live, 2026-09-21 | 2.446 gwei | $1.44 | $1.96 |

ETH ≈ $2,650 at time of lookup. Two caveats that matter more than the numbers themselves:

- **The "live" mainnet row is an outlier, not a representative baseline.** 0.065–1.45 gwei is remarkably low for Ethereum mainnet historically; it has spent far more time in the 10–50+ gwei range. The illustrative rows exist because comparing Base only to a coincidentally-quiet mainnet moment would understate the typical L1/L2 cost gap — at anything resembling normal congestion, an L2 is the clearly cheaper venue for a per-presentation cost like this one, by 5–20×.
- **The Base figures are execution gas only.** Base, as an OP-Stack rollup, also pays a separate fee to post compressed transaction data back to Ethereum L1 for data availability. Post-EIP-4844 blobs this is typically a fraction of a cent, not included above — the real total on Base is a little higher than this table shows, though still far below mainnet-at-normal-congestion.

## Reproducing

From `contracts/`:

```sh
forge test --match-contract GasMeasurementTest --gas-report
```

Reuses Phase 2's already-generated fixture proofs (`circuits/credential/proof_{p1only,condab,full}.json`) via their Solidity calldata, hardcoded into `test/GasMeasurement.t.sol` — regenerate that calldata with `snarkjs zkey export soliditycalldata public_<name>.json proof_<name>.json` from `circuits/credential/` if those fixtures are ever regenerated (e.g. after a `SCOPE` change, as happened once already this phase).
