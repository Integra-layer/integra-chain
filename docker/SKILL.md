# Integra Validator Node Management

Skill for deploying, monitoring, troubleshooting, and managing Integra blockchain validator nodes.

## Chain Reference

| Property | Mainnet | Testnet |
|----------|---------|---------|
| Chain ID | integra-1 | integra-testnet-1 |
| EVM Chain ID | 26217 | 26218 |
| Token | IRL (airl, 18 decimals) | IRL (airl, 18 decimals) |
| Binary | intgd | intgd |
| CometBFT | v0.38.19 | v0.38.19 |
| Cosmos SDK | v0.53.5 | v0.53.5 |
| Go | 1.23.8 | 1.23.8 |
| Binary MD5 | 9f9c240e0e9f12a04990034410625b84 | — |

## Public Endpoints

- RPC: `https://mainnet.integralayer.com/rpc`
- EVM JSON-RPC: `https://mainnet.integralayer.com/evm`
- REST/LCD: `https://mainnet.integralayer.com/api`
- WebSocket: `wss://mainnet.integralayer.com/ws`

## Infrastructure

| Name | IP | Provider | SSH Command | Home Dir |
|------|-----|----------|-------------|----------|
| Gateway | 89.167.88.24 | Hetzner | `ssh -i ~/.ssh/integra root@89.167.88.24` | `~/.intgd` |
| Signer-1 | 45.77.139.208 | Vultr | `ssh -i ~/.ssh/integra root@45.77.139.208` | `~/.intgd-mainnet` |
| Signer-2 | 159.223.206.94 | DigitalOcean | `ssh -i ~/.ssh/integra root@159.223.206.94` | `~/.intgd-mainnet` |
| Archive | 3.208.92.57 | AWS | `ssh -i ~/.ssh/integra-validator-key.pem ubuntu@3.208.92.57` | `~/.intgd` |

Note: Signer-1 and Signer-2 use `--home ~/.intgd-mainnet` for all intgd commands and `intgd-mainnet` as the systemd unit name.

---

## 1. Deploy a New Validator Node (Docker)

### Quick Start

```bash
git clone https://github.com/Integra-layer/integra-chain.git
cd integra-chain
MONIKER="my-validator" docker compose -f docker/docker-compose.validator.yml up --build -d
```

### Post-Deploy Verification

```bash
# Wait ~30s for node to initialize, then check sync status
docker logs -f integra-validator

# Confirm the node is syncing
docker exec integra-validator intgd status | jq '.sync_info'
# Expected: catching_up = true (will become false once synced)

# Check peer count (should be >= 3)
docker exec integra-validator curl -s localhost:26657/net_info | jq '.result.n_peers'
```

### Critical Config Checks

Before the node finishes syncing, verify these settings in the container:

```bash
# EVM chain ID must be 26217 (NOT the default 262144)
docker exec integra-validator grep 'chain-id' /root/.intgd/config/app.toml
# Expected: chain-id = "26217"

# Minimum gas price must be correct
docker exec integra-validator grep 'minimum-gas-prices' /root/.intgd/config/app.toml
# Expected: minimum-gas-prices = "5000000000000airl"
```

If either value is wrong, fix it and restart:

```bash
docker exec integra-validator sed -i 's/chain-id = "262144"/chain-id = "26217"/' /root/.intgd/config/app.toml
docker exec integra-validator sed -i 's/minimum-gas-prices = ".*"/minimum-gas-prices = "5000000000000airl"/' /root/.intgd/config/app.toml
docker restart integra-validator
```

### State Sync vs Block Sync

State sync is faster but unreliable on this chain. If state sync fails with "height requested is too high", switch to block sync:

```bash
# In docker-compose or entrypoint, set:
STATE_SYNC=false
# Then recreate the container
docker compose -f docker/docker-compose.validator.yml up --build -d
```

---

## 2. Check Node Status Across All Servers

### Quick Health Check (Run Locally)

