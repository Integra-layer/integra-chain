# Integra Layer — Deployment Runbook

Step-by-step guide to deploy Integra mainnet + testnet from scratch.

**Prerequisites already done:**
- integra-chain repo ready with custom genesis, Docker, ops scripts
- `intgd` binary builds successfully (`make build`)
- 40 bats tests passing
- GitHub Actions CI configured

---

## Phase 1: Server Provisioning

### 1.1 — Inventory

You need 4 servers per network (8 total). Two are reused, four are new.

**Mainnet:**

| Node | Provider | Role | Status |
|------|----------|------|--------|
| foundation-1 | Hetzner Helsinki | RPC (primary) | Reuse 89.167.55.161 |
| foundation-2 | AWS us-east-1 | RPC (archive) | Reuse 3.92.110.107 |
| foundation-3 | Hetzner Falkenstein | Signing-only | **NEW — order this** |
| foundation-4 | OVH/Vultr Paris | Signing-only | **NEW — order this** |

**Testnet:** Colocated on same servers (different ports/home dir) or separate VPS.

**Minimum specs per server:** 4 vCPU, 16 GB RAM, 500 GB NVMe SSD, Ubuntu 24.04

### 1.2 — Order new servers

**Hetzner (foundation-3):**
1. Go to https://console.hetzner.cloud
2. Create new server -> Location: Falkenstein -> Type: CX32 (~$15/mo)
3. OS: Ubuntu 24.04 -> SSH key: your key -> Name: `foundation-3`
4. Note the IP: `________`

**OVH/Vultr (foundation-4):**
1. Order B2-30 or equivalent (~$25/mo)
2. OS: Ubuntu 24.04 -> SSH key: your key -> Name: `foundation-4`
3. Note the IP: `________`

### 1.3 — Prepare existing servers

