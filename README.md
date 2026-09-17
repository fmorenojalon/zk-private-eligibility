# zk-private-eligibility

A greenfield zero-knowledge credential system: a holder proves on their own phone, via a ZK-SNARK (Groth16, circom), that they qualify as a sophisticated EU investor — without disclosing income, portfolio, employment, or identity — while a verifier (an investment platform) checks that proof on-chain, learning nothing beyond yes/no. An issuer (a bank) attests the underlying facts; the same credential can be reused unlinkably and is correctly refused once revoked. Solo applied-research PoC in collaboration with an AI coding agent. Full rationale in [`specs/PRD.md`](specs/PRD.md).

## Start here

| Document guide | Go to |
| --- | --- |
| What this system must do, and why | [`specs/PRD.md`](specs/PRD.md) |
| Why these technologies, and how the pieces fit together | [`specs/ARCHITECTURE.md`](specs/ARCHITECTURE.md) |
| The cryptographic/protocol design — credential schema, predicates, nullifier, threat model | [`specs/credential-protocol.md`](specs/credential-protocol.md) |
| Toolchain setup and clean-build reproduction | [`TOOLCHAIN.md`](TOOLCHAIN.md) |
| The circuits and on-chain verifier | [`contracts/README.md`](contracts/README.md) |
| The measurement harness | [`measurement/README.md`](measurement/README.md) |

## Repo layout

```
specs/                   the specification suite
├── PRD.md                requirements: what must be true, phases, status
├── ARCHITECTURE.md        why this stack, system topology
├── credential-protocol.md cryptographic/protocol design (cross-phase)
└── phase-1/                requirements scoped to Phase 1 only
TOOLCHAIN.md              exact versions, install commands, build gotchas
circuits/                 circom circuits + BASELINE_RESULTS.md
contracts/                Foundry project: generated verifier, tests, README
holder-app-ios/           iOS proving harness (mopro)
measurement/              collector, analysis, records, README
issuer-service/           TBD
platform-backend/         TBD
platform-frontend/        TBD
```

