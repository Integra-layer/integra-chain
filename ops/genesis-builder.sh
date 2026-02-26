#!/bin/bash
# genesis-builder.sh — Automates the Integra Layer genesis ceremony.
#
# Run this on the coordinator node (foundation-1). It handles:
#   1. Initialize the node
#   2. Add genesis accounts (treasury + validators)
#   3. Create gentx for this validator
#   4. Collect gentxs from all validators
#   5. Inject denom metadata
#   6. Validate genesis
#
# Usage:
#   ./genesis-builder.sh init         — Initialize node + add accounts
#   ./genesis-builder.sh gentx        — Create this node's gentx
#   ./genesis-builder.sh collect      — Collect all gentxs + finalize genesis
#   ./genesis-builder.sh validate     — Validate the final genesis
#   ./genesis-builder.sh all          — Run full ceremony (single-node dev mode)

set -e

BOLD='\033[1m' GREEN='\033[0;32m' CYAN='\033[0;36m'
YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'

# ---- Configuration ----
CHAIN_ID="${CHAIN_ID:-integra-1}"
HOME_DIR="${HOME_DIR:-/root/.intgd}"
DENOM="airl"
KEYRING="${KEYRING:-file}"

# Token amounts (airl = 10^18 per IRL)
TREASURY_AMOUNT="99999996000000000000000000000"    # 99,999,996,000 IRL
VALIDATOR_AMOUNT="1000000000000000000000"           # 1,000 IRL
STAKE_AMOUNT="1000000000000000000000"               # 1,000 IRL self-stake
MIN_SELF_DELEGATION="1000000000000000000000"         # 1,000 IRL
DELEGATION_AMOUNT="250000000000000000000000000000"   # 250,000,000 IRL per validator

# Validator defaults
COMMISSION_RATE="0.05"
COMMISSION_MAX_RATE="0.20"
COMMISSION_MAX_CHANGE="0.01"

# ---- Helpers ----
log()  { echo -e "${CYAN}[genesis]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn ]${NC} $*"; }
err()  { echo -e "${RED}[error ]${NC} $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 1; }
}

require_deps() {
  require_cmd intgd
  require_cmd jq
}

# ---- Step 1: Initialize ----
do_init() {
  local moniker="${1:?Usage: genesis-builder.sh init <moniker>}"

  log "Initializing node: moniker=$moniker chain=$CHAIN_ID"
  intgd init "$moniker" --chain-id "$CHAIN_ID" --home "$HOME_DIR" 2>/dev/null
  ok "Node initialized at $HOME_DIR"

  # Fix client.toml
  sed -i'' -e "s/chain-id = \"\"/chain-id = \"${CHAIN_ID}\"/" "$HOME_DIR/config/client.toml"
  ok "client.toml chain-id set"
}

# ---- Step 2: Add genesis accounts ----
do_add_accounts() {
  log "Adding genesis accounts..."

  # Treasury account
  if [ -n "$TREASURY_ADDR" ]; then
    intgd genesis add-genesis-account "$TREASURY_ADDR" "${TREASURY_AMOUNT}${DENOM}" --home "$HOME_DIR"
    ok "Treasury: $TREASURY_ADDR (99,999,996,000 IRL)"
  else
    warn "TREASURY_ADDR not set — skipping treasury account"
  fi

  # Validator accounts
  local i=1
  for addr in $VALIDATOR_ADDRS; do
    intgd genesis add-genesis-account "$addr" "${VALIDATOR_AMOUNT}${DENOM}" --home "$HOME_DIR"
    ok "Validator $i: $addr (1,000 IRL)"
    i=$((i + 1))
  done

  if [ "$i" -eq 1 ]; then
    warn "No VALIDATOR_ADDRS set. Set: export VALIDATOR_ADDRS='addr1 addr2 addr3 addr4'"
  fi
}

# ---- Step 3: Inject denom metadata ----
do_inject_metadata() {
  log "Injecting IRL denom metadata..."

  local genesis="$HOME_DIR/config/genesis.json"
  local metadata='[{
    "description": "Integra Layer Native Token",
    "denom_units": [
      { "denom": "airl", "exponent": 0, "aliases": ["attoirl"] },
      { "denom": "irl", "exponent": 18, "aliases": ["IRL"] }
    ],
    "base": "airl",
    "display": "irl",
    "name": "Integra",
    "symbol": "IRL"
  }]'

  local tmp=$(mktemp)
  jq --argjson meta "$metadata" '.app_state.bank.denom_metadata = $meta' "$genesis" > "$tmp"
  mv "$tmp" "$genesis"
  ok "Denom metadata injected (airl / IRL, 18 decimals)"
}

# ---- Step 4: Create gentx ----
do_gentx() {
  local moniker="${1:?Usage: genesis-builder.sh gentx <moniker> [key-name]}"
  local key_name="${2:-validator}"

  log "Creating gentx: moniker=$moniker key=$key_name stake=${STAKE_AMOUNT}${DENOM}"
  intgd genesis gentx "$key_name" "${STAKE_AMOUNT}${DENOM}" \
    --chain-id "$CHAIN_ID" \
    --moniker "$moniker" \
    --commission-rate "$COMMISSION_RATE" \
    --commission-max-rate "$COMMISSION_MAX_RATE" \
    --commission-max-change-rate "$COMMISSION_MAX_CHANGE" \
    --min-self-delegation "$MIN_SELF_DELEGATION" \
    --keyring-backend "$KEYRING" \
    --home "$HOME_DIR"

  ok "Gentx created in $HOME_DIR/config/gentx/"
  echo ""
  log "Next: copy this gentx file to the coordinator node's $HOME_DIR/config/gentx/"
  ls -la "$HOME_DIR/config/gentx/"
}

