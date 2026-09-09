# zk-private-eligibility

A greenfield zero-knowledge credential system: a person proves on their own phone that they qualify as a sophisticated investor under EU rules — without disclosing income, portfolio, employment, or identity — and an investment platform verifies that claim on-chain, learning nothing beyond a yes/no. Solo applied-research PoC. Full rationale in [`specs/PRD.md`](specs/PRD.md).

**Methodology.** Built spec-first, in collaboration with an AI coding agent — every phase's design in [`specs/`](specs/) was written and reviewed before implementation, then checked again against it. [`specs/PRD.md` §10](specs/PRD.md) is the phase-by-phase record.

## Start here

| I want to... | Go to |
| --- | --- |
| Understand what this system must do, and why | [`specs/PRD.md`](specs/PRD.md) |
| Understand why these technologies, and how the pieces fit together | [`specs/ARCHITECTURE.md`](specs/ARCHITECTURE.md) |
| See the cryptographic/protocol design — credential schema, predicates, nullifier, threat model | [`specs/credential-protocol.md`](specs/credential-protocol.md) |
| Set up the toolchain and reproduce a clean build | [`TOOLCHAIN.md`](TOOLCHAIN.md) |
| Run/verify the circuits and on-chain verifier | [`contracts/README.md`](contracts/README.md) |
| Run the measurement harness | [`measurement/README.md`](measurement/README.md) |

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

