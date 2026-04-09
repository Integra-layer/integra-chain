# Integra Chain

Cosmos EVM Layer 1 blockchain for real-world asset tokenization.

**Repo**: `Integra-layer/integra-chain` (GitHub, branch: `main`)
**Binary**: `intgd` (built from `integra/cmd/intgd`)
**Module**: `github.com/cosmos/evm` (forked from cosmos/evm upstream)

## Chain Info

| | Mainnet | Testnet |
|---|---|---|
| Chain ID | `integra-1` | `integra-testnet-1` |
| EVM Chain ID | `26217` | `26218` |
| Token | IRL (`airl`, 18 decimals) | IRL (`airl`, 18 decimals) |
| CometBFT | v0.38.19 | v0.38.19 |
| Cosmos SDK | v0.53.5 | v0.53.5 |
| Go | 1.23.8 | 1.23.8 |

## Mainnet Binary

- **Tag**: `v1.0.0` (commit `0e6a388`)
- **MD5**: `9f9c240e0e9f12a04990034410625b84`
- **All 4 validators run this identical binary** (SCP'd, not built independently)
- The binary was built WITHOUT ldflags, so `intgd version` returns empty

## Validators (4 nodes, all bonded)

| Name | IP | Provider | Home Dir |
|------|-----|----------|----------|
| Integra-Gateway | 89.167.88.24 | Hetzner | `~/.intgd` |
| Integra-Signer1 | 45.77.139.208 | Vultr | `~/.intgd-mainnet` |
| Integra-Signer2 | 159.223.206.94 | DigitalOcean | `~/.intgd-mainnet` |
| Integra-Archive | 3.208.92.57 | AWS | `~/.intgd` |

Signer-1 and Signer-2 run both testnet and mainnet on the same server. Mainnet uses port offset +10000 (P2P 36656, RPC 36657, etc.).

## CRITICAL SAFETY RULES

### Never merge consensus-breaking changes without a coordinated upgrade

A "State Machine Breaking" change is anything that alters how blocks are validated or state is computed:
- Transaction processing logic, gas calculations, EVM opcode behavior
- Module state transitions (staking, bank, evm, feemarket, erc20)
- Protobuf message changes that affect state
- Precompile behavior changes

If such a change is merged to `main` and a new validator builds from HEAD, their node will produce different state hashes and either:
- Fall out of consensus (can't validate blocks)
- Get slashed for double-signing (5% penalty, permanent removal)

**Process for consensus-breaking changes:**
1. Create a new tagged release (e.g., `v1.1.0`)
2. Submit a software upgrade governance proposal specifying the upgrade height
3. ALL validators must upgrade their binary before that height
4. Use the Cosmos SDK upgrade module (`x/upgrade`)

### Never merge upstream cosmos/evm changes blindly

The upstream `integra-evm-src` repo (`Aboudjem/evm`) tracks newer versions:
- Go 1.25.7 (mainnet uses 1.23.8)
- CometBFT v0.39.0-beta (mainnet uses v0.38.19)
- Cosmos SDK v0.54.0-rc (mainnet uses v0.53.5)

Merging these would break consensus immediately. Only cherry-pick specific fixes after testing.

### Docker builds MUST use the same Go version as mainnet

The Dockerfile pins `golang:1.23.8-alpine`. Do not change this without upgrading all validators.

### What CAN be changed safely (no binary upgrade needed)

These are on-chain parameters changeable via governance proposal:
- `minimum-gas-prices` (per-validator config, not even governance)
- Base fee / fee market params (`x/feemarket`)
- Staking params (unbonding period, max validators)
- Governance params (voting period, deposit, quorum)
- Slashing params (downtime window, jail duration)
- ERC-20 registration settings

Query current params: `intgd query params subspace <module> <key>`

### What requires a binary upgrade

- EVM opcode gas costs (hardcoded in go-ethereum fork)
- New precompile contracts
- New Cosmos SDK modules
- Protobuf schema changes
- Bug fixes in state machine logic

## Build

```bash
# Local build
cd integra && go mod download && go build -o ../build/intgd ./cmd/intgd

# Docker build (for validators)
docker compose -f docker/docker-compose.validator.yml up --build -d

# Run tests
make test
```

## Key Directories

- `integra/` — main app, cmd/intgd binary entry point
- `x/` — Cosmos SDK custom modules
- `precompiles/` — EVM precompiled contracts (staking, distribution, governance)
- `docker/` — validator Docker setup (Dockerfile, wizard, lib.sh, tests)
- `config/` — chain constants (chain ID, EVM chain ID, denom)
- `contracts/` — Solidity contracts (ERC-20, hardhat config)
- `rpc/` — Custom RPC endpoints

## Endpoints

Working endpoints:
- Mainnet RPC: `https://mainnet.integralayer.com/rpc`
- Mainnet EVM: `https://mainnet.integralayer.com/evm`
- Mainnet REST: `https://mainnet.integralayer.com/api`
- Testnet RPC: `https://testnet.integralayer.com/rpc`

Dead endpoints (DO NOT USE):
- `rpc.integralayer.com` — DOWN
- `evm.integralayer.com` — DOWN
- `ormos.integralayer.com` — DOWN
- `grpc.integralayer.com` — DOWN

## SSH Access

```bash
ssh -i ~/.ssh/integra root@89.167.88.24        # Gateway
ssh -i ~/.ssh/integra root@45.77.139.208       # Signer-1
ssh -i ~/.ssh/integra root@159.223.206.94      # Signer-2
ssh -i ~/.ssh/integra-validator-key.pem ubuntu@3.208.92.57  # Archive (different key + user)
```

## Change Types (from .clconfig.json)

- `feat-smb` — State Machine Breaking (REQUIRES coordinated upgrade)
- `feat-api` — API Breaking (safe for running chain, may break clients)
- `fix` — Bug fix
- `imp` — Improvement