# ---- Step 5: Collect gentxs ----
do_collect() {
  log "Collecting gentxs..."

  local count=$(ls "$HOME_DIR/config/gentx/" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -eq 0 ]; then
    err "No gentx files found in $HOME_DIR/config/gentx/"
    err "Copy gentx files from each validator node first."
    exit 1
  fi

  log "Found $count gentx file(s)"
  intgd genesis collect-gentxs --home "$HOME_DIR"
  ok "Gentxs collected"
}

# ---- Step 6: Validate ----
do_validate() {
  log "Validating genesis..."
  if intgd genesis validate --home "$HOME_DIR" 2>&1; then
    ok "Genesis is valid!"
  else
    err "Genesis validation FAILED"
    exit 1
  fi

  # Print summary
  local genesis="$HOME_DIR/config/genesis.json"
  echo ""
  log "Genesis summary:"
  echo -e "  Chain ID:     ${BOLD}$(jq -r '.chain_id' "$genesis")${NC}"
  echo -e "  Genesis time: ${BOLD}$(jq -r '.genesis_time' "$genesis")${NC}"

  local num_accounts=$(jq '.app_state.auth.accounts | length' "$genesis")
  echo -e "  Accounts:     ${BOLD}${num_accounts}${NC}"

  local num_gentx=$(jq '.app_state.genutil.gen_txs | length' "$genesis")
  echo -e "  Validators:   ${BOLD}${num_gentx}${NC}"

  local total_supply=$(jq -r '.app_state.bank.supply[0].amount // "unknown"' "$genesis")
  echo -e "  Total supply: ${BOLD}${total_supply} ${DENOM}${NC}"

  echo ""
  echo -e "  ${GREEN}Genesis file: $genesis${NC}"
  echo -e "  ${CYAN}Distribute this file to all validator nodes.${NC}"
}

# ---- Step 7: Post-genesis delegation ----
do_delegate() {
  log "Delegating to all validators (250M IRL each)..."

  local treasury_key="${1:-foundation-treasury}"
  local i=1

  for valoper in $VALOPER_ADDRS; do
    log "Delegating to validator $i: $valoper"
    intgd tx staking delegate "$valoper" "${DELEGATION_AMOUNT}${DENOM}" \
      --from "$treasury_key" \
      --gas-prices "5000000000000${DENOM}" \
      --gas auto --gas-adjustment 1.3 \
      --keyring-backend "$KEYRING" \
      --chain-id "$CHAIN_ID" \
      --home "$HOME_DIR" -y

    ok "Delegated 250M IRL to $valoper"
    i=$((i + 1))

    # Wait for tx to land
    sleep 6
  done

  if [ "$i" -eq 1 ]; then
    warn "No VALOPER_ADDRS set. Set: export VALOPER_ADDRS='valoper1 valoper2 valoper3 valoper4'"
  fi
}

# ---- Main ----
case "${1:-help}" in
  init)
    require_deps
    do_init "${2:?Provide moniker: genesis-builder.sh init <moniker>}"
    do_add_accounts
    do_inject_metadata
    ;;
  gentx)
    require_deps
    do_gentx "${2:?Provide moniker: genesis-builder.sh gentx <moniker> [key-name]}" "${3:-validator}"
    ;;
  collect)
    require_deps
    do_collect
    do_inject_metadata
    do_validate
    ;;
  validate)
    require_deps
    do_validate
    ;;
  delegate)
    require_deps
    do_delegate "${2:-foundation-treasury}"
    ;;
  all)
    require_deps
    # Full ceremony for single-node dev/test
    do_init "${2:?Provide moniker: genesis-builder.sh all <moniker>}"
    do_add_accounts
    do_inject_metadata
    do_gentx "${2}" "${3:-validator}"
    do_collect
    do_validate
    ;;
  help|*)
    echo "Integra Layer Genesis Builder"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  init <moniker>              Initialize node + add genesis accounts"
    echo "  gentx <moniker> [key]       Create this node's gentx"
    echo "  collect                     Collect all gentxs + validate"
    echo "  validate                    Validate final genesis"
    echo "  delegate [treasury-key]     Post-genesis: delegate 250M to each validator"
    echo "  all <moniker> [key]         Full ceremony (single-node dev mode)"
    echo ""
    echo "Environment variables:"
    echo "  CHAIN_ID          Chain ID (default: integra-1)"
    echo "  HOME_DIR          Node home (default: /root/.intgd)"
    echo "  KEYRING           Keyring backend (default: file)"
    echo "  TREASURY_ADDR     Treasury wallet address"
    echo "  VALIDATOR_ADDRS   Space-separated validator addresses"
    echo "  VALOPER_ADDRS     Space-separated valoper addresses (for delegate)"
    echo ""
    echo "Multi-node ceremony:"
    echo "  1. On coordinator:  TREASURY_ADDR=... VALIDATOR_ADDRS='...' $0 init foundation-1"
    echo "  2. Copy genesis to all nodes"
    echo "  3. On each node:    $0 gentx foundation-N"
    echo "  4. Copy gentxs back to coordinator"
    echo "  5. On coordinator:  $0 collect"
    echo "  6. Distribute final genesis to all nodes"
    echo "  7. Start all nodes, then: VALOPER_ADDRS='...' $0 delegate"
    ;;
esac
