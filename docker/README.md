# Integra Validator Node - Docker Setup

Run an Integra validator node with Docker. Works on any Linux VPS with 4+ CPU cores, 16GB+ RAM, and 500GB+ SSD.

## Prerequisites

- Docker 20.10+ with Compose V2
- Open port **26656** (P2P) in your firewall
- A funded Integra wallet (contact the Foundation for IRL tokens)

## Quick Start (Non-Interactive)

```bash
git clone https://github.com/Integra-layer/integra-chain.git
cd integra-chain

# Build and start (replace "my-validator" with your name)
MONIKER="my-validator" docker compose -f docker/docker-compose.validator.yml up --build -d

# Watch logs
docker logs -f integra-validator

# Check sync status (wait until catching_up = false)
docker exec integra-validator intgd status | jq '.sync_info.catching_up'
```

That's it. The container will:
1. Initialize the node with your moniker
2. Download the genesis file from the network
3. Configure peers, gas prices, EVM chain ID automatically
4. Start syncing blocks (block sync, takes a few hours on first run)

## Interactive Setup (Wizard)

If you prefer a guided setup with wallet creation:

```bash
git clone https://github.com/Integra-layer/integra-chain.git
cd integra-chain

docker compose -f docker/docker-compose.validator.yml build
docker compose -f docker/docker-compose.validator.yml run --rm validator setup
```

The wizard will walk you through:
- Network selection (Mainnet / Testnet)
- Validator metadata (name, description, commission)
- Wallet setup (new, import mnemonic, or import EVM key)
- Genesis and peer configuration

Then start the node:

```bash
docker compose -f docker/docker-compose.validator.yml up -d
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MONIKER` | _(triggers wizard if empty)_ | Your validator name |
| `NETWORK` | `mainnet` | `mainnet` or `testnet` |
| `STATE_SYNC` | `false` | Enable state sync (currently unavailable on mainnet) |
| `PEERS` | _(auto-configured)_ | Override persistent peers |

## Create Your Validator

Once your node is fully synced (`catching_up: false`):

### 1. Create or import a wallet

```bash
# Generate new wallet
docker exec -it integra-validator intgd keys add validator --keyring-backend file

# OR import existing mnemonic
docker exec -it integra-validator intgd keys add validator --recover --keyring-backend file

# OR import EVM private key
docker exec -it integra-validator intgd keys unsafe-import-eth-key validator YOUR_HEX_KEY --keyring-backend file
```

Save your mnemonic securely. You cannot recover it later.

### 2. Fund your wallet

Get your address and request IRL tokens from the Integra Foundation:

```bash
docker exec integra-validator intgd keys show validator -a --keyring-backend file
```

### 3. Create the validator

```bash
# Get your consensus public key
docker exec integra-validator intgd comet show-validator

# Create validator (replace values)
docker exec -it integra-validator intgd tx staking create-validator \
  --amount 100000000000000000000airl \
  --pubkey '{"@type":"/cosmos.crypto.ed25519.PubKey","key":"YOUR_KEY_HERE"}' \
  --moniker "my-validator" \
  --commission-rate 0.05 \
  --commission-max-rate 0.20 \
  --commission-max-change-rate 0.01 \
  --min-self-delegation 1000000000000000000000 \
  --gas-prices 5000000000000airl \
  --gas auto \
  --gas-adjustment 1.3 \
  --from validator \
  --keyring-backend file \
  --chain-id integra-1 \
  -y
```

The `--amount` is in `airl` (18 decimals). 100 IRL = `100000000000000000000airl`.

### 4. Verify

```bash
# Check your validator status
docker exec integra-validator intgd query staking validator \
  $(docker exec integra-validator intgd keys show validator --bech val -a --keyring-backend file)
```

## Network Info

| | Mainnet | Testnet |
|---|---|---|
| Chain ID | `integra-1` | `integra-testnet-1` |
| EVM Chain ID | `26217` | `26218` |
| Token | IRL (`airl`, 18 decimals) | IRL (`airl`, 18 decimals) |
| RPC | https://mainnet.integralayer.com/rpc | https://testnet.integralayer.com/rpc |
| EVM | https://mainnet.integralayer.com/evm | https://testnet.integralayer.com/evm |
| REST | https://mainnet.integralayer.com/api | https://testnet.integralayer.com/api |
| Explorer | https://explorer.integralayer.com | https://testnet.explorer.integralayer.com |
| Min Gas Price | 5000000000000airl (~5000 gwei) | 5000000000000airl |

## Ports

| Port | Service | Must be open? |
|------|---------|---------------|
| 26656 | P2P (CometBFT) | Yes |
| 26657 | RPC | Optional (local queries) |
| 8545 | EVM JSON-RPC | Optional |
| 8546 | EVM WebSocket | Optional |
| 1317 | Cosmos REST | Optional |
| 9090 | gRPC | Optional |

Only port **26656** needs to be publicly accessible. The others are for your own use.

## Common Operations

```bash
# View logs
docker logs -f integra-validator

# Check sync status
docker exec integra-validator intgd status | jq '.sync_info'

# Check your validator
docker exec integra-validator intgd query staking validators --output json | jq '.validators[] | {moniker, status, tokens}'

# Restart
docker restart integra-validator

# Stop
docker stop integra-validator

# Upgrade (pull latest, rebuild)
cd integra-chain && git pull
docker compose -f docker/docker-compose.validator.yml up --build -d
```

## Troubleshooting

**Node won't connect to peers**
- Ensure port 26656 is open: `sudo ufw allow 26656/tcp`
- Check peers: `docker exec integra-validator intgd status | jq '.node_info.listen_addr'`

**"wrong Block.Header.AppHash" or consensus failure**
- Your binary version doesn't match the network. Rebuild from the latest commit:
  ```bash
  git pull && docker compose -f docker/docker-compose.validator.yml up --build -d
  ```

**State sync fails**
- Disable state sync and use block sync instead:
  ```bash
  STATE_SYNC=false MONIKER="my-validator" docker compose -f docker/docker-compose.validator.yml up --build -d
  ```
- Or clear data and retry: `docker volume rm integra-chain_integra-data`

**"account sequence mismatch"**
- Wait a few seconds and retry. This happens when transactions are sent too quickly.

**Container keeps restarting**
- Check logs: `docker logs integra-validator --tail 50`
- Common cause: genesis mismatch. Remove volume and restart:
  ```bash
  docker compose -f docker/docker-compose.validator.yml down -v
  MONIKER="my-validator" docker compose -f docker/docker-compose.validator.yml up --build -d
  ```

## Hardware Recommendations

| | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 8+ cores |
| RAM | 16 GB | 32 GB |
| Disk | 500 GB SSD | 1 TB NVMe |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 LTS |
| Network | 100 Mbps | 1 Gbps |

## Security

- Never expose your keyring password or mnemonic
- Use `--keyring-backend file` (not `test`) for production validators
- Consider running behind a sentry node architecture for DDoS protection
- Monitor for missed blocks to avoid slashing (0.01% penalty after missing 9,500 of 10,000 blocks)
- Double-signing results in 5% slashing and permanent removal