**foundation-1 (89.167.55.161 — Hetzner Helsinki, Piyush's N1):**
```bash
ssh root@89.167.55.161

# Stop old chain
pkill intgd || true
# Backup old data
mv /root/.intgd /root/.intgd-old-$(date +%Y%m%d) 2>/dev/null || true
```

**foundation-2 (3.92.110.107 — AWS, Adam's node):**
```bash
ssh -i ~/.ssh/integra-validator-key.pem ubuntu@3.92.110.107

# Stop old chain
sudo systemctl stop intgd || true
sudo pkill intgd || true
# Backup old data
sudo mv /root/.intgd /root/.intgd-old-$(date +%Y%m%d) 2>/dev/null || true
```

---

## Phase 2: Deploy Binary to All Nodes

### 2.1 — Build the binary (on your Mac)

```bash
cd ~/projects/integra-chain
make build
file build/intgd
# Must show: ELF 64-bit ... for linux — if it shows Mach-O, you need cross-compile
```

**Cross-compile for Linux (if on Mac):**
```bash
cd integra
CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o ../build/intgd-linux ./cmd/intgd
```

**Or build on the server directly:**
```bash
# On each server:
apt-get update && apt-get install -y golang-go git make build-essential
git clone https://github.com/Integra-layer/integra-chain.git
cd integra-chain
make build
cp build/intgd /usr/local/bin/intgd
intgd version
```

### 2.2 — Deploy to all servers

```bash
# From your Mac — repeat for each server:
SERVERS="89.167.55.161 3.92.110.107 <FOUNDATION-3-IP> <FOUNDATION-4-IP>"

for SERVER in $SERVERS; do
  echo "Deploying to $SERVER..."
  scp build/intgd-linux root@$SERVER:/usr/local/bin/intgd
  ssh root@$SERVER "chmod +x /usr/local/bin/intgd && intgd version"
done
```

### 2.3 — Verify on each server

```bash
intgd version
# Should show the version from integra-chain repo
```

---

## Phase 3: Genesis Ceremony

This is the critical phase. One coordinator node (foundation-1) builds the genesis, others contribute their gentx.

### 3.1 — Copy ops scripts to coordinator

```bash
scp ops/genesis-builder.sh root@89.167.55.161:/usr/local/bin/genesis-builder
ssh root@89.167.55.161 "chmod +x /usr/local/bin/genesis-builder"
```

### 3.2 — Initialize on coordinator (foundation-1)

```bash
ssh root@89.167.55.161

# Initialize the node
intgd init foundation-1 --chain-id integra-1 --home /root/.intgd
```

### 3.3 — Generate keys on EVERY node

On each server, generate a validator key:

```bash
# foundation-1:
intgd keys add validator --keyring-backend file --home /root/.intgd
# SAVE THE MNEMONIC!
# Note the address: integra1________

# foundation-2:
intgd keys add validator --keyring-backend file --home /root/.intgd
# Note the address: integra1________

# foundation-3:
intgd keys add validator --keyring-backend file --home /root/.intgd
# Note the address: integra1________

# foundation-4:
intgd keys add validator --keyring-backend file --home /root/.intgd
# Note the address: integra1________
```

Also generate the treasury key (on foundation-1 only):
```bash
intgd keys add foundation-treasury --keyring-backend file --home /root/.intgd
# SAVE THIS MNEMONIC — this controls 99.999B IRL
# Note the address: integra1________
```

### 3.4 — Fill in addresses and add genesis accounts (on coordinator)

```bash
ssh root@89.167.55.161

# Set the addresses you collected above
export TREASURY_ADDR="integra1..."
export VALIDATOR_ADDRS="integra1... integra1... integra1... integra1..."

# Add treasury account: 99,999,996,000 IRL
intgd genesis add-genesis-account $TREASURY_ADDR 99999996000000000000000000000airl --home /root/.intgd

# Add each validator account: 1,000 IRL each
for ADDR in $VALIDATOR_ADDRS; do
  intgd genesis add-genesis-account $ADDR 1000000000000000000000airl --home /root/.intgd
done
```

### 3.5 — Inject denom metadata (on coordinator)

```bash
GENESIS="/root/.intgd/config/genesis.json"
TMP=$(mktemp)

jq '.app_state.bank.denom_metadata = [{
  "description": "Integra Layer Native Token",
  "denom_units": [
    { "denom": "airl", "exponent": 0, "aliases": ["attoirl"] },
    { "denom": "irl", "exponent": 18, "aliases": ["IRL"] }
  ],
  "base": "airl",
  "display": "irl",
  "name": "Integra",
  "symbol": "IRL"
}]' "$GENESIS" > "$TMP" && mv "$TMP" "$GENESIS"
```

### 3.6 — Distribute genesis to all nodes

```bash
# From foundation-1, copy genesis to all other nodes:
scp /root/.intgd/config/genesis.json root@3.92.110.107:/root/.intgd/config/genesis.json
scp /root/.intgd/config/genesis.json root@<FOUNDATION-3-IP>:/root/.intgd/config/genesis.json
scp /root/.intgd/config/genesis.json root@<FOUNDATION-4-IP>:/root/.intgd/config/genesis.json
```

### 3.7 — Create gentx on EVERY node

Each validator creates their own gentx:

```bash
# On foundation-1:
intgd genesis gentx validator 1000000000000000000000airl \
  --chain-id integra-1 --moniker "Foundation-1" \
  --commission-rate 0.05 --commission-max-rate 0.20 --commission-max-change-rate 0.01 \
  --min-self-delegation 1000000000000000000000 \
  --keyring-backend file --home /root/.intgd

# On foundation-2: (same with --moniker "Foundation-2")
# On foundation-3: (same with --moniker "Foundation-3")
# On foundation-4: (same with --moniker "Foundation-4")
```

### 3.8 — Collect gentxs on coordinator

```bash
# Copy gentx files FROM each node TO foundation-1
scp root@3.92.110.107:/root/.intgd/config/gentx/*.json /root/.intgd/config/gentx/
scp root@<FOUNDATION-3-IP>:/root/.intgd/config/gentx/*.json /root/.intgd/config/gentx/
scp root@<FOUNDATION-4-IP>:/root/.intgd/config/gentx/*.json /root/.intgd/config/gentx/

# Verify 4 gentx files
ls /root/.intgd/config/gentx/
# Should show 4 files

# Collect them into genesis
intgd genesis collect-gentxs --home /root/.intgd
```

### 3.9 — Validate genesis

```bash
intgd genesis validate --home /root/.intgd
# Must output: genesis file is valid
```

### 3.10 — Distribute FINAL genesis to all nodes

```bash
# The genesis now includes all gentxs. Redistribute:
scp /root/.intgd/config/genesis.json root@3.92.110.107:/root/.intgd/config/genesis.json
scp /root/.intgd/config/genesis.json root@<FOUNDATION-3-IP>:/root/.intgd/config/genesis.json
scp /root/.intgd/config/genesis.json root@<FOUNDATION-4-IP>:/root/.intgd/config/genesis.json
```

---

## Phase 4: Configure Nodes

### 4.1 — Get node IDs (on each server)

```bash
intgd comet show-node-id --home /root/.intgd
# Note the ID: ________________
```

### 4.2 — Build persistent_peers string

Format: `<id>@<ip>:26656`

```
PEERS="<id1>@89.167.55.161:26656,<id2>@3.92.110.107:26656,<id3>@<F3-IP>:26656,<id4>@<F4-IP>:26656"
```

### 4.3 — Apply config on ALL nodes

```bash
HOME_DIR="/root/.intgd"

# persistent_peers
sed -i "s/persistent_peers = \"\"/persistent_peers = \"${PEERS}\"/" $HOME_DIR/config/config.toml

# minimum-gas-prices
sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "5000000000000airl"/' $HOME_DIR/config/app.toml

# evm_chain_id (fix default 262144 -> 26217)
sed -i 's/evm_chain_id = "262144"/evm_chain_id = "26217"/' $HOME_DIR/config/app.toml

# client.toml
sed -i 's/chain-id = ""/chain-id = "integra-1"/' $HOME_DIR/config/client.toml
```

### 4.4 — RPC nodes only (foundation-1, foundation-2)

```bash
# Enable REST API
sed -i '/\[api\]/,/\[/ s/enable = false/enable = true/' $HOME_DIR/config/app.toml

# Enable JSON-RPC
sed -i '/\[json-rpc\]/,/\[/ s/enable = false/enable = true/' $HOME_DIR/config/app.toml

# Enable state sync snapshots
sed -i 's/snapshot-interval = 0/snapshot-interval = 1000/' $HOME_DIR/config/app.toml
```

### 4.5 — Signing-only nodes (foundation-3, foundation-4)

```bash
# Aggressive pruning
sed -i 's/pruning = "default"/pruning = "everything"/' $HOME_DIR/config/app.toml

# Disable APIs (not public-facing)
sed -i '/\[json-rpc\]/,/\[/ s/enable = true/enable = false/' $HOME_DIR/config/app.toml

# Disable tx indexer
sed -i 's/indexer = "kv"/indexer = "null"/' $HOME_DIR/config/config.toml
```

---

## Phase 5: Launch

### 5.1 — Create systemd service (on ALL nodes)

```bash
cat > /etc/systemd/system/intgd.service << 'EOF'
[Unit]
Description=Integra Layer Node
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/intgd start --home /root/.intgd
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=append:/var/log/intgd/node.log
StandardError=append:/var/log/intgd/error.log

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /var/log/intgd
systemctl daemon-reload
systemctl enable intgd
```

### 5.2 — Start all 4 nodes within 60 seconds of each other

```bash
# On ALL 4 servers, run as close together as possible:
systemctl start intgd
```

Tip: Open 4 terminal tabs, type the command in each, then hit Enter rapidly.

### 5.3 — Monitor logs

```bash
journalctl -u intgd -f
# Or:
tail -f /var/log/intgd/node.log
```

What to look for:
- "Committed state" messages = blocks are being produced
- "Executed block" with increasing heights = chain is alive
- No "ERR" or "panic" messages

### 5.4 — Verify chain is producing blocks

```bash
intgd status --home /root/.intgd | jq '.sync_info.latest_block_height'
# Run twice, 10 seconds apart — height should increase

intgd status --home /root/.intgd | jq '.sync_info.catching_up'
# Should be false
```

### 5.5 — Verify all 4 validators are active

```bash
intgd query staking validators --home /root/.intgd -o json | \
  jq '.validators[] | {moniker: .description.moniker, status, tokens}'
```

Expected: 4 validators, all status `BOND_STATUS_BONDED`, tokens ~1000000000000000000000 each.

---

## Phase 6: Post-Launch Delegation

### 6.1 — Get all valoper addresses

```bash
intgd query staking validators --home /root/.intgd -o json | \
  jq -r '.validators[] | "\(.description.moniker): \(.operator_address)"'
```

### 6.2 — Delegate 250M IRL from treasury to each validator

Run on foundation-1 (where treasury key lives):

```bash
AMOUNT="250000000000000000000000000000airl"  # 250,000,000 IRL

# Delegate to each — replace valoper addresses:
intgd tx staking delegate <valoper1> $AMOUNT \
  --from foundation-treasury --gas-prices 5000000000000airl --gas auto --gas-adjustment 1.3 \
  --keyring-backend file --chain-id integra-1 --home /root/.intgd -y

sleep 6  # wait for block

intgd tx staking delegate <valoper2> $AMOUNT \
  --from foundation-treasury --gas-prices 5000000000000airl --gas auto --gas-adjustment 1.3 \
  --keyring-backend file --chain-id integra-1 --home /root/.intgd -y

sleep 6

intgd tx staking delegate <valoper3> $AMOUNT \
  --from foundation-treasury --gas-prices 5000000000000airl --gas auto --gas-adjustment 1.3 \
  --keyring-backend file --chain-id integra-1 --home /root/.intgd -y

sleep 6

intgd tx staking delegate <valoper4> $AMOUNT \
  --from foundation-treasury --gas-prices 5000000000000airl --gas auto --gas-adjustment 1.3 \
  --keyring-backend file --chain-id integra-1 --home /root/.intgd -y
```

### 6.3 — Verify voting power distribution

```bash
intgd query staking validators --home /root/.intgd -o json | \
  jq '.validators[] | {moniker: .description.moniker, tokens, delegator_shares}'
```

Expected: ~250,001,000 IRL each, ~25% VP each.

---

## Phase 7: DNS and Public Endpoints

### 7.1 — Install Caddy on RPC nodes (foundation-1 and foundation-2)

```bash
apt-get update && apt-get install -y caddy
```

### 7.2 — Caddyfile for foundation-1 (primary RPC)

```bash
cat > /etc/caddy/Caddyfile << 'EOF'
rpc.integralayer.com {
  reverse_proxy 127.0.0.1:26657
}

rest.integralayer.com {
  reverse_proxy 127.0.0.1:1317
}

evm.integralayer.com {
  reverse_proxy 127.0.0.1:8545
}

ws.integralayer.com {
  reverse_proxy 127.0.0.1:8546
}
EOF

systemctl restart caddy
```

### 7.3 — Update DNS (Route53 or your DNS provider)

Create A records:
- `rpc.integralayer.com` -> foundation-1 IP
- `rest.integralayer.com` -> foundation-1 IP
- `evm.integralayer.com` -> foundation-1 IP
- `ws.integralayer.com` -> foundation-1 IP

---

## Phase 8: Cosmovisor (Auto-Upgrades)

Run on each validator after the chain is stable:

```bash
scp ops/cosmovisor-setup.sh root@<SERVER>:/usr/local/bin/cosmovisor-setup
ssh root@<SERVER> "chmod +x /usr/local/bin/cosmovisor-setup && cosmovisor-setup"
```

---

## Phase 9: Backup Keys

On EVERY validator node:

```bash
mkdir -p /root/.integra-backups

# Consensus key (signs blocks)
cp /root/.intgd/config/priv_validator_key.json /root/.integra-backups/

# Node key (P2P identity)
cp /root/.intgd/config/node_key.json /root/.integra-backups/

# Keyring (wallet keys)
cp -r /root/.intgd/keyring-file /root/.integra-backups/
```

Download to your local machine too:
```bash
scp root@<SERVER>:/root/.integra-backups/* ~/integra-backups/<server-name>/
```

---

## Verification Checklist

Run these after everything is up:

```bash
# 1. Blocks producing?
intgd status | jq '.sync_info.latest_block_height'

# 2. All 4 validators bonded?
intgd query staking validators -o json | \
  jq '[.validators[] | select(.status == "BOND_STATUS_BONDED")] | length'
# Expected: 4

# 3. VP roughly equal?
intgd query staking validators -o json | \
  jq '.validators[] | {moniker: .description.moniker, tokens}'

# 4. Inflation correct (1%)?
intgd query mint params -o json | jq '.params.inflation_max'
# Expected: "0.010000000000000000"

# 5. Total supply correct?
intgd query bank total -o json | jq '.supply'
# Expected: ~100,000,000,000 IRL (100B)

# 6. EVM works?
curl -X POST http://127.0.0.1:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"result":"0x6669"} (26217 in hex)

# 7. Test transaction?
intgd tx bank send foundation-treasury <val1-addr> 1000000000000000000airl \
  --gas-prices 5000000000000airl --gas auto --gas-adjustment 1.3 \
  --keyring-backend file --chain-id integra-1 -y
```

---

## Troubleshooting

**Chain not producing blocks:**
- Check all 4 nodes are running: `systemctl status intgd`
- Check peers connected: `curl -s localhost:26657/net_info | jq '.result.n_peers'`
- Check genesis matches: `sha256sum /root/.intgd/config/genesis.json` (must be same on all)

**Node cannot find peers:**
- Verify persistent_peers IPs and node IDs are correct
- Check firewall allows port 26656: `ufw allow 26656`
- Check node ID: `intgd comet show-node-id --home /root/.intgd`

**"wrong Block.Header.AppHash" panic:**
- Genesis mismatch between nodes. Redistribute the FINAL genesis from coordinator.

**Transaction fails with "insufficient fees":**
- Use `--gas-prices 5000000000000airl` (5000 gwei, our base fee)

**EVM chain ID wrong (262144 instead of 26217):**
- Fix app.toml: `sed -i 's/evm_chain_id = "262144"/evm_chain_id = "26217"/' /root/.intgd/config/app.toml`
- Restart: `systemctl restart intgd`
