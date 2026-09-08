#!/bin/bash
# End-to-end setup+prove+verify pass per circuit configuration -
# specs/phase-2/eligibility-circuits.md §7. Mirrors circuits/*-baseline's
# methodology (circom --r1cs --wasm, Powers-of-Tau + snarkjs groth16
# setup + one dev contribution, prove, verify), timed the same way
# BASELINE_RESULTS.md's numbers were produced (wall-clock date +%s%N
# deltas around each step).
set -e

NAME=$1
PTAU=$2

cd "$(dirname "$0")"

ms() { echo $(( ($1 - $2) / 1000000 )); }

t0=$(date +%s%N)
circom "circuit_${NAME}.circom" --r1cs --wasm --sym -o . -l ../node_modules >/tmp/circom_${NAME}.log 2>&1
t1=$(date +%s%N)
echo "[$NAME] compile: $(ms $t1 $t0) ms"

node "circuit_${NAME}_js/generate_witness.js" "circuit_${NAME}_js/circuit_${NAME}.wasm" "input_${NAME}.json" "witness_${NAME}.wtns"
t2=$(date +%s%N)
echo "[$NAME] witness gen: $(ms $t2 $t1) ms"

npx --prefix .. snarkjs groth16 setup "circuit_${NAME}.r1cs" "$PTAU" "circuit_${NAME}_0000.zkey" >/tmp/setup_${NAME}.log 2>&1
t3=$(date +%s%N)
echo "[$NAME] setup: $(ms $t3 $t2) ms"

npx --prefix .. snarkjs zkey contribute "circuit_${NAME}_0000.zkey" "circuit_${NAME}_final.zkey" --name="phase2-dev" -e="$(openssl rand -hex 32)" >/tmp/contribute_${NAME}.log 2>&1
t4=$(date +%s%N)
echo "[$NAME] contribute: $(ms $t4 $t3) ms"

npx --prefix .. snarkjs zkey export verificationkey "circuit_${NAME}_final.zkey" "verification_key_${NAME}.json" >/tmp/vkey_${NAME}.log 2>&1

npx --prefix .. snarkjs groth16 prove "circuit_${NAME}_final.zkey" "witness_${NAME}.wtns" "proof_${NAME}.json" "public_${NAME}.json"
t5=$(date +%s%N)
echo "[$NAME] proving: $(ms $t5 $t4) ms"

npx --prefix .. snarkjs groth16 verify "verification_key_${NAME}.json" "public_${NAME}.json" "proof_${NAME}.json"
t6=$(date +%s%N)
echo "[$NAME] verify: $(ms $t6 $t5) ms"

echo "[$NAME] zkey size: $(du -h circuit_${NAME}_final.zkey | cut -f1)"
