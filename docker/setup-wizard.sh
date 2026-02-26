#!/bin/bash
set -e

# Source testable functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$SCRIPT_DIR/lib.sh"
elif [ -f /usr/local/bin/lib.sh ]; then
  source /usr/local/bin/lib.sh
fi

BOLD='\033[1m' GREEN='\033[0;32m' CYAN='\033[0;36m'
YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'

banner() {
  echo -e "${CYAN}"
  echo "  +-----------------------------------------+"
  echo "  |   Integra Layer -- Validator Setup       |"
  echo "  +-----------------------------------------+"
  echo -e "${NC}"
}

banner

# --- Network selection ---
echo -e "${BOLD}Select network:${NC}"
echo "  [1] Mainnet (integra-1)"
echo "  [2] Testnet (integra-testnet-1)"
read -rp "Choice [1]: " NETWORK_CHOICE
NETWORK_CHOICE=${NETWORK_CHOICE:-1}

set_network_config "$NETWORK_CHOICE"

# --- Validator metadata ---
echo ""
echo -e "${BOLD}Validator details:${NC}"
read -rp "  Moniker (name): " MONIKER
read -rp "  Description: " DESCRIPTION
read -rp "  Website (optional): " WEBSITE
read -rp "  Commission rate % [5]: " COMMISSION
COMMISSION=${COMMISSION:-5}
COMMISSION_DEC=$(commission_to_decimal "$COMMISSION")

# --- Initialize node ---
echo -e "\n${CYAN}Initializing node...${NC}"
intgd init "$MONIKER" --chain-id "$CHAIN_ID" --home /root/.intgd 2>/dev/null

# --- Wallet setup ---
echo ""
echo -e "${BOLD}Wallet setup:${NC}"
echo "  [1] Generate new wallet"
echo "  [2] Import existing mnemonic (24 words)"
echo "  [3] Import EVM private key (hex)"
read -rp "Choice [1]: " WALLET_CHOICE
WALLET_CHOICE=${WALLET_CHOICE:-1}

if [ "$WALLET_CHOICE" = "1" ]; then
  echo -e "\n${YELLOW}SAVE THIS MNEMONIC -- YOU CANNOT RECOVER IT LATER${NC}\n"
  intgd keys add validator --keyring-backend file --home /root/.intgd 2>&1
elif [ "$WALLET_CHOICE" = "2" ]; then
  echo -e "\nEnter your mnemonic (24 words):"
  read -rp "> " MNEMONIC
  echo "$MNEMONIC" | intgd keys recover validator --keyring-backend file --home /root/.intgd
elif [ "$WALLET_CHOICE" = "3" ]; then
  echo -e "\nEnter your EVM private key (hex, with or without 0x prefix):"
  read -rp "> " HEX_KEY
  # Strip 0x prefix if present
  HEX_KEY="${HEX_KEY#0x}"
  echo -e "\n${YELLOW}Note: intgd will prompt you to set a keyring passphrase.${NC}"
  intgd keys unsafe-import-eth-key validator "$HEX_KEY" --keyring-backend file --home /root/.intgd
fi

VALIDATOR_ADDR=$(intgd keys show validator -a --keyring-backend file --home /root/.intgd)
VALOPER_ADDR=$(intgd keys show validator --bech val -a --keyring-backend file --home /root/.intgd)
echo -e "\n${GREEN}Wallet address: ${VALIDATOR_ADDR}${NC}"
echo -e "${GREEN}Valoper address: ${VALOPER_ADDR}${NC}"

# --- Download genesis (skip for fresh chain bootstrapping) ---
echo ""
echo -e "${BOLD}Genesis setup:${NC}"
echo "  [1] Download genesis from RPC (joining existing chain)"
echo "  [2] Use locally generated genesis (bootstrapping new chain)"
echo "  [3] Genesis ceremony participant (generate gentx for coordinator)"
read -rp "Choice [1]: " GENESIS_CHOICE
GENESIS_CHOICE=${GENESIS_CHOICE:-1}

if [ "$GENESIS_CHOICE" = "1" ]; then
  echo -e "\n${CYAN}Downloading genesis...${NC}"
  if curl -sf "${RPC_URL}/genesis" | jq '.result.genesis' > /root/.intgd/config/genesis.json; then
    echo -e "${GREEN}Genesis downloaded (chain: $(jq -r '.chain_id' /root/.intgd/config/genesis.json))${NC}"
  else
    echo -e "${RED}Failed to download genesis from ${RPC_URL}${NC}"
    echo -e "${YELLOW}You will need to manually place genesis.json in /root/.intgd/config/${NC}"
  fi