```bash
# Gateway
ssh -i ~/.ssh/integra root@89.167.88.24 'intgd status 2>&1 | jq "{node: \"Gateway\", height: .sync_info.latest_block_height, catching_up: .sync_info.catching_up, peers: (.node_info.other.tx_index // \"n/a\")}"'

# Signer-1
ssh -i ~/.ssh/integra root@45.77.139.208 'intgd status --home ~/.intgd-mainnet 2>&1 | jq "{node: \"Signer-1\", height: .sync_info.latest_block_height, catching_up: .sync_info.catching_up}"'

# Signer-2
ssh -i ~/.ssh/integra root@159.223.206.94 'intgd status --home ~/.intgd-mainnet 2>&1 | jq "{node: \"Signer-2\", height: .sync_info.latest_block_height, catching_up: .sync_info.catching_up}"'

# Archive
ssh -i ~/.ssh/integra-validator-key.pem ubuntu@3.208.92.57 'intgd status 2>&1 | jq "{node: \"Archive\", height: .sync_info.latest_block_height, catching_up: .sync_info.catching_up}"'
```

### Full Health Check Script

Run this to verify all health criteria at once:

```bash
# For each server, check:
# 1. Node is running and responding
# 2. catching_up is false
# 3. Height is within 2-3 blocks of other nodes
# 4. Peer count >= 3

for SERVER in "root@89.167.88.24:~/.intgd:~/.ssh/integra" \
              "root@45.77.139.208:~/.intgd-mainnet:~/.ssh/integra" \
              "root@159.223.206.94:~/.intgd-mainnet:~/.ssh/integra" \
              "ubuntu@3.208.92.57:~/.intgd:~/.ssh/integra-validator-key.pem"; do
  IFS=':' read -r USER_HOST HOME_DIR KEY <<< "$SERVER"
  echo "=== $USER_HOST ==="
  ssh -i "$KEY" "$USER_HOST" "intgd status --home $HOME_DIR 2>&1 | jq '.sync_info | {height: .latest_block_height, catching_up: .catching_up, latest_block_time: .latest_block_time}'" 2>/dev/null || echo "UNREACHABLE"
  ssh -i "$KEY" "$USER_HOST" "curl -s localhost:26657/net_info 2>/dev/null | jq '.result.n_peers'" 2>/dev/null || echo "RPC DOWN"
  echo ""
done
```

### Validator Set Check

```bash
# From any node or locally via RPC
curl -s https://mainnet.integralayer.com/rpc/validators | jq '.result.validators[] | {address: .address, voting_power: .voting_power}'

# Check all validators are BONDED
intgd query staking validators --node https://mainnet.integralayer.com/rpc --output json | jq '.validators[] | {moniker: .description.moniker, status: .status, tokens: .tokens}'
# All 4 should show status: "BOND_STATUS_BONDED"
```

---

## 3. Troubleshoot Common Validator Issues

### State Sync Failure

**Symptom:** Node stuck, logs show "height requested is too high" or snapshot errors.

**Cause:** A forked node is advertising bad snapshots.

**Fix:**
```bash
# Switch to block sync
# For systemd nodes:
# Edit config.toml: enable = false under [statesync]
# For Docker nodes:
STATE_SYNC=false docker compose -f docker/docker-compose.validator.yml up --build -d
```

### Peer Handshake Fails Silently

**Symptom:** Node has 0 peers, no error in logs, just no connections.

**Cause:** Missing or wrong `--chain-id` flag.

**Fix:** Ensure `chain-id = "integra-1"` in config.toml and that the genesis file matches.

### Wrong EVM Chain ID

**Symptom:** EVM transactions fail, MetaMask rejects the chain, or EVM RPC returns wrong chain ID.

**Cause:** Default EVM chain ID is 262144, must be 26217.

**Fix:**
```bash
# In app.toml, find [evm] section
sed -i 's/chain-id = "262144"/chain-id = "26217"/' ~/.intgd/config/app.toml
systemctl restart intgd
```

### Wrong Gas Price

**Symptom:** Transactions rejected with "insufficient fees".

**Cause:** minimum-gas-prices not set or wrong.

**Fix:**
```bash
# In app.toml
sed -i 's/minimum-gas-prices = ".*"/minimum-gas-prices = "5000000000000airl"/' ~/.intgd/config/app.toml
systemctl restart intgd
```

### Node Falling Behind / Missed Blocks

**Symptom:** Height is significantly behind other nodes, or validator is missing blocks.

