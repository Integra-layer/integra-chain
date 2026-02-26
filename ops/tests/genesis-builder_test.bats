#!/usr/bin/env bats
# Tests for ops/genesis-builder.sh — genesis ceremony automation.
# Tests the help output and argument validation (no intgd required).

SCRIPT="$BATS_TEST_DIRNAME/../genesis-builder.sh"

@test "genesis-builder.sh: syntax is valid" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "help: shows usage when no args" {
  run bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Integra Layer Genesis Builder"* ]]
  [[ "$output" == *"init <moniker>"* ]]
  [[ "$output" == *"gentx <moniker>"* ]]
  [[ "$output" == *"collect"* ]]
  [[ "$output" == *"validate"* ]]
  [[ "$output" == *"delegate"* ]]
}

@test "help: shows environment variables" {
  run bash "$SCRIPT" help
  [[ "$output" == *"CHAIN_ID"* ]]
  [[ "$output" == *"TREASURY_ADDR"* ]]
  [[ "$output" == *"VALIDATOR_ADDRS"* ]]
  [[ "$output" == *"VALOPER_ADDRS"* ]]
}

@test "help: shows multi-node ceremony steps" {
  run bash "$SCRIPT" help
  [[ "$output" == *"Multi-node ceremony"* ]]
  [[ "$output" == *"coordinator"* ]]
}

@test "init: fails without moniker argument" {
  run bash "$SCRIPT" init
  [ "$status" -ne 0 ]
}

@test "gentx: fails without moniker argument" {
  run bash "$SCRIPT" gentx
  [ "$status" -ne 0 ]
}

@test "all: fails without moniker argument" {
  run bash "$SCRIPT" all
  [ "$status" -ne 0 ]
}

@test "token amounts: treasury is 99,999,996,000 IRL" {
  # Verify the treasury amount constant: 99999996000 * 10^18
  run grep 'TREASURY_AMOUNT=' "$SCRIPT"
  [[ "$output" == *"99999996000000000000000000000"* ]]
}

@test "token amounts: validator stake is 1,000 IRL" {
  run grep 'VALIDATOR_AMOUNT=' "$SCRIPT"
  [[ "$output" == *"1000000000000000000000"* ]]
}

@test "token amounts: delegation is 250,000,000 IRL per validator" {
  run grep 'DELEGATION_AMOUNT=' "$SCRIPT"
  [[ "$output" == *"250000000000000000000000000000"* ]]
}

@test "config: default chain_id is integra-1" {
  run grep 'CHAIN_ID=' "$SCRIPT"
  [[ "$output" == *"integra-1"* ]]
}

@test "config: uses airl denom" {
  run grep 'DENOM=' "$SCRIPT"
  [[ "$output" == *'"airl"'* ]]
}

@test "config: commission rate is 5%" {
  run grep 'COMMISSION_RATE=' "$SCRIPT"
  [[ "$output" == *"0.05"* ]]
}

@test "cosmovisor-setup.sh: syntax is valid" {
  run bash -n "$BATS_TEST_DIRNAME/../cosmovisor-setup.sh"
  [ "$status" -eq 0 ]
}
