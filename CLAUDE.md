# Integra Chain

Cosmos EVM Layer 1 blockchain for real-world asset tokenization.

> **⚠️ STATUS (2026-05-14): Mainnet is shut down.** Only **testnet** (`integra-testnet-1`) is
> currently operational. The mainnet sections below are kept as historical/reference material for
> an eventual relaunch — they do **not** describe anything running today. When mainnet is brought
> back, restore the "running" framing and re-verify every value (IPs, binary hash, validator set).

**Repo**: `Integra-layer/integra-chain` (GitHub, branch: `main`)
**Binary**: `intgd` (built from `integra/cmd/intgd`)
**Module**: `github.com/cosmos/evm` (forked from cosmos/evm upstream)

## Chain Info

| | Mainnet *(shut down)* | Testnet *(live)* |
|---|---|---|
| Chain ID | `integra-1` | `integra-testnet-1` |
| EVM Chain ID | `26217` | `26218` |
| Token | IRL (`airl`, 18 decimals) | IRL (`airl`, 18 decimals) |
| CometBFT | v0.38.19 | v0.38.19 |
| Cosmos SDK | v0.53.5 | v0.53.5 |
| Go | 1.23.8 | 1.23.8 |

*The Mainnet column is reference-only — mainnet is not running (see status note at the top).*

## Mainnet Binary *(shut down — historical reference)*