elif [ "$GENESIS_CHOICE" = "3" ]; then
  echo -e "\n${CYAN}Genesis ceremony mode${NC}"
  echo -e "${YELLOW}The coordinator will provide the genesis file. For now, using the default genesis.${NC}"
  echo -e "${YELLOW}Replace /root/.intgd/config/genesis.json with the coordinator's genesis before generating gentx.${NC}"
  read -rp "  Self-delegation amount in IRL [1000]: " SELF_DELEGATION
  SELF_DELEGATION=${SELF_DELEGATION:-1000}
  # Convert IRL to airl (18 decimals)
  SELF_DELEGATION_AIRL="${SELF_DELEGATION}000000000000000000"

  echo -e "\n${CYAN}Generating gentx...${NC}"
  intgd genesis gentx validator "${SELF_DELEGATION_AIRL}${DENOM}" \
    --chain-id "$CHAIN_ID" \
    --moniker "$MONIKER" \
    --commission-rate "$COMMISSION_DEC" \
    --commission-max-rate "0.20" \
    --commission-max-change-rate "0.01" \
    --min-self-delegation "${SELF_DELEGATION_AIRL}" \
    --keyring-backend file \
    --home /root/.intgd

  GENTX_FILE=$(ls /root/.intgd/config/gentx/*.json 2>/dev/null | head -1)
  echo ""
  echo -e "${GREEN}+-----------------------------------------+${NC}"
  echo -e "${GREEN}|   Gentx generated!                      |${NC}"
  echo -e "${GREEN}+-----------------------------------------+${NC}"
  echo ""
  echo -e "  Gentx file: ${BOLD}${GENTX_FILE}${NC}"
  echo ""
  echo -e "  ${YELLOW}Next steps:${NC}"
  echo -e "  1. Send your gentx file to the genesis coordinator"
  echo -e "  2. Wait for the coordinator to distribute the final genesis"
  echo -e "  3. Replace /root/.intgd/config/genesis.json with the final genesis"
  echo -e "  4. Restart: docker compose up"
  echo ""
  exit 0
else
  echo -e "${YELLOW}Using genesis generated by 'intgd init'. Replace it before starting if needed.${NC}"
fi

# --- Configure node ---
echo -e "\n${CYAN}Configuring node...${NC}"
configure_toml /root/.intgd "$CHAIN_ID" "$EVM_CHAIN_ID" "$DENOM" "$SEEDS"

# State sync (for fast catch-up on existing chains)
if [ "$GENESIS_CHOICE" = "1" ]; then
  LATEST_HEIGHT=$(curl -sf "${RPC_URL}/block" | jq -r '.result.block.header.height' 2>/dev/null || echo "0")
  if [ "$LATEST_HEIGHT" -gt 1000 ] 2>/dev/null; then
    TRUST_HEIGHT=$((LATEST_HEIGHT - 1000))
    TRUST_HASH=$(curl -sf "${RPC_URL}/block?height=${TRUST_HEIGHT}" | jq -r '.result.block_id.hash' 2>/dev/null || echo "")

    if [ -n "$TRUST_HASH" ] && [ "$TRUST_HASH" != "null" ]; then
      configure_state_sync /root/.intgd "$RPC_URL" "$TRUST_HEIGHT" "$TRUST_HASH"
      echo -e "${GREEN}State sync enabled (trust height: ${TRUST_HEIGHT})${NC}"
    fi
  fi
fi

echo -e "${GREEN}Node configured${NC}"

# --- Save validator.json for later ---
PUBKEY=$(intgd comet show-validator --home /root/.intgd)
generate_validator_json /root/validator.json "$PUBKEY" "$DENOM" "$MONIKER" "$WEBSITE" "$DESCRIPTION" "$COMMISSION_DEC"

# --- Done ---
echo ""
echo -e "${GREEN}+-----------------------------------------+${NC}"
echo -e "${GREEN}|   Setup complete!                       |${NC}"
echo -e "${GREEN}+-----------------------------------------+${NC}"
echo ""
echo -e "  Network:    ${BOLD}${CHAIN_ID}${NC}"
echo -e "  Moniker:    ${BOLD}${MONIKER}${NC}"
echo -e "  Wallet:     ${BOLD}${VALIDATOR_ADDR}${NC}"
echo -e "  Valoper:    ${BOLD}${VALOPER_ADDR}${NC}"
echo -e "  Commission: ${BOLD}${COMMISSION}%${NC}"
echo ""
echo -e "  ${CYAN}Next steps:${NC}"
echo -e "  1. Start the node:  docker start integra-validator"
echo -e "  2. Wait for sync:   docker exec integra-validator intgd status | jq '.sync_info.catching_up'"
echo -e "  3. Fund your wallet with IRL tokens (contact Foundation)"
echo -e "  4. Edit /root/validator.json -- set 'amount' to your self-stake"
echo -e "  5. Create validator:"
echo -e "     docker exec -it integra-validator intgd tx staking create-validator /root/validator.json \\"
echo -e "       --from validator --gas-prices 5000000000000${DENOM} --gas auto --gas-adjustment 1.3 \\"
echo -e "       --keyring-backend file --chain-id ${CHAIN_ID} -y"
echo ""