**Cause:** Resource exhaustion, network issues, or process crash.

**Check:**
```bash
# Compare heights across nodes (use the health check above)
# Check if catching_up is true
intgd status --home DIR | jq '.sync_info.catching_up'

# Check system resources
ssh -i KEY USER@HOST 'free -h && df -h && top -bn1 | head -5'

# Check for OOM kills
ssh -i KEY USER@HOST 'dmesg | grep -i "out of memory" | tail -5'
```

**Slashing risk:** 0.01% slash after missing 9500 out of 10000 blocks. Monitor missed blocks actively.

### Binary Mismatch

**Symptom:** Consensus failure, app hash mismatch, node halts at a specific height.

**Cause:** Binary on one node differs from others.

**Fix:**
```bash
# Check binary hash on every node (must all match)
md5sum $(which intgd)
# Expected: 9f9c240e0e9f12a04990034410625b84

# If wrong, rebuild or copy the correct binary
# Go version must be exactly 1.23.8
go version
```

---

## 4. Validator Lifecycle Management

### Restart a Node

```bash
# Systemd (Gateway, Archive)
ssh -i ~/.ssh/integra root@89.167.88.24 'systemctl restart intgd'

# Systemd (Signer-1, Signer-2 — different unit name)
ssh -i ~/.ssh/integra root@45.77.139.208 'systemctl restart intgd-mainnet'
ssh -i ~/.ssh/integra root@159.223.206.94 'systemctl restart intgd-mainnet'

# Docker validator
docker restart integra-validator
```

### View Logs

```bash
# Systemd
ssh -i ~/.ssh/integra root@89.167.88.24 'journalctl -u intgd -f --no-hostname -n 100'
ssh -i ~/.ssh/integra root@45.77.139.208 'journalctl -u intgd-mainnet -f --no-hostname -n 100'

# Docker
docker logs -f --tail 100 integra-validator
```

### Upgrade a Node

**CRITICAL: Never deploy a consensus-breaking change without coordinated upgrade across all validators.**

Safe upgrade procedure (non-consensus-breaking, e.g. bug fix):

```bash
# 1. Build the new binary (Go 1.23.8 required)
cd integra-chain
git pull origin main
go build -o intgd ./cmd/intgd

# 2. Verify the binary hash matches what other operators will run
md5sum intgd

# 3. Stop the node
systemctl stop intgd  # or intgd-mainnet on shared servers

# 4. Replace the binary
cp intgd $(which intgd)

# 5. Start the node
systemctl start intgd

# 6. Verify it's syncing
intgd status --home DIR | jq '.sync_info'
```

Consensus-breaking upgrade (chain halt required):

```bash
# 1. Coordinate halt height with all validators
# 2. Wait for all nodes to reach halt height
# 3. Stop all nodes
# 4. Replace binary on all nodes
# 5. Start all nodes
# DO NOT start nodes one by one — start all within a short window
```

### Monitor Continuously

Key metrics to watch:

| Metric | Command | Healthy Value |
|--------|---------|---------------|
| Block height | `intgd status \| jq '.sync_info.latest_block_height'` | Increasing, within 2-3 of peers |
| Catching up | `intgd status \| jq '.sync_info.catching_up'` | `false` |
| Peer count | `curl -s localhost:26657/net_info \| jq '.result.n_peers'` | >= 3 |
| Validator status | `intgd query staking validators --output json \| jq ...` | All 4 BONDED |
| Missed blocks | Check signing info for your validator | < 9500 / 10000 window |
| Disk usage | `df -h` | < 80% |
| Memory | `free -h` | No swap pressure |

---

## Safety Rules

1. **NEVER** merge consensus-breaking changes without a coordinated upgrade plan across all validators
2. **Binary must be identical** on all nodes (MD5: `9f9c240e0e9f12a04990034410625b84`)
3. **Go version must be 1.23.8** — other versions may produce different binaries
4. **Do not touch upstream cosmos/evm modules** — they are on newer incompatible versions
5. **EVM chain ID must be 26217** (not the default 262144)
6. **Minimum gas price must be 5000000000000airl**
7. **All 4 validators must be BONDED** — if one drops, investigate immediately