- **Tag**: `v1.0.0` (commit `0e6a388`)
- **MD5**: `9f9c240e0e9f12a04990034410625b84`
- **All 4 validators run this identical binary** (SCP'd, not built independently)
- The binary was built WITHOUT ldflags, so `intgd version` returns empty

## Mainnet validators *(SHUT DOWN as of 2026-05-14 — none of these are running mainnet)*

| Name | IP | Provider | Home Dir |
|------|-----|----------|----------|
| Integra-Gateway | 89.167.88.24 | Hetzner | `~/.intgd` |
| Integra-Signer1 | 45.77.139.208 | Vultr | `~/.intgd-mainnet` |
| Integra-Signer2 | 159.223.206.94 | DigitalOcean | `~/.intgd-mainnet` |
| Integra-Archive | 3.208.92.57 | AWS | `~/.intgd` |

**Mainnet is currently shut down — this table is historical.** When mainnet was live, Signer-1 and Signer-2 ran both testnet and mainnet on the same server, with mainnet at port offset +10000 (P2P 36656, RPC 36657, etc.). Those two hosts now run **only** the testnet `intgd.service` — the `intgd-mainnet.service` unit is stopped/removed and `~/.intgd-mainnet` is no longer in use.

## Testnet validators (3 nodes, all bonded)

| Moniker | Server hostname | IP | Provider | Home Dir | Role |
|---|---|---|---|---|---|
| Integra-Helsinki | testnet-gateway | 46.225.231.81 | Hetzner | `~/.intgd` | **Public RPC origin (Caddy → localhost:8545)** |
| Integra-Amsterdam | signer-1 | 45.77.139.208 | Vultr | `~/.intgd` | Validator (RPC bound to 127.0.0.1, EVM RPC `enable=false`) |
| Integra-SantaClara | signer-2 | 159.223.206.94 | DigitalOcean | `~/.intgd` | Validator (RPC bound to 127.0.0.1, EVM RPC `enable=false`) |

**Notes:**
- Server hostnames (signer-1, signer-2, testnet-gateway) do not match validator monikers.
- testnet.integralayer.com origin is **testnet-gateway (46.225.231.81)**. Caddy on this box reverse-proxies `localhost:8545` (EVM) and `localhost:26657` (Cometbft RPC) to the public hostname.
- Daemon unit on every testnet host is `intgd.service` (bare `ExecStart=/usr/local/bin/intgd start`, no flags — so `app.toml` is canonical). With mainnet shut down, this is now the **only** `intgd` unit on each host. (When mainnet was live, signer-1/signer-2 also ran a separate `intgd-mainnet.service` with `--home /root/.intgd-mainnet --json-rpc.address 0.0.0.0:18545`.)
- Slashing window is 10,000 blocks at 5% min-signed.

**Testnet `app.toml` `[json-rpc]` non-default values (raised 2026-05-05 to unblock 22k-element view-call enumeration in IRWAWrapper):**
- `gas-cap = 300000000` (was 25M)
- `evm-timeout = "15s"` (was 5s)

Backups at `~/.intgd/config/app.toml.bak.<unix-ts>`. Note: signer-1/signer-2 testnet EVM RPC has `enable = false`, so the gas-cap setting on those is dormant — only testnet-gateway actually serves the RPC.

## Testnet block explorer (Ethernal)

**As of 2026-05-14, the testnet explorer runs on its OWN dedicated server**, separate from any validator. This is the result of the migration that decommissioned the co-located explorer on testnet-gateway.

| | |
|---|---|
| Hostname | `Integra-testnet-explorer` |
| IP | `91.99.208.48` |
| Provider | Hetzner CCX23, fsn1-dc8 (Falkenstein) |
| Resources | 4 dedicated EPYC vCPU / 16 GB / 160 GB NVMe / 4 GB swap |
| Public URLs | `https://testnet.explorer.integralayer.com` and `https://admin.testnet.explorer.integralayer.com` (real Let's Encrypt cert) |
| Stack | 9 Docker containers (Ethernal fork + Postgres + TimescaleDB + Redis + Soketi + pm2 indexer) |
| Config dir | `/opt/integra-explorer/` |
| Compose | `docker compose -f /opt/integra-explorer/docker/docker-compose.integra.yml --env-file /opt/integra-explorer/docker/.env.integra ...` |
| DB | Postgres 14 + TimescaleDB; `integra-explorer-postgres` container; database `ethernal`; volumes `docker_pgdata` (21 GB) + `docker_redisdata` |
| Caddy | site blocks for both hostnames in `/etc/caddy/Caddyfile`; **no** `tls internal` (real LE cert); `/api/*` → 8890, `/app/*` → 6002, `/` → 3200; `/evm` reverse-proxies to `https://testnet.integralayer.com` (the public RPC, since this box has no local validator) |
| SSH | `ssh -i ~/.ssh/integra root@91.99.208.48` |

**Important post-migration tunings (also baked in 2026-05-14, do NOT regress):**
- Per-database statement timeout: `ALTER DATABASE ethernal SET statement_timeout = 90000` (raised from 30 s; the `countActiveWallets` SQL is ~30-45 s cold on 2.2 M tx).
- 4 indexes restored after pg_dump-induced hypertable rebuild: `idx_transaction_events_workspace_to`, `transaction_events_workspaceId_from_idx`, `idx_token_transfer_events_workspace_src`, `idx_token_transfer_events_workspace_dst`.
- `token_transfer_events.isReward boolean NOT NULL DEFAULT false` (was missing post-rebuild; caused worker INSERT crash loop on rewards; ~2.1 M existing rows backfilled from `token_transfers.isReward`).
- Self-hosted stub `hasReachedTransactionQuota()` patched into `/opt/integra-explorer/run/models/explorer.js` (backup at `explorer.js.bak.pre-quota-stub`); needs an upstream PR.

**Caddyfile-mutation gotcha (intgd-throttle.service):** the autoscaler on `testnet-gateway` (NOT on the explorer box) now expects **2** `max_conns_per_host` occurrences in `/etc/caddy/Caddyfile` (was 4 before the explorer blocks were removed during the 2026-05-14 decomm). The constant `EXPECTED_OCCURRENCES = 2` lives at line 68 of `/usr/local/bin/intgd-throttle.py` on testnet-gateway. Backup at `*.bak.pre-decomm.*`.

**Rollback window:** the OLD explorer on testnet-gateway is `docker compose stop`'d (NOT `down`'d) with volumes preserved. To roll back, `cd /opt/integra-explorer && docker compose -f docker/docker-compose.integra.yml --env-file docker/.env.integra start` on 46.225.231.81 + restore the Caddyfile backup at `/etc/caddy/Caddyfile.bak.pre-explorer-removal.*` + flip DNS A records back (R53 hosted zone `Z07594511H8QLFFDPQYUJ`, two A records `testnet.explorer.integralayer.com` + `admin.testnet.explorer.integralayer.com`). Rollback window expires **2026-06-15** — after that the OLD volumes can be archived/removed by a deliberate operator.

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
- Go 1.25.7 (the live chain uses 1.23.8)
- CometBFT v0.39.0-beta (the live chain uses v0.38.19)
- Cosmos SDK v0.54.0-rc (the live chain uses v0.53.5)

Merging these would break consensus immediately. Only cherry-pick specific fixes after testing.

### Docker builds MUST use the same Go version as the live chain

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

Working endpoints (testnet only — mainnet is shut down):
- Testnet RPC: `https://testnet.integralayer.com/rpc`
- Testnet EVM: `https://testnet.integralayer.com/evm`

Offline — mainnet shut down (2026-05-14):
- `mainnet.integralayer.com/rpc`
- `mainnet.integralayer.com/evm`
- `mainnet.integralayer.com/api`

Dead endpoints (DO NOT USE):
- `rpc.integralayer.com` — DOWN
- `evm.integralayer.com` — DOWN
- `ormos.integralayer.com` — DOWN
- `grpc.integralayer.com` — DOWN

## SSH Access

```bash
# Testnet (the only live network)
ssh -i ~/.ssh/integra root@46.225.231.81       # testnet-gateway (Integra-Helsinki, public RPC origin)
ssh -i ~/.ssh/integra root@45.77.139.208       # signer-1 (Integra-Amsterdam, testnet validator)
ssh -i ~/.ssh/integra root@159.223.206.94      # signer-2 (Integra-SantaClara, testnet validator)

# Mainnet — SHUT DOWN (hosts listed for reference; nothing mainnet running on them)
ssh -i ~/.ssh/integra root@89.167.88.24        # Gateway (mainnet — down)
ssh -i ~/.ssh/integra-validator-key.pem ubuntu@3.208.92.57  # Archive (mainnet — down; different key + user)
```

## Change Types (from .clconfig.json)

- `feat-smb` — State Machine Breaking (REQUIRES coordinated upgrade)
- `feat-api` — API Breaking (safe for running chain, may break clients)
- `fix` — Bug fix
- `imp` — Improvement
