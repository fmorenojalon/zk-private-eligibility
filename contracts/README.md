# Contracts

Foundry project for on-chain verification (F1.2 baseline; Phase 3 will add the registry contracts per specs/credential-protocol.md).

## `Groth16Verifier.sol`

### What it is, and how it's generated

Not hand-written. `snarkjs zkey export solidityverifier` reads the circuit's proving key (`circuits/poseidon-baseline/circuit_final.zkey`) and writes a plain **Solidity source file** — `src/Groth16Verifier.sol` in this directory. snarkjs's job stops there; it produces readable `.sol` text, not bytecode. Bytecode only exists after we separately compile it with our own toolchain (`forge build`/`forge create`, which invoke `solc`).

To regenerate after a circuit change:

```sh
cd circuits/poseidon-baseline
npx --prefix .. snarkjs zkey export solidityverifier circuit_final.zkey ../../contracts/src/Groth16Verifier.sol
```

### Interface: exactly one function

```solidity
function verifyProof(
    uint[2] calldata _pA,
    uint[2][2] calldata _pB,
    uint[2] calldata _pC,
    uint[1] calldata _pubSignals
) public view returns (bool)
```

That's the entire public interface — one endpoint, `view` (read-only, no state change, free to call off-chain via `eth_call`/`cast call`). No constructor logic, no owner, no admin functions, nothing upgradeable. The contract is a pure, stateless verification oracle: give it a proof and public signals, get back `true`/`false`.

`_pA`/`_pB`/`_pC` are the three elliptic curve points that make up a Groth16 proof (`A`/`B`/`C` in the usual notation) — each one a function of the *entire* witness the holder's device computed (every private input, like `holder_secret`, plus every public input and intermediate value — see `ARCHITECTURE.md`'s "witness" section), not a fragment of any single input. That's what makes verification here just checking one pairing equation over these three points, not "unpacking" anything.

`_pubSignals` is `uint[1]` specifically because `poseidon-baseline` has exactly one public output (the hash). This array size is baked in at generation time — a circuit with 3 public signals generates `uint[3]`, and needs its own freshly generated verifier contract, not a parameter update to this one.

### Everything else is baked-in constants

The file also defines ~20 `uint256 constant` values (`alphax`, `betax1`, `gammax1`, `deltax1`, `IC0x`, `IC1x`, …) — the verification key from the trusted setup (`circuit_final.zkey`), compiled directly into bytecode rather than stored in contract storage. Cheaper gas-wise, but it also means a different circuit needs a freshly generated contract, not a parameter update to this one.

### How verification actually happens: raw EVM assembly + precompiles

`verifyProof`'s body is written in Yul (inline EVM assembly), not normal Solidity — deliberately, for gas efficiency. It calls three of Ethereum's built-in precompiled contracts directly via `staticcall`, at addresses `6`, `7`, `8`:

- `6` = `ecAdd` — BN254 elliptic curve point addition
- `7` = `ecMul` — BN254 scalar multiplication
- `8` = `ecPairing` — BN254 pairing check

These exist as native Ethereum precompiles specifically to make Groth16-style proof verification cheap (EIP-196/197) — this is *why* circom/snarkjs default to the BN254 curve (TR-1): it's the one Ethereum has hardware-level precompile support for. A different curve would mean implementing pairing math in Solidity itself, orders of magnitude more expensive.

What `verifyProof` does, in order:
1. **`checkField`** — rejects the call outright if a public signal isn't a valid BN254 field element.
2. Computes `vk_x = IC0 + IC1 · pubSignal[0]` (the public-input contribution to the pairing equation) via one `ecMul` + one `ecAdd` call.
3. One single `ecPairing` call checks the full Groth16 equation `e(-A,B) · e(alpha,beta) · e(vk_x,gamma) · e(C,delta) = 1` — batched into one precompile call rather than four separate pairings, the standard Groth16-on-EVM optimization.
4. Returns the precompile's success/failure as the bool.

So "verification" on-chain is concretely: two elliptic-curve operations plus one pairing check, almost entirely delegated to Ethereum's native crypto precompiles rather than Solidity-level computation — which is also why `test_GenuineProofVerifies` shows ~219k gas rather than something far larger.

## Test

