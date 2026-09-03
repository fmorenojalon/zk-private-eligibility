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

That's the whole verification story: a proof generated on the iPhone, converted to Solidity calldata, checked by a contract whose logic came directly from the circuit's proving key, running on a real (if ephemeral) EVM.

**Note:** Groth16 proofs are randomized (blinding factors baked into each proof for zero-knowledge), so *regenerating* a proof for the same input would produce different `pA`/`pB`/`pC` values than the ones above, even though the public output stays the same. The values here are specifically the ones in the committed `circuits/poseidon-baseline/proof.json` fixture — they'll keep working as long as that file isn't regenerated.

`forge test -vv` (above) runs the same three assertions automatically against Foundry's in-memory EVM on every test run — that's the version that's part of the committed test suite, rather than a manual Anvil session like this one.
