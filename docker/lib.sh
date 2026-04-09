#!/bin/bash
# Testable library functions for the Integra validator setup wizard.
# Sourced by setup-wizard.sh and tests.

# set_network_config <choice>
# Sets CHAIN_ID, EVM_CHAIN_ID, DENOM, RPC_URL, SEEDS based on network choice.
set_network_config() {
  local choice="${1:-1}"
  if [ "$choice" = "1" ]; then
    CHAIN_ID="integra-1"
    EVM_CHAIN_ID="26217"
    DENOM="airl"
    RPC_URL="https://mainnet.integralayer.com/rpc"
    SEEDS="837a39f482a80b56f491737055fe52199006f1fd@89.167.88.24:26656,adeaabdac580df25d3766d6f1950e30c1aba2f1c@45.77.139.208:36656,91d0540496a97bf071d7fd44458b1c00a2515af3@159.223.206.94:36656,9c953486b7e73d0028ef63589605926213471ef3@3.208.92.57:26656"
  else
    CHAIN_ID="integra-testnet-1"
    EVM_CHAIN_ID="26218"
    DENOM="airl"
    RPC_URL="https://testnet.integralayer.com/rpc"
    SEEDS="10d16647b0476d5405ceeb20347437a70da0c0b1@46.225.231.81:26656,1d215b882540caf56adf5d4279f377b57dfecac5@45.77.139.208:26656,bee94426ebd65dd3ee7ab56b8fcebf7f1b1585e7@159.223.206.94:26656"
  fi
}

# commission_to_decimal <percent>
# Converts integer commission percentage to decimal string (e.g. 5 -> 0.05).
commission_to_decimal() {
  local pct="${1:-5}"
  echo "scale=2; $pct/100" | bc
}

# configure_toml <home_dir> <chain_id> <evm_chain_id> <denom> [seeds]
# Applies sed patches to config.toml, app.toml, client.toml.
# Idempotent: safe to run multiple times.
configure_toml() {
  local home="$1" chain_id="$2" evm_chain_id="$3" denom="$4" seeds="${5:-}"

  # persistent_peers (replace any existing value)
  if [ -n "$seeds" ]; then
    sed -i'' -e "s|persistent_peers = \"[^\"]*\"|persistent_peers = \"${seeds}\"|" "$home/config/config.toml"
  fi

  # minimum-gas-prices (replace any existing value)
  sed -i'' -e "s|minimum-gas-prices = \"[^\"]*\"|minimum-gas-prices = \"5000000000000${denom}\"|" "$home/config/app.toml"

  # evm_chain_id (replace any value, not just 262144)
  sed -i'' -e "s|evm_chain_id = \"[^\"]*\"|evm_chain_id = \"${evm_chain_id}\"|" "$home/config/app.toml"

  # Enable REST API
  sed -i'' -e '/\[api\]/,/\[/ s/enable = false/enable = true/' "$home/config/app.toml"

  # Enable JSON-RPC
  sed -i'' -e '/\[json-rpc\]/,/\[/ s/enable = false/enable = true/' "$home/config/app.toml"

  # Bind JSON-RPC to all interfaces (for Docker)
  sed -i'' -e '/\[json-rpc\]/,/\[/ s|address = "127.0.0.1:8545"|address = "0.0.0.0:8545"|' "$home/config/app.toml"
  sed -i'' -e '/\[json-rpc\]/,/\[/ s|ws-address = "127.0.0.1:8546"|ws-address = "0.0.0.0:8546"|' "$home/config/app.toml"

  # Bind RPC to all interfaces (for Docker)
  sed -i'' -e 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|' "$home/config/config.toml"

  # client.toml chain-id (replace any value)
  sed -i'' -e "s|chain-id = \"[^\"]*\"|chain-id = \"${chain_id}\"|" "$home/config/client.toml"
}

# configure_state_sync <home_dir> <rpc_url> <trust_height> <trust_hash>
# Patches config.toml for state sync.
configure_state_sync() {
  local home="$1" rpc_url="$2" trust_height="$3" trust_hash="$4"

  sed -i'' -e '/\[statesync\]/,/\[/ s/enable = false/enable = true/' "$home/config/config.toml"
  sed -i'' -e "s/trust_height = 0/trust_height = ${trust_height}/" "$home/config/config.toml"
  sed -i'' -e "s/trust_hash = \"\"/trust_hash = \"${trust_hash}\"/" "$home/config/config.toml"
  sed -i'' -e "s|rpc_servers = \"\"|rpc_servers = \"${rpc_url},${rpc_url}\"|" "$home/config/config.toml"
}

# generate_validator_json <output_path> <pubkey_json> <denom> <moniker> <website> <description> <commission_dec>
# Writes a validator.json file for create-validator tx.
generate_validator_json() {
  local output="$1" pubkey="$2" denom="$3" moniker="$4"
  local website="$5" description="$6" commission_dec="$7"

  cat > "$output" << VALJSON
{
  "pubkey": ${pubkey},
  "amount": "AMOUNT_HERE${denom}",
  "moniker": "${moniker}",
  "identity": "",
  "website": "${website}",
  "security": "",
  "details": "${description}",
  "commission-rate": "${commission_dec}",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1000000000000000000000"
}
VALJSON
}