```sh
forge test -vv
```

Runs against Foundry's in-memory EVM using a real proof/public-signal fixture from `circuits/poseidon-baseline/{proof,public}.json` (input `{"in": ["1", "2"]}`). Covers F1.2: genuine proof verifies, a tampered proof and a tampered public input are both rejected.

## What is Anvil?

Foundry's local Ethereum-compatible dev chain — **not** a testnet or mainnet. A fresh, ephemeral in-memory blockchain that speaks real Ethereum JSON-RPC and EVM semantics, pre-funded with 10 test accounts. It exists only while the process runs; kill it and that chain instance is gone (a fresh one spins up in seconds from the same reproducible steps below).

Default chain ID is `31337` — the standard convention for local dev chains (same one Hardhat's local network uses). Confirm it live:

```sh
curl -s -X POST http://127.0.0.1:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# {"jsonrpc":"2.0","id":1,"result":"0x7a69"}   <- 0x7a69 = 31337
```

## Deploy to a local Anvil chain and verify live

```sh
anvil --port 8545 &

forge create src/Groth16Verifier.sol:Groth16Verifier \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

The private key above is Anvil's well-known default test account #0 — public, documented, and only ever funded on ephemeral local chains. Never reuse it anywhere real. Deployment is deterministic (same key, same nonce, fresh chain), so it always lands at `0x5FbDB2315678afecb367f032d93F642f64180aa3`.

Confirm the contract is real, deployed bytecode (not just a receipt):

```sh
cast code 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://127.0.0.1:8545
```

Then call `verifyProof` with the real committed proof (`circuits/poseidon-baseline/proof.json` / `public.json`, input `{"in": ["1", "2"]}`):

```sh
VERIFIER=0x5FbDB2315678afecb367f032d93F642f64180aa3

# genuine proof -> true
cast call $VERIFIER \
  "verifyProof(uint256[2],uint256[2][2],uint256[2],uint256[1])(bool)" \
  "[0x2655b05c458d1bbe9699c544abefb7078da913321fac68faaf46248a308c13e5,0x271d1e744176ddd4252c68af022953e2f686af15fb547eba0a091bc04c4b8867]" \
  "[[0x28a8b83a77a08f722f6786d31bb54465740207e786708787cf2157fa97afb26f,0x0b27e916bc1db95727bf375967fed141bf318d3bb1d7c566434c46f07ae8259a],[0x00af2da5dbdfa171bcfcd3c177a5c0fd4815759e97fde046c0869f6f5b209f4d,0x17d950bcb4c72e61e60b56cf29b2bb1a914542122999aa00ec786802dcb0c02c]]" \
  "[0x28cb352f51a2e9681f16d5dfabf201021a5ff92e01f79a620c5da3a287877fbc,0x0c0be64b806261a43d3c7852ae8638e46aebf4b2b59e1baa30cb236a46afd8e4]" \
  "[0x115cc0f5e7d690413df64c6b9662e9cf2a3617f2743245519e19607a4417189a]" \
  --rpc-url http://127.0.0.1:8545
# -> true

# same proof, one hex digit of pA[0] flipped (...13e5 -> ...13e6) -> false
cast call $VERIFIER \
  "verifyProof(uint256[2],uint256[2][2],uint256[2],uint256[1])(bool)" \
  "[0x2655b05c458d1bbe9699c544abefb7078da913321fac68faaf46248a308c13e6,0x271d1e744176ddd4252c68af022953e2f686af15fb547eba0a091bc04c4b8867]" \
  "[[0x28a8b83a77a08f722f6786d31bb54465740207e786708787cf2157fa97afb26f,0x0b27e916bc1db95727bf375967fed141bf318d3bb1d7c566434c46f07ae8259a],[0x00af2da5dbdfa171bcfcd3c177a5c0fd4815759e97fde046c0869f6f5b209f4d,0x17d950bcb4c72e61e60b56cf29b2bb1a914542122999aa00ec786802dcb0c02c]]" \
  "[0x28cb352f51a2e9681f16d5dfabf201021a5ff92e01f79a620c5da3a287877fbc,0x0c0be64b806261a43d3c7852ae8638e46aebf4b2b59e1baa30cb236a46afd8e4]" \
  "[0x115cc0f5e7d690413df64c6b9662e9cf2a3617f2743245519e19607a4417189a]" \
  --rpc-url http://127.0.0.1:8545
# -> false

# real proof, fabricated public output -> false
cast call $VERIFIER \
  "verifyProof(uint256[2],uint256[2][2],uint256[2],uint256[1])(bool)" \
  "[0x2655b05c458d1bbe9699c544abefb7078da913321fac68faaf46248a308c13e5,0x271d1e744176ddd4252c68af022953e2f686af15fb547eba0a091bc04c4b8867]" \
  "[[0x28a8b83a77a08f722f6786d31bb54465740207e786708787cf2157fa97afb26f,0x0b27e916bc1db95727bf375967fed141bf318d3bb1d7c566434c46f07ae8259a],[0x00af2da5dbdfa171bcfcd3c177a5c0fd4815759e97fde046c0869f6f5b209f4d,0x17d950bcb4c72e61e60b56cf29b2bb1a914542122999aa00ec786802dcb0c02c]]" \
  "[0x28cb352f51a2e9681f16d5dfabf201021a5ff92e01f79a620c5da3a287877fbc,0x0c0be64b806261a43d3c7852ae8638e46aebf4b2b59e1baa30cb236a46afd8e4]" \
  "[0x9999999999999999999999999999999999999999999999999999999999999999]" \
  --rpc-url http://127.0.0.1:8545
# -> false
```

That's the whole verification flow: a proof generated on the iPhone, converted to Solidity calldata, checked by a contract whose logic came directly from the circuit's proving key, running on a real (if ephemeral) EVM.

**Note:** Groth16 proofs are randomized (blinding factors baked into each proof for zero-knowledge), so *regenerating* a proof for the same input would produce different `pA`/`pB`/`pC` values than the ones above, even though the public output stays the same. The values here are specifically the ones in the committed `circuits/poseidon-baseline/proof.json` fixture — they'll keep working as long as that file isn't regenerated.

`forge test -vv` (above) runs the same three assertions automatically against Foundry's in-memory EVM on every test run — that's the version that's part of the committed test suite, rather than a manual Anvil session like this one.

## Phase 3 contracts

Full design rationale for all of these lives in [`specs/phase-3/verification-infrastructure.md` §3](../specs/phase-3/verification-infrastructure.md#3-f31-f32-f36--contract-interfaces) — this is just what each one does and its interface.

### `EligibilityRegistry.sol`

Holds the issuer-controlled facts every offering shares: the valid-set root per epoch, the sanctions root, and the set of jurisdiction roots the issuer has approved. Everything is gated to one `issuer` address — no signature, access control is the whole security boundary (L10).

```solidity
function publishValidSetRoot(bytes32 newRoot) external;      // onlyIssuer - increments currentEpoch
function publishSanctionsRoot(bytes32 newRoot) external;     // onlyIssuer
function approveJurisdictionRoot(bytes32 root) external;     // onlyIssuer - adds to a set, never overwrites
// + public getters: currentEpoch(), validSetRootAt(epoch), sanctionsRoot(), approvedJurisdictionRoots(root)
```

### `NullifierRegistry.sol`

A flat set of consumed nullifiers — the on-chain replay guard (TR-13/PR-7). Once a given nullifier value has been recorded here, presenting the same proof again is rejected: `consumeIfUnused` reverts on anything already marked used.

The reason it isn't simply "call `consumeIfUnused` whenever you want" is front-running: a nullifier is a public value, visible in the calldata of anyone's pending presentation transaction. If any address could call `consumeIfUnused` directly, an attacker watching the mempool could read a legitimate holder's nullifier out of their about-to-be-mined transaction and submit it first — the holder's real presentation would then revert on "already used," even though they never actually got access. So this contract only ever accepts calls from one specific address, set up like this:

1. **Deploy `NullifierRegistry`.** The deploying address is captured permanently as `deployer`.
2. **Deploy `OfferingPolicy`**, passing it this contract's address.
3. **The same `deployer` address calls `setAuthorized(offeringPolicyAddress)` — once.** After this, `authorized` is fixed to `OfferingPolicy`'s address forever; calling `setAuthorized` again reverts, and so does calling `consumeIfUnused` from anywhere except `authorized`.

```solidity
function setAuthorized(address a) external;              // deployer-only, callable exactly once
function consumeIfUnused(uint256 nullifier) external;     // callable only by whatever setAuthorized set
```

A full presentation is covered in [The presentation flow, end to end](#the-presentation-flow-end-to-end) below.

**Why the mapping catches a replay at all.** `consumed` doesn't track "users" or "scopes" — it only ever sees one bare `uint256` and asks whether it's seen that exact number before. What makes replay detection work isn't nullifiers being unique; it's the opposite: `Poseidon(holder_secret, currentEpoch, scope)` is a *deterministic* function with no randomness in it. The same holder presenting to the same offering in the same epoch always produces the exact same nullifier, every time — even though the surrounding Groth16 proof itself is randomized (different `pA`/`pB`/`pC` on every generation), the nullifier output is not. That determinism is the entire mechanism: without it, a replay would just look like a brand-new number, and `consumed[nullifier]` would never find a match.

### `OfferingPolicy.sol`

The entry point a platform actually calls, and the contract whose two functions form a two-phase shape:

- **`registerOffering`** — called once per offering, rare. Sets that offering's `jurisdictionRoot`, constrained to a root the issuer already approved (`EligibilityRegistry.approvedJurisdictionRoots`) — a platform can never register an arbitrary one of its own. Returns a sequential `offeringId`, which doubles as that offering's `scope` — no separate value to track.
- **`presentEligibility`** — called once per holder presentation, the common case, and the one with real internal ordering to understand: five cheap checks against `EligibilityRegistry`'s live state and this offering's own recorded `jurisdictionRoot` run first; only if all five pass does the real Groth16 verification run (against `Groth16VerifierFull` specifically — the only configuration real offerings ever use); only if *that* passes does the nullifier actually get consumed. All of it is one atomic transaction — a failure at any step reverts everything, including whatever earlier steps already touched.

Full step-by-step for `presentEligibility`, including why that ordering matters, is in [The presentation flow, end to end](#the-presentation-flow-end-to-end) below.

```solidity
function registerOffering(bytes32 jurisdictionRoot) external returns (uint256 offeringId);  // onlyPlatform
function presentEligibility(
    uint256 offeringId,
    uint256[2] calldata pA,
    uint256[2][2] calldata pB,
    uint256[2] calldata pC,
    uint256[6] calldata publicSignals  // [nullifier, jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope]
) external returns (bool granted);
```

The three generated verifiers (`Groth16VerifierP1Only`/`CondAB`/`Full`, under `src/verifiers/`) are the same shape of contract as `Groth16Verifier.sol` above, one per circuit configuration — see that section for how `verifyProof` actually works mechanically.

## The presentation flow, end to end

What a real presentation against a live offering looks like, start to finish — this is what `OfferingPolicy.presentEligibility` and `NullifierRegistry.consumeIfUnused` are built to support, and it's the sequence the walkthrough below runs against a real deployed chain.

1. The platform's presentation request tells the holder's device the offering's `jurisdictionRoot`, plus the current `sanctionsRoot`/`validSetRoot`/`currentEpoch` — including `scope`, which is just the `offeringId` here, so there's no separate lookup for it.
2. The circuit computes `nullifier = Poseidon(holder_secret, currentEpoch, scope)` as an *output* — the holder doesn't choose it.
3. The holder generates the Groth16 proof: `pA`, `pB`, `pC`, and public signals `[nullifier, jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope]` — the nullifier sits at index 0.
4. The holder sends this to the platform, off-chain. Nothing has touched the chain yet.
5. The platform — not the holder — submits `OfferingPolicy.presentEligibility(offeringId, pA, pB, pC, publicSignals)`.
6. Five recorded-value checks run first, cheaply, in order: `jurisdictionRoot` matches this offering's; `sanctionsRoot` is current; `currentEpoch` is genuinely current; `validSetRoot` matches what's recorded for that epoch; `scope` matches this `offeringId`. Any failure reverts here — before the nullifier is touched at all.
7. Only then does `Groth16VerifierFull.verifyProof` run, the real cryptographic check. A tampered or fabricated proof dies here — still before the nullifier is touched.
8. **Only now, last, does `consumeIfUnused(nullifier)` run** — `require(!consumed[nullifier])`, then `consumed[nullifier] = true`, then `NullifierConsumed` fires.
9. All of it is one atomic transaction: if step 8 reverts, everything from steps 6–7 unwinds too, even though it already passed. A replay gets no partial credit — it's as if nothing happened. A genuine success emits `EligibilityGranted` and returns `granted = true`.

`consumeIfUnused` runs *last*, deliberately: an invalid or malformed proof never spends a nullifier. Only a proof that survives every recorded-value check and the real cryptographic verification actually consumes one.

**Why step 6 exists at all, given step 7 already does real cryptographic verification.** `verifyProof` only proves this proof is internally consistent with the exact public inputs submitted alongside it — it has no notion of "current." A proof stays cryptographically valid forever, even long after the epoch, `sanctionsRoot`, or offering it names has gone stale — Groth16 verification is a timeless mathematical check, not something that expires. Step 6 is what confirms these specific public inputs are still the live, correct ones for this offering *today*, not merely self-consistent with each other. Skip it, and a revoked holder's original proof — still perfectly valid by `verifyProof`'s own logic — would keep working forever.

## Phase 3: deploy and verify the eligibility contracts on Anvil

The same "deploy to a real chain, drive it with `cast`" exercise as above, for the full Phase 3 stack (`EligibilityRegistry`, `NullifierRegistry`, `Groth16VerifierFull`, `OfferingPolicy`) rather than just the bare verifier. `forge test` (28 cases across `EligibilityRegistry.t.sol`/`NullifierRegistry.t.sol`/`OfferingPolicy.t.sol`/`Integration.t.sol`) already covers this against Foundry's in-memory EVM — this section is the same flow confirmed against a real, if ephemeral, Anvil process instead, using two of Anvil's well-known default test accounts as "issuer" and "platform" (public, documented, ephemeral-chain-only — never reuse them anywhere real):

```sh
anvil --port 8555 &

ISSUER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # Anvil account #0
ISSUER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
PLATFORM_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d  # Anvil account #1
PLATFORM=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
RPC=http://127.0.0.1:8555
```

**Deploy all four contracts**, issuer deploying each one (deployment order matters: `OfferingPolicy`'s constructor needs the other three's addresses already, and `NullifierRegistry.setAuthorized` — next step — can only ever be called by whichever address deployed it):

```sh
forge create src/EligibilityRegistry.sol:EligibilityRegistry --rpc-url $RPC --private-key $ISSUER_KEY --broadcast --constructor-args $ISSUER
# Deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3

forge create src/NullifierRegistry.sol:NullifierRegistry --rpc-url $RPC --private-key $ISSUER_KEY --broadcast
# Deployed to: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512

forge create src/verifiers/Groth16VerifierFull.sol:Groth16VerifierFull --rpc-url $RPC --private-key $ISSUER_KEY --broadcast
# Deployed to: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0

forge create src/OfferingPolicy.sol:OfferingPolicy --rpc-url $RPC --private-key $ISSUER_KEY --broadcast \
  --constructor-args $PLATFORM 0x5FbDB2315678afecb367f032d93F642f64180aa3 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
# Deployed to: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
```

Deployment is deterministic on a fresh chain (same keys, same nonce sequence), so these four addresses will reproduce exactly on a clean `anvil` restart following these same steps.

**Wire `NullifierRegistry` to `OfferingPolicy`** — must be sent by the issuer key specifically, since `deployer` was captured as `msg.sender` when `NullifierRegistry` was deployed (`specs/phase-3/verification-infrastructure.md §3.2`):

```sh
REGISTRY=0x5FbDB2315678afecb367f032d93F642f64180aa3
NULLIFIERS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
POLICY=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9

cast send $NULLIFIERS "setAuthorized(address)" $POLICY --rpc-url $RPC --private-key $ISSUER_KEY
cast call $NULLIFIERS "authorized()(address)" --rpc-url $RPC
# -> 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
```

**Issuer sets up the registry state**, using the real values baked into Alice's real fixture proof (`circuits/credential/public_full.json` — `[nullifier, jurisdictionRoot, sanctionsRoot, validSetRoot, currentEpoch, scope]`, verified in `specs/phase-3/verification-infrastructure.md §3.3`):

```sh
JROOT=0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff
SROOT=0x0b9fa49e73ac3e867872fcbe504c1a93652e83a030af877ec38d2fd7a9b51af3
VROOT=0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2

cast send $REGISTRY "approveJurisdictionRoot(bytes32)" $JROOT --rpc-url $RPC --private-key $ISSUER_KEY

# currentEpoch increments by 1 per call - reach epoch 5 (the fixture's epoch),
# landing the real validSetRoot on the 5th publish.
for i in 1 2 3 4; do
  cast send $REGISTRY "publishValidSetRoot(bytes32)" $(cast --to-bytes32 $i) --rpc-url $RPC --private-key $ISSUER_KEY
done
cast send $REGISTRY "publishValidSetRoot(bytes32)" $VROOT --rpc-url $RPC --private-key $ISSUER_KEY

cast send $REGISTRY "publishSanctionsRoot(bytes32)" $SROOT --rpc-url $RPC --private-key $ISSUER_KEY
```

**Platform registers an offering** against the issuer-approved `jurisdictionRoot` (`registerOffering` reverts on anything else — `specs/phase-3/verification-infrastructure.md §1`/§3.3):

```sh
cast send $POLICY "registerOffering(bytes32)" $JROOT --rpc-url $RPC --private-key $PLATFORM_KEY
cast call $POLICY "nextOfferingId()(uint256)" --rpc-url $RPC
# -> 1 (offering 0 now registered)
```

**Present Alice's real proof** (`circuits/credential/proof_full.json`/`public_full.json`) against offering `0`:

```sh
cast send $POLICY \
  "presentEligibility(uint256,uint256[2],uint256[2][2],uint256[2],uint256[6])(bool)" \
  0 \
  "[0x060fc32807bc7e7e464ebd95af36e153c9e0d5b5ead3dae26dc8d11a2cf683ab,0x2b99305a8a98c1def6bdc1a0c49f2a2a11babbf586a9064828fb02f450d54c55]" \
  "[[0x1ca1a01f24aac569c0a1104eb1dc719240aa9691f5f529b8192009afe2994fa0,0x251082d516d29c78bf63cd5c6859fccf74a4851da0e95af110284c933489d437],[0x02881368a6989192d09fb52c6af353a84b09d7dba8c3604ff5ab7ba5d05687ac,0x2a0b692d1c2c3d2f8a8cb6e6df86e93eb812f956621dc5ae40c38dc2feb5c968]]" \
  "[0x06af8d2f8363b3a6807a78b14a565634ab8dea65b1e7f001f2908459a40cb445,0x03b2d48ee0b84cfab0003f71ca58a00b0f2b4e19a57c592f81c007b4b95bbb48]" \
  "[0x1286f39bcb5e397777332dbfa971c100c51f94b406ab03e48509a11b6a259100,0x0a85c9dc3c9b7d1a4b73627f0ac4eedfb2a11a20cf5194bbb0e089384ee3f3ff,0x0b9fa49e73ac3e867872fcbe504c1a93652e83a030af877ec38d2fd7a9b51af3,0x13da7c1d32569bf2a92e1aea89a0a85a9397cfc47a581edffe2fe55db5197fb2,0x0000000000000000000000000000000000000000000000000000000000000005,0x0000000000000000000000000000000000000000000000000000000000000000]" \
  --rpc-url $RPC --private-key $PLATFORM_KEY
# status: 1 (success) - emits NullifierConsumed and EligibilityGranted(offeringId=0, nullifier=...)
```

**Replay the identical call** — confirms TR-13/PR-7 end-to-end, not just at the `NullifierRegistry` unit level:

```sh
cast send $POLICY "presentEligibility(...)" 0 ... --rpc-url $RPC --private-key $PLATFORM_KEY
# Error: execution reverted: nullifier already used
```

Both outcomes (grant, then reject on replay) match `OfferingPolicy.t.sol` cases 10/11 and `Integration.t.sol`'s happy path exactly — this is the same behavior, just observed against a real deployed contract on a real (if ephemeral) EVM rather than only Foundry's in-memory one.
