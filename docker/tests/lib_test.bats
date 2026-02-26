#!/usr/bin/env bats
# Tests for docker/lib.sh — testable functions for the validator setup wizard.

setup() {
  source "$BATS_TEST_DIRNAME/../lib.sh"
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/config"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ---- set_network_config ----

@test "set_network_config: mainnet (choice 1)" {
  set_network_config "1"
  [ "$CHAIN_ID" = "integra-1" ]
  [ "$EVM_CHAIN_ID" = "26217" ]
  [ "$DENOM" = "airl" ]
  [ "$RPC_URL" = "https://rpc.integralayer.com" ]
}

@test "set_network_config: testnet (choice 2)" {
  set_network_config "2"
  [ "$CHAIN_ID" = "integra-testnet-1" ]
  [ "$EVM_CHAIN_ID" = "26218" ]
  [ "$DENOM" = "airl" ]
  [ "$RPC_URL" = "https://testnet-rpc.integralayer.com" ]
}

@test "set_network_config: defaults to mainnet on empty input" {
  set_network_config ""
  [ "$CHAIN_ID" = "integra-1" ]
}

@test "set_network_config: invalid input falls through to testnet" {
  set_network_config "99"
  [ "$CHAIN_ID" = "integra-testnet-1" ]
}

@test "set_network_config: both networks use airl denom" {
  set_network_config "1"
  local mainnet_denom="$DENOM"
  set_network_config "2"
  local testnet_denom="$DENOM"
  [ "$mainnet_denom" = "$testnet_denom" ]
  [ "$mainnet_denom" = "airl" ]
}

# ---- commission_to_decimal ----

@test "commission_to_decimal: 5% -> 0.05" {
  result=$(commission_to_decimal 5)
  [ "$result" = ".05" ]
}

@test "commission_to_decimal: 10% -> 0.10" {
  result=$(commission_to_decimal 10)
  [ "$result" = ".10" ]
}

@test "commission_to_decimal: 100% -> 1.00" {
  result=$(commission_to_decimal 100)
  [ "$result" = "1.00" ]
}

@test "commission_to_decimal: 0% -> 0" {
  result=$(commission_to_decimal 0)
  [ "$result" = "0" ]
}

@test "commission_to_decimal: defaults to 5 on empty" {
  result=$(commission_to_decimal "")
  [ "$result" = ".05" ]
}

# ---- configure_toml ----

@test "configure_toml: sets minimum-gas-prices in app.toml" {
  echo 'minimum-gas-prices = ""' > "$TEST_HOME/config/app.toml"
  echo 'evm_chain_id = "262144"' >> "$TEST_HOME/config/app.toml"
  echo -e '[api]\nenable = false\n[next]' >> "$TEST_HOME/config/app.toml"
  echo -e '[json-rpc]\nenable = false\n[next2]' >> "$TEST_HOME/config/app.toml"
  echo 'chain-id = ""' > "$TEST_HOME/config/client.toml"
  echo 'persistent_peers = ""' > "$TEST_HOME/config/config.toml"

  configure_toml "$TEST_HOME" "integra-1" "26217" "airl" ""

  grep -q 'minimum-gas-prices = "5000000000000airl"' "$TEST_HOME/config/app.toml"
}

@test "configure_toml: fixes evm_chain_id from 262144 to correct value" {
  echo 'minimum-gas-prices = ""' > "$TEST_HOME/config/app.toml"
  echo 'evm_chain_id = "262144"' >> "$TEST_HOME/config/app.toml"
  echo -e '[api]\nenable = false\n[next]' >> "$TEST_HOME/config/app.toml"
  echo -e '[json-rpc]\nenable = false\n[next2]' >> "$TEST_HOME/config/app.toml"
  echo 'chain-id = ""' > "$TEST_HOME/config/client.toml"
  echo 'persistent_peers = ""' > "$TEST_HOME/config/config.toml"

  configure_toml "$TEST_HOME" "integra-1" "26217" "airl" ""

  grep -q 'evm_chain_id = "26217"' "$TEST_HOME/config/app.toml"
  ! grep -q 'evm_chain_id = "262144"' "$TEST_HOME/config/app.toml"
}

@test "configure_toml: sets chain-id in client.toml" {
  echo 'minimum-gas-prices = ""' > "$TEST_HOME/config/app.toml"
  echo 'evm_chain_id = "262144"' >> "$TEST_HOME/config/app.toml"
  echo -e '[api]\nenable = false\n[next]' >> "$TEST_HOME/config/app.toml"
  echo -e '[json-rpc]\nenable = false\n[next2]' >> "$TEST_HOME/config/app.toml"
  echo 'chain-id = ""' > "$TEST_HOME/config/client.toml"
  echo 'persistent_peers = ""' > "$TEST_HOME/config/config.toml"

  configure_toml "$TEST_HOME" "integra-testnet-1" "26218" "airl" ""

  grep -q 'chain-id = "integra-testnet-1"' "$TEST_HOME/config/client.toml"
}

@test "configure_toml: enables REST API" {
  echo 'minimum-gas-prices = ""' > "$TEST_HOME/config/app.toml"
  echo 'evm_chain_id = "262144"' >> "$TEST_HOME/config/app.toml"
  echo -e '[api]\nenable = false\n[next]' >> "$TEST_HOME/config/app.toml"
  echo -e '[json-rpc]\nenable = false\n[next2]' >> "$TEST_HOME/config/app.toml"
  echo 'chain-id = ""' > "$TEST_HOME/config/client.toml"
  echo 'persistent_peers = ""' > "$TEST_HOME/config/config.toml"

  configure_toml "$TEST_HOME" "integra-1" "26217" "airl" ""

  # After patching, the [api] section should have enable = true
  run grep -A1 '\[api\]' "$TEST_HOME/config/app.toml"
  [[ "$output" == *"enable = true"* ]]
}

@test "configure_toml: sets persistent_peers when seeds provided" {
  echo 'minimum-gas-prices = ""' > "$TEST_HOME/config/app.toml"
  echo 'evm_chain_id = "262144"' >> "$TEST_HOME/config/app.toml"
  echo -e '[api]\nenable = false\n[next]' >> "$TEST_HOME/config/app.toml"
  echo -e '[json-rpc]\nenable = false\n[next2]' >> "$TEST_HOME/config/app.toml"
  echo 'chain-id = ""' > "$TEST_HOME/config/client.toml"
  echo 'persistent_peers = ""' > "$TEST_HOME/config/config.toml"

  configure_toml "$TEST_HOME" "integra-1" "26217" "airl" "node1@1.2.3.4:26656,node2@5.6.7.8:26656"

  grep -q 'persistent_peers = "node1@1.2.3.4:26656,node2@5.6.7.8:26656"' "$TEST_HOME/config/config.toml"
}

@test "configure_toml: skips persistent_peers when seeds empty" {
  echo 'minimum-gas-prices = ""' > "$TEST_HOME/config/app.toml"
  echo 'evm_chain_id = "262144"' >> "$TEST_HOME/config/app.toml"
  echo -e '[api]\nenable = false\n[next]' >> "$TEST_HOME/config/app.toml"
  echo -e '[json-rpc]\nenable = false\n[next2]' >> "$TEST_HOME/config/app.toml"
  echo 'chain-id = ""' > "$TEST_HOME/config/client.toml"
  echo 'persistent_peers = ""' > "$TEST_HOME/config/config.toml"

  configure_toml "$TEST_HOME" "integra-1" "26217" "airl" ""

  grep -q 'persistent_peers = ""' "$TEST_HOME/config/config.toml"
}

# ---- configure_state_sync ----

@test "configure_state_sync: enables state sync with correct values" {
  cat > "$TEST_HOME/config/config.toml" << 'EOF'
[statesync]
enable = false
rpc_servers = ""
trust_height = 0
trust_hash = ""
[other]
EOF

  configure_state_sync "$TEST_HOME" "https://rpc.integralayer.com" "50000" "ABCDEF1234567890"

  grep -q 'enable = true' "$TEST_HOME/config/config.toml"
  grep -q 'trust_height = 50000' "$TEST_HOME/config/config.toml"
  grep -q 'trust_hash = "ABCDEF1234567890"' "$TEST_HOME/config/config.toml"
  grep -q 'rpc_servers = "https://rpc.integralayer.com,https://rpc.integralayer.com"' "$TEST_HOME/config/config.toml"
}

# ---- generate_validator_json ----

@test "generate_validator_json: creates valid JSON with correct fields" {
  local outfile="$TEST_HOME/validator.json"

  generate_validator_json "$outfile" '{"@type":"/cosmos.crypto.ed25519.PubKey","key":"abc123"}' \
    "airl" "my-validator" "https://example.com" "A test validator" "0.05"

  [ -f "$outfile" ]
  run jq -r '.moniker' "$outfile"
  [ "$output" = "my-validator" ]
}

@test "generate_validator_json: amount placeholder uses correct denom" {
  local outfile="$TEST_HOME/validator.json"

  generate_validator_json "$outfile" '{"key":"test"}' "airl" "test" "" "" "0.05"

  run jq -r '.amount' "$outfile"
  [ "$output" = "AMOUNT_HEREairl" ]
}

@test "generate_validator_json: commission-rate is correct" {
  local outfile="$TEST_HOME/validator.json"
  generate_validator_json "$outfile" '{"key":"test"}' "airl" "test" "" "" "0.10"
  run jq -r '.["commission-rate"]' "$outfile"
  [ "$output" = "0.10" ]
}

@test "generate_validator_json: commission-max-rate is 0.20" {
  local outfile="$TEST_HOME/validator.json"
  generate_validator_json "$outfile" '{"key":"test"}' "airl" "test" "" "" "0.10"
  run jq -r '.["commission-max-rate"]' "$outfile"
  [ "$output" = "0.20" ]
}

@test "generate_validator_json: commission-max-change-rate is 0.01" {
  local outfile="$TEST_HOME/validator.json"
  generate_validator_json "$outfile" '{"key":"test"}' "airl" "test" "" "" "0.10"
  run jq -r '.["commission-max-change-rate"]' "$outfile"
  [ "$output" = "0.01" ]
}

@test "generate_validator_json: min-self-delegation is 1000 IRL in airl" {
  local outfile="$TEST_HOME/validator.json"

  generate_validator_json "$outfile" '{"key":"test"}' "airl" "test" "" "" "0.05"

  run jq -r '.["min-self-delegation"]' "$outfile"
  [ "$output" = "1000000000000000000000" ]
}

# ---- entrypoint.sh ----

@test "entrypoint.sh: syntax is valid" {
  run bash -n "$BATS_TEST_DIRNAME/../entrypoint.sh"
  [ "$status" -eq 0 ]
}

@test "setup-wizard.sh: syntax is valid" {
  run bash -n "$BATS_TEST_DIRNAME/../setup-wizard.sh"
  [ "$status" -eq 0 ]
}

@test "lib.sh: syntax is valid" {
  run bash -n "$BATS_TEST_DIRNAME/../lib.sh"
  [ "$status" -eq 0 ]
}
