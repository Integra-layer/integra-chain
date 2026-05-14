#!/usr/bin/env bash
# Integra Mainnet Parameter Verification Script
# Queries live on-chain data and compares against genesis source code expectations.
# Usage: bash scripts/verify-mainnet-params.sh > mainnet-params-report-$(date +%Y%m%d).md

set -uo pipefail

# ── Endpoints ────────────────────────────────────────────────────────────────
REST="https://mainnet.integralayer.com/api"
RPC="https://mainnet.integralayer.com/rpc"
EVM="https://mainnet.integralayer.com/evm"
WS="wss://mainnet.integralayer.com/ws"
SSH_HOST="root@89.167.88.24"
SSH_KEY="$HOME/.ssh/integra"

# ── Counters ─────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
RECORD_COUNT=0

# ── Helpers ──────────────────────────────────────────────────────────────────
rest() { curl -sf --max-time 15 "$REST/$1"; }
rpc()  { curl -sf --max-time 15 "$RPC/$1"; }
evm_call() {
  curl -sf --max-time 15 -X POST "$EVM" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":[$2],\"id\":1}" | jq -r '.result'
}

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "| $label | \`$expected\` | \`$actual\` | ✅ PASS |"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "| $label | \`$expected\` | \`$actual\` | ❌ FAIL |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_contains() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "| $label | contains \`$expected\` | \`${actual:0:80}\` | ✅ PASS |"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "| $label | contains \`$expected\` | \`${actual:0:80}\` | ❌ FAIL |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_numeric_gte() {
  local label="$1" min="$2" actual="$3"
  if (( actual >= min )); then
    echo "| $label | >= \`$min\` | \`$actual\` | ✅ PASS |"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "| $label | >= \`$min\` | \`$actual\` | ❌ FAIL |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_not_empty() {
  local label="$1" actual="$2"
  if [[ -n "$actual" && "$actual" != "null" && "$actual" != "0x" ]]; then
    local display="${actual:0:80}"
    [[ ${#actual} -gt 80 ]] && display="${display}..."
    echo "| $label | non-empty | \`${display}\` | ✅ PASS |"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "| $label | non-empty | \`$actual\` | ❌ FAIL |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

record() {
  local label="$1" actual="$2"
  echo "| $label | — | \`${actual:0:100}\` | 📋 RECORD |"
  RECORD_COUNT=$((RECORD_COUNT + 1))
}

table_header() {
  echo "| Parameter | Expected | Actual | Status |"
  echo "|-----------|----------|--------|--------|"
}

# ── Report Header ────────────────────────────────────────────────────────────
echo "# Integra Mainnet Parameter Verification Report"
echo ""
echo "**Date:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "**Endpoints:** REST=$REST | RPC=$RPC | EVM=$EVM"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 1. Chain Identity
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 1. Chain Identity"
echo ""
table_header

NODE_INFO=$(rpc "status")
NETWORK=$(echo "$NODE_INFO" | jq -r '.result.node_info.network')
check "node_info.network" "integra-1" "$NETWORK"

MONIKER=$(echo "$NODE_INFO" | jq -r '.result.node_info.moniker')
record "node_info.moniker" "$MONIKER"

LATEST_HEIGHT=$(echo "$NODE_INFO" | jq -r '.result.sync_info.latest_block_height')
record "latest_block_height" "$LATEST_HEIGHT"

CATCHING_UP=$(echo "$NODE_INFO" | jq -r '.result.sync_info.catching_up')
check "catching_up" "false" "$CATCHING_UP"

ETH_CHAIN_ID=$(evm_call "eth_chainId" "")
check "eth_chainId" "0x6669" "$ETH_CHAIN_ID"

NET_VERSION=$(evm_call "net_version" "")
check "net_version" "26217" "$NET_VERSION"

CLIENT_VERSION=$(evm_call "web3_clientVersion" "")
record "web3_clientVersion" "$CLIENT_VERSION"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 2. Consensus Params
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 2. Consensus Params"
echo ""
table_header

CONSENSUS=$(rpc "consensus_params?height=$LATEST_HEIGHT")
BLOCK_MAX_BYTES=$(echo "$CONSENSUS" | jq -r '.result.consensus_params.block.max_bytes')
record "block.max_bytes" "$BLOCK_MAX_BYTES"

BLOCK_MAX_GAS=$(echo "$CONSENSUS" | jq -r '.result.consensus_params.block.max_gas')
record "block.max_gas" "$BLOCK_MAX_GAS"

EVIDENCE_MAX_AGE=$(echo "$CONSENSUS" | jq -r '.result.consensus_params.evidence.max_age_num_blocks')
record "evidence.max_age_num_blocks" "$EVIDENCE_MAX_AGE"

EVIDENCE_DURATION=$(echo "$CONSENSUS" | jq -r '.result.consensus_params.evidence.max_age_duration')
record "evidence.max_age_duration" "$EVIDENCE_DURATION"

PUB_KEY_TYPES=$(echo "$CONSENSUS" | jq -c '.result.consensus_params.validator.pub_key_types')
check "validator.pub_key_types" '["ed25519"]' "$PUB_KEY_TYPES"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 3. Staking
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 3. Staking"
echo ""
table_header

STAKING=$(rest "cosmos/staking/v1beta1/params")
BOND_DENOM=$(echo "$STAKING" | jq -r '.params.bond_denom')
check "bond_denom" "airl" "$BOND_DENOM"

UNBONDING=$(echo "$STAKING" | jq -r '.params.unbonding_time')
check "unbonding_time" "1814400s" "$UNBONDING"

MAX_VALS=$(echo "$STAKING" | jq -r '.params.max_validators')
check "max_validators" "100" "$MAX_VALS"

MAX_ENTRIES=$(echo "$STAKING" | jq -r '.params.max_entries')
check "max_entries" "7" "$MAX_ENTRIES"

HIST_ENTRIES=$(echo "$STAKING" | jq -r '.params.historical_entries')
check "historical_entries" "10000" "$HIST_ENTRIES"

MIN_COMMISSION=$(echo "$STAKING" | jq -r '.params.min_commission_rate')
check "min_commission_rate" "0.000000000000000000" "$MIN_COMMISSION"

echo ""
echo "### Validators"
echo ""
VALIDATORS=$(rest "cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED")
VAL_COUNT=$(echo "$VALIDATORS" | jq '.validators | length')
echo "**Bonded validators:** $VAL_COUNT"
echo ""
echo "| Moniker | Operator Address | Tokens | Commission |"
echo "|---------|-----------------|--------|------------|"
echo "$VALIDATORS" | jq -r '.validators[] | "| \(.description.moniker) | \(.operator_address) | \(.tokens) | \(.commission.commission_rates.rate) |"'

POOL=$(rest "cosmos/staking/v1beta1/pool")
BONDED=$(echo "$POOL" | jq -r '.pool.bonded_tokens')
NOT_BONDED=$(echo "$POOL" | jq -r '.pool.not_bonded_tokens')
echo ""
echo "**Staking pool:** bonded=\`$BONDED\` not_bonded=\`$NOT_BONDED\`"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 4. Mint
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 4. Mint"
echo ""
table_header

MINT=$(rest "cosmos/mint/v1beta1/params")
MINT_DENOM=$(echo "$MINT" | jq -r '.params.mint_denom')
check "mint_denom" "airl" "$MINT_DENOM"

INFLATION_CHANGE=$(echo "$MINT" | jq -r '.params.inflation_rate_change')
check "inflation_rate_change" "0.000000000000000000" "$INFLATION_CHANGE"

INFLATION_MAX=$(echo "$MINT" | jq -r '.params.inflation_max')
check "inflation_max" "0.030000000000000000" "$INFLATION_MAX"

INFLATION_MIN=$(echo "$MINT" | jq -r '.params.inflation_min')
check "inflation_min" "0.030000000000000000" "$INFLATION_MIN"

GOAL_BONDED=$(echo "$MINT" | jq -r '.params.goal_bonded')
check "goal_bonded" "0.010000000000000000" "$GOAL_BONDED"

BLOCKS_PER_YEAR=$(echo "$MINT" | jq -r '.params.blocks_per_year')
check "blocks_per_year" "6311520" "$BLOCKS_PER_YEAR"

INFLATION=$(rest "cosmos/mint/v1beta1/inflation")
CURRENT_INFLATION=$(echo "$INFLATION" | jq -r '.inflation')
check "current_inflation" "0.030000000000000000" "$CURRENT_INFLATION"

PROVISIONS=$(rest "cosmos/mint/v1beta1/annual_provisions")
ANNUAL_PROVISIONS=$(echo "$PROVISIONS" | jq -r '.annual_provisions')
record "annual_provisions" "$ANNUAL_PROVISIONS"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 5. Governance
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 5. Governance"
echo ""
table_header

GOV=$(rest "cosmos/gov/v1/params/deposit")
MIN_DEPOSIT=$(echo "$GOV" | jq -r '.params.min_deposit[0].amount')
check "min_deposit (airl)" "100000000000000000000000000" "$MIN_DEPOSIT"

MIN_DEPOSIT_DENOM=$(echo "$GOV" | jq -r '.params.min_deposit[0].denom')
check "min_deposit denom" "airl" "$MIN_DEPOSIT_DENOM"

EXPEDITED_DEPOSIT=$(echo "$GOV" | jq -r '.params.expedited_min_deposit[0].amount')
check "expedited_min_deposit (airl)" "500000000000000000000000000" "$EXPEDITED_DEPOSIT"

MAX_DEPOSIT_PERIOD=$(echo "$GOV" | jq -r '.params.max_deposit_period')
check "max_deposit_period" "604800s" "$MAX_DEPOSIT_PERIOD"

VOTING_PERIOD=$(echo "$GOV" | jq -r '.params.voting_period')
check "voting_period" "604800s" "$VOTING_PERIOD"

EXPEDITED_VOTING=$(echo "$GOV" | jq -r '.params.expedited_voting_period')
check "expedited_voting_period" "259200s" "$EXPEDITED_VOTING"

QUORUM=$(echo "$GOV" | jq -r '.params.quorum')
check "quorum" "0.334000000000000000" "$QUORUM"

THRESHOLD=$(echo "$GOV" | jq -r '.params.threshold')
check "threshold" "0.500000000000000000" "$THRESHOLD"

VETO=$(echo "$GOV" | jq -r '.params.veto_threshold')
check "veto_threshold" "0.334000000000000000" "$VETO"

MIN_INITIAL=$(echo "$GOV" | jq -r '.params.min_initial_deposit_ratio')
check "min_initial_deposit_ratio" "0.250000000000000000" "$MIN_INITIAL"

BURN_VETO=$(echo "$GOV" | jq -r '.params.burn_vote_veto')
check "burn_vote_veto" "true" "$BURN_VETO"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 6. Slashing
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 6. Slashing"
echo ""
table_header

SLASHING=$(rest "cosmos/slashing/v1beta1/params")
SIGNED_WINDOW=$(echo "$SLASHING" | jq -r '.params.signed_blocks_window')
check "signed_blocks_window" "10000" "$SIGNED_WINDOW"

MIN_SIGNED=$(echo "$SLASHING" | jq -r '.params.min_signed_per_window')
check "min_signed_per_window" "0.050000000000000000" "$MIN_SIGNED"

JAIL_DURATION=$(echo "$SLASHING" | jq -r '.params.downtime_jail_duration')
check "downtime_jail_duration" "600s" "$JAIL_DURATION"

SLASH_DOUBLE=$(echo "$SLASHING" | jq -r '.params.slash_fraction_double_sign')
check "slash_fraction_double_sign" "0.050000000000000000" "$SLASH_DOUBLE"

SLASH_DOWNTIME=$(echo "$SLASHING" | jq -r '.params.slash_fraction_downtime')
check "slash_fraction_downtime" "0.000100000000000000" "$SLASH_DOWNTIME"

echo ""
echo "### Validator Signing Infos"
echo ""
echo "| Validator | Missed Blocks | Tombstoned |"
echo "|-----------|--------------|------------|"

SIGNING=$(rest "cosmos/slashing/v1beta1/signing_infos")
echo "$SIGNING" | jq -r '.info[] | "| \(.address) | \(.missed_blocks_counter) | \(.jailed_until // "n/a") |"' 2>/dev/null || echo "| (unable to fetch) | — | — |"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 7. Distribution
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 7. Distribution"
echo ""
table_header

DISTR=$(rest "cosmos/distribution/v1beta1/params")
COMMUNITY_TAX=$(echo "$DISTR" | jq -r '.params.community_tax')
check "community_tax" "0.000000000000000000" "$COMMUNITY_TAX"

WITHDRAW_ENABLED=$(echo "$DISTR" | jq -r '.params.withdraw_addr_enabled')
check "withdraw_addr_enabled" "true" "$WITHDRAW_ENABLED"

COMMUNITY_POOL=$(rest "cosmos/distribution/v1beta1/community_pool")
POOL_AMOUNT=$(echo "$COMMUNITY_POOL" | jq -r '.pool[0].amount // "0"')
record "community_pool" "$POOL_AMOUNT"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 8. Bank
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 8. Bank"
echo ""
table_header

SUPPLY=$(rest "cosmos/bank/v1beta1/supply")
TOTAL_SUPPLY=$(echo "$SUPPLY" | jq -r '.supply[] | select(.denom == "airl") | .amount')
record "total_supply (airl)" "$TOTAL_SUPPLY"

METADATA=$(rest "cosmos/bank/v1beta1/denoms_metadata/airl")
META_BASE=$(echo "$METADATA" | jq -r '.metadata.base')
check "denom_metadata.base" "airl" "$META_BASE"

META_DISPLAY=$(echo "$METADATA" | jq -r '.metadata.display')
check "denom_metadata.display" "irl" "$META_DISPLAY"

META_NAME=$(echo "$METADATA" | jq -r '.metadata.name')
check "denom_metadata.name" "IRL" "$META_NAME"

META_SYMBOL=$(echo "$METADATA" | jq -r '.metadata.symbol')
check "denom_metadata.symbol" "IRL" "$META_SYMBOL"

META_DESC=$(echo "$METADATA" | jq -r '.metadata.description')
check "denom_metadata.description" "Integra Layer Native Token" "$META_DESC"

EXP_0=$(echo "$METADATA" | jq -r '.metadata.denom_units[] | select(.exponent == "0" or .exponent == 0) | .denom')
check "denom_unit exponent=0" "airl" "$EXP_0"

EXP_18=$(echo "$METADATA" | jq -r '.metadata.denom_units[] | select(.exponent == "18" or .exponent == 18) | .denom')
check "denom_unit exponent=18" "irl" "$EXP_18"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 9. Auth
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 9. Auth"
echo ""
table_header

AUTH=$(rest "cosmos/auth/v1beta1/params")
MAX_MEMO=$(echo "$AUTH" | jq -r '.params.max_memo_characters')
record "max_memo_characters" "$MAX_MEMO"

TX_SIG_LIMIT=$(echo "$AUTH" | jq -r '.params.tx_sig_limit')
record "tx_sig_limit" "$TX_SIG_LIMIT"

TX_SIZE_COST=$(echo "$AUTH" | jq -r '.params.tx_size_cost_per_byte')
record "tx_size_cost_per_byte" "$TX_SIZE_COST"

SIG_ED25519=$(echo "$AUTH" | jq -r '.params.sig_verify_cost_ed25519')
record "sig_verify_cost_ed25519" "$SIG_ED25519"

SIG_SECP256K1=$(echo "$AUTH" | jq -r '.params.sig_verify_cost_secp256k1')
record "sig_verify_cost_secp256k1" "$SIG_SECP256K1"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 10. EVM Module
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 10. EVM Module"
echo ""
table_header

EVM_PARAMS=$(rest "cosmos/evm/vm/v1/params")
EVM_DENOM=$(echo "$EVM_PARAMS" | jq -r '.params.evm_denom')
check "evm_denom" "airl" "$EVM_DENOM"

EXTRA_EIPS=$(echo "$EVM_PARAMS" | jq -c '.params.extra_eips')
check "extra_eips" "[]" "$EXTRA_EIPS"

# Check active static precompiles (9 expected)
PRECOMPILE_COUNT=$(echo "$EVM_PARAMS" | jq '.params.active_static_precompiles | length')
check "active_static_precompiles count" "9" "$PRECOMPILE_COUNT"

EXPECTED_PRECOMPILES=(
  "0x0000000000000000000000000000000000000100"
  "0x0000000000000000000000000000000000000400"
  "0x0000000000000000000000000000000000000800"
  "0x0000000000000000000000000000000000000801"
  "0x0000000000000000000000000000000000000802"
  "0x0000000000000000000000000000000000000803"
  "0x0000000000000000000000000000000000000804"
  "0x0000000000000000000000000000000000000805"
  "0x0000000000000000000000000000000000000806"
)
PRECOMPILE_NAMES=("P256" "Bech32" "Staking" "Distribution" "ICS20" "Vesting" "Bank" "Governance" "Slashing")

for i in "${!EXPECTED_PRECOMPILES[@]}"; do
  ADDR="${EXPECTED_PRECOMPILES[$i]}"
  NAME="${PRECOMPILE_NAMES[$i]}"
  FOUND=$(echo "$EVM_PARAMS" | jq -r --arg addr "$ADDR" '.params.active_static_precompiles[] | select(. == $addr)')
  if [[ -n "$FOUND" ]]; then
    echo "| precompile: $NAME | \`$ADDR\` | present | ✅ PASS |"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "| precompile: $NAME | \`$ADDR\` | missing | ❌ FAIL |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Access control
CREATE_ACCESS=$(echo "$EVM_PARAMS" | jq -r '.params.access_control.create.access_type // .params.access_control.create.AccessType // empty')
check_contains "access_control.create" "ACCESS_TYPE_PERMISSIONLESS" "$CREATE_ACCESS"

CALL_ACCESS=$(echo "$EVM_PARAMS" | jq -r '.params.access_control.call.access_type // .params.access_control.call.AccessType // empty')
check_contains "access_control.call" "ACCESS_TYPE_PERMISSIONLESS" "$CALL_ACCESS"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 11. Fee Market
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 11. Fee Market"
echo ""
table_header

FEEMARKET=$(rest "cosmos/evm/feemarket/v1/params")
NO_BASE_FEE=$(echo "$FEEMARKET" | jq -r '.params.no_base_fee')
check "no_base_fee" "false" "$NO_BASE_FEE"

BASE_FEE_DENOM=$(echo "$FEEMARKET" | jq -r '.params.base_fee_change_denominator')
check "base_fee_change_denominator" "8" "$BASE_FEE_DENOM"

ELASTICITY=$(echo "$FEEMARKET" | jq -r '.params.elasticity_multiplier')
check "elasticity_multiplier" "2" "$ELASTICITY"

BASE_FEE=$(echo "$FEEMARKET" | jq -r '.params.base_fee')
# base_fee may be returned with decimal suffix — strip it for comparison
BASE_FEE_INT="${BASE_FEE%%.*}"
check "base_fee" "5000000000000" "$BASE_FEE_INT"

MIN_GAS_PRICE=$(echo "$FEEMARKET" | jq -r '.params.min_gas_price')
check "min_gas_price" "5000000000000.000000000000000000" "$MIN_GAS_PRICE"

MIN_GAS_MULT=$(echo "$FEEMARKET" | jq -r '.params.min_gas_multiplier')
check "min_gas_multiplier" "0.500000000000000000" "$MIN_GAS_MULT"

ENABLE_HEIGHT=$(echo "$FEEMARKET" | jq -r '.params.enable_height')
check "enable_height" "0" "$ENABLE_HEIGHT"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 12. ERC-20
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 12. ERC-20"
echo ""
table_header

ERC20=$(rest "cosmos/evm/erc20/v1/params")
ENABLE_ERC20=$(echo "$ERC20" | jq -r '.params.enable_erc20')
check "enable_erc20" "true" "$ENABLE_ERC20"

PERMISSIONLESS=$(echo "$ERC20" | jq -r '.params.permissionless_registration')
check "permissionless_registration" "false" "$PERMISSIONLESS"

echo ""
echo "### Token Pairs"
echo ""

TOKEN_PAIRS=$(rest "cosmos/evm/erc20/v1/token_pairs")
WIRL_ADDR=$(echo "$TOKEN_PAIRS" | jq -r '.token_pairs[] | select(.denom == "airl") | .erc20_address')
check "WIRL erc20_address" "0xD4949664cD82660AaE99bEdc034a0deA8A0bd517" "$WIRL_ADDR"

WIRL_DENOM=$(echo "$TOKEN_PAIRS" | jq -r '.token_pairs[] | select(.denom == "airl") | .denom')
check "WIRL denom" "airl" "$WIRL_DENOM"

WIRL_ENABLED=$(echo "$TOKEN_PAIRS" | jq -r '.token_pairs[] | select(.denom == "airl") | .enabled')
check "WIRL enabled" "true" "$WIRL_ENABLED"

WIRL_OWNER=$(echo "$TOKEN_PAIRS" | jq -r '.token_pairs[] | select(.denom == "airl") | .contract_owner')
check "WIRL contract_owner" "OWNER_MODULE" "$WIRL_OWNER"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 13. IBC
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 13. IBC"
echo ""
table_header

IBC_CLIENTS=$(rest "ibc/core/client/v1/client_states" 2>/dev/null || echo '{"client_states":[]}')
CLIENT_COUNT=$(echo "$IBC_CLIENTS" | jq '.client_states | length')
record "ibc_clients" "$CLIENT_COUNT"

IBC_CONNECTIONS=$(rest "ibc/core/connection/v1/connections" 2>/dev/null || echo '{"connections":[]}')
CONN_COUNT=$(echo "$IBC_CONNECTIONS" | jq '.connections | length')
record "ibc_connections" "$CONN_COUNT"

IBC_CHANNELS=$(rest "ibc/core/channel/v1/channels" 2>/dev/null || echo '{"channels":[]}')
CHAN_COUNT=$(echo "$IBC_CHANNELS" | jq '.channels | length')
record "ibc_channels" "$CHAN_COUNT"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 14. EVM Verification
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 14. EVM Verification"
echo ""

echo "### Gas Prices"
echo ""
table_header

GAS_PRICE_HEX=$(evm_call "eth_gasPrice" "")
GAS_PRICE_DEC=$((16#${GAS_PRICE_HEX#0x}))
GAS_PRICE_GWEI=$((GAS_PRICE_DEC / 1000000000))
check_numeric_gte "eth_gasPrice (gwei)" 5000 "$GAS_PRICE_GWEI"

MAX_PRIORITY_HEX=$(evm_call "eth_maxPriorityFeePerGas" "" 2>/dev/null || echo "")
if [[ -n "$MAX_PRIORITY_HEX" && "$MAX_PRIORITY_HEX" != "null" ]]; then
  record "eth_maxPriorityFeePerGas" "$MAX_PRIORITY_HEX"
else
  record "eth_maxPriorityFeePerGas" "not supported"
fi

echo ""
echo "### Precompile Code Verification"
echo ""
table_header

for i in "${!EXPECTED_PRECOMPILES[@]}"; do
  ADDR="${EXPECTED_PRECOMPILES[$i]}"
  NAME="${PRECOMPILE_NAMES[$i]}"
  CODE=$(evm_call "eth_getCode" "\"$ADDR\", \"latest\"")
  # Precompiles return empty code but should be callable — just check they don't error
  if [[ -n "$CODE" ]]; then
    echo "| $NAME ($ADDR) | responds | \`${CODE:0:20}${CODE:20:+...}\` | ✅ PASS |"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "| $NAME ($ADDR) | responds | error | ❌ FAIL |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo ""
echo "### Preinstalled Contract Code Verification"
echo ""
table_header

PREINSTALL_NAMES=("Create2" "Multicall3" "Permit2" "Safe singleton factory" "EIP-2935")
PREINSTALL_ADDRS=(
  "0x4e59b44847b379578588920ca78fbf26c0b4956c"
  "0xcA11bde05977b3631167028862bE2a173976CA11"
  "0x000000000022D473030F116dDEE9F6B43aC78BA3"
  "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7"
  "0x0000F90827F1C53a10cb7A02335B175320002935"
)

for i in "${!PREINSTALL_NAMES[@]}"; do
  NAME="${PREINSTALL_NAMES[$i]}"
  ADDR="${PREINSTALL_ADDRS[$i]}"
  CODE=$(evm_call "eth_getCode" "\"$ADDR\", \"latest\"")
  if [[ -n "$CODE" && "$CODE" != "0x" && "$CODE" != "null" ]]; then
    CODE_LEN=${#CODE}
    echo "| $NAME | has code | \`${CODE:0:20}...\` (${CODE_LEN} chars) | ✅ PASS |"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "| $NAME ($ADDR) | has code | \`$CODE\` | ❌ FAIL |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo ""
echo "### WIRL Contract Verification"
echo ""
table_header

WIRL_CONTRACT="0xD4949664cD82660AaE99bEdc034a0deA8A0bd517"
WIRL_CODE=$(evm_call "eth_getCode" "\"$WIRL_CONTRACT\", \"latest\"")
check_not_empty "WIRL contract code" "$WIRL_CODE"

# name() call
WIRL_NAME_HEX=$(evm_call "eth_call" "{\"to\":\"$WIRL_CONTRACT\",\"data\":\"0x06fdde03\"}, \"latest\"")
if [[ -n "$WIRL_NAME_HEX" && "$WIRL_NAME_HEX" != "null" && "$WIRL_NAME_HEX" != "0x" ]]; then
  # Decode ABI-encoded string: skip 0x + 64 chars offset + 64 chars length, then take the hex string
  HEX_DATA="${WIRL_NAME_HEX#0x}"
  # Get length from bytes 32-63 (chars 64-127)
  STR_LEN_HEX="${HEX_DATA:64:64}"
  STR_LEN=$((16#$STR_LEN_HEX))
  # Get string data starting at byte 64 (char 128)
  STR_HEX="${HEX_DATA:128:$((STR_LEN * 2))}"
  WIRL_NAME=$(echo "$STR_HEX" | xxd -r -p 2>/dev/null || echo "decode_error")
  record "WIRL name()" "$WIRL_NAME"
else
  record "WIRL name()" "error: $WIRL_NAME_HEX"
fi

# symbol() call
WIRL_SYMBOL_HEX=$(evm_call "eth_call" "{\"to\":\"$WIRL_CONTRACT\",\"data\":\"0x95d89b41\"}, \"latest\"")
if [[ -n "$WIRL_SYMBOL_HEX" && "$WIRL_SYMBOL_HEX" != "null" && "$WIRL_SYMBOL_HEX" != "0x" ]]; then
  HEX_DATA="${WIRL_SYMBOL_HEX#0x}"
  STR_LEN_HEX="${HEX_DATA:64:64}"
  STR_LEN=$((16#$STR_LEN_HEX))
  STR_HEX="${HEX_DATA:128:$((STR_LEN * 2))}"
  WIRL_SYMBOL=$(echo "$STR_HEX" | xxd -r -p 2>/dev/null || echo "decode_error")
  record "WIRL symbol()" "$WIRL_SYMBOL"
else
  record "WIRL symbol()" "error: $WIRL_SYMBOL_HEX"
fi

# decimals() call
WIRL_DEC_HEX=$(evm_call "eth_call" "{\"to\":\"$WIRL_CONTRACT\",\"data\":\"0x313ce567\"}, \"latest\"")
if [[ -n "$WIRL_DEC_HEX" && "$WIRL_DEC_HEX" != "null" && "$WIRL_DEC_HEX" != "0x" ]]; then
  WIRL_DECIMALS=$((16#${WIRL_DEC_HEX#0x}))
  check "WIRL decimals()" "18" "$WIRL_DECIMALS"
else
  echo "| WIRL decimals() | 18 | error | ❌ FAIL |"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 15. WebSocket
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 15. WebSocket"
echo ""
table_header

# Use websocat, or node with built-in WebSocket (Node 22+), or skip
if command -v websocat &>/dev/null; then
  WS_RESULT=$(echo '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | timeout 10 websocat "$WS" 2>/dev/null | jq -r '.result' || echo "error")
  check "ws eth_chainId" "0x6669" "$WS_RESULT"
elif command -v node &>/dev/null; then
  WS_RESULT=$(timeout 10 node -e "
    const ws = new WebSocket('$WS');
    ws.onopen = () => ws.send(JSON.stringify({jsonrpc:'2.0',method:'eth_chainId',params:[],id:1}));
    ws.onmessage = (e) => { console.log(JSON.parse(e.data).result); ws.close(); };
    ws.onerror = (e) => { console.log('error'); process.exit(1); };
    setTimeout(() => { console.log('timeout'); process.exit(1); }, 8000);
  " 2>/dev/null || echo "error")
  if [[ "$WS_RESULT" == "0x6669" ]]; then
    check "ws eth_chainId" "0x6669" "$WS_RESULT"
  else
    echo "| ws eth_chainId | \`0x6669\` | \`$WS_RESULT\` (Node built-in WS may not support wss://) | ⚠️ WARN |"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
else
  echo "| ws eth_chainId | 0x6669 | skipped (no ws client) | ⚠️ WARN |"
  WARN_COUNT=$((WARN_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 16. Node Config (SSH)
# ═══════════════════════════════════════════════════════════════════════════════
echo "## 16. Node Config (via SSH)"
echo ""
table_header

if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_HOST" "test -f /root/.intgd/config/app.toml" 2>/dev/null; then
  MIN_GAS_PRICES=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$SSH_HOST" "grep '^minimum-gas-prices' /root/.intgd/config/app.toml" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '"')
  record "minimum-gas-prices" "$MIN_GAS_PRICES"

  PRUNING=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$SSH_HOST" "grep '^pruning ' /root/.intgd/config/app.toml" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d '"')
  record "pruning" "$PRUNING"

  JSON_RPC_API=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$SSH_HOST" "grep '^api ' /root/.intgd/config/app.toml" 2>/dev/null | head -1 | awk -F'= ' '{print $2}' | tr -d '"')
  record "json-rpc api" "$JSON_RPC_API"

  TELEMETRY=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$SSH_HOST" "grep -A2 '^\[telemetry\]' /root/.intgd/config/app.toml" 2>/dev/null | grep 'enabled' | head -1 | awk -F'= ' '{print $2}' | tr -d ' ')
  record "telemetry.enabled" "$TELEMETRY"
else
  echo "| SSH to gateway | accessible | connection failed | ⚠️ WARN |"
  WARN_COUNT=$((WARN_COUNT + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo "---"
echo ""
echo "## Summary"
echo ""
echo "| Status | Count |"
echo "|--------|-------|"
echo "| ✅ PASS | $PASS_COUNT |"
echo "| ❌ FAIL | $FAIL_COUNT |"
echo "| ⚠️ WARN | $WARN_COUNT |"
echo "| 📋 RECORD | $RECORD_COUNT |"
echo "| **Total** | **$((PASS_COUNT + FAIL_COUNT + WARN_COUNT + RECORD_COUNT))** |"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "**Result: ALL CHECKS PASSED** ✅"
else
  echo "**Result: $FAIL_COUNT FAILURES DETECTED** ❌"
  echo ""
  echo "Review failed checks above and investigate discrepancies."
fi
