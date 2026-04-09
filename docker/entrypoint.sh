#!/bin/bash
set -e

HOME_DIR="/root/.intgd"

# Source library
if [ -f /usr/local/bin/lib.sh ]; then
  source /usr/local/bin/lib.sh
fi

auto_setup() {
  # Non-interactive setup using environment variables
  local network="${NETWORK:-mainnet}"
  local moniker="${MONIKER:?MONIKER env var required}"

  if [ "$network" = "mainnet" ] || [ "$network" = "1" ]; then
    set_network_config "1"
  else
    set_network_config "2"
  fi

  echo "==> Initializing node: ${moniker} on ${CHAIN_ID}"
  intgd init "$moniker" --chain-id "$CHAIN_ID" --home "$HOME_DIR" 2>/dev/null

  # Download genesis
  echo "==> Downloading genesis from ${RPC_URL}..."
  if ! curl -sf "${RPC_URL}/genesis" | jq '.result.genesis' > "$HOME_DIR/config/genesis.json"; then
    echo "ERROR: Failed to download genesis from ${RPC_URL}"
    exit 1
  fi
  echo "==> Genesis downloaded (chain: $(jq -r '.chain_id' "$HOME_DIR/config/genesis.json"))"

  # Configure node
  echo "==> Configuring node..."
  configure_toml "$HOME_DIR" "$CHAIN_ID" "$EVM_CHAIN_ID" "$DENOM" "$SEEDS"

  # Add custom peers if provided
  if [ -n "${PEERS:-}" ]; then
    sed -i'' -e "s|persistent_peers = \"[^\"]*\"|persistent_peers = \"${PEERS}\"|" "$HOME_DIR/config/config.toml"
  fi

  # State sync (disabled by default — mainnet nodes don't serve usable snapshots yet)
  # Block sync takes ~15-30 min for the current chain height, which is acceptable.
  if [ "${STATE_SYNC:-false}" = "true" ]; then
    LATEST_HEIGHT=$(curl -sf "${RPC_URL}/block" | jq -r '.result.block.header.height' 2>/dev/null || echo "0")
    if [ "$LATEST_HEIGHT" -gt 1000 ] 2>/dev/null; then
      TRUST_HEIGHT=$((LATEST_HEIGHT - 1000))
      TRUST_HASH=$(curl -sf "${RPC_URL}/block?height=${TRUST_HEIGHT}" | jq -r '.result.block_id.hash' 2>/dev/null || echo "")
      if [ -n "$TRUST_HASH" ] && [ "$TRUST_HASH" != "null" ]; then
        configure_state_sync "$HOME_DIR" "$RPC_URL" "$TRUST_HEIGHT" "$TRUST_HASH"
        echo "==> State sync enabled (trust height: ${TRUST_HEIGHT})"
      fi
    fi
  fi

  echo "==> Auto-setup complete for ${moniker} on ${CHAIN_ID}"
}

case "$1" in
  setup)
    exec setup-wizard
    ;;
  start)
    if [ ! -d "$HOME_DIR/config" ]; then
      if [ -n "${MONIKER:-}" ]; then
        # Non-interactive mode: env vars provided
        auto_setup
      else
        echo "First run detected — launching setup wizard..."
        echo "(Set MONIKER env var to skip the wizard)"
        setup-wizard
      fi
    fi
    exec intgd start \
      --home "$HOME_DIR" \
      --minimum-gas-prices "5000000000000airl" \
      --json-rpc.enable true \
      --json-rpc.api "eth,txpool,personal,net,debug,web3"
    ;;
  *)
    exec "$@"
    ;;
esac
