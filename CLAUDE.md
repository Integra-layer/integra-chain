# Integra Chain

Cosmos EVM Layer 1 blockchain for real-world asset tokenization.

> **Network status (verified 2026-05-29): only `integra-testnet-1` is operational.**
> Mainnet is shut down and nothing mainnet runs on any host (`intgd-mainnet.service` and
> `~/.intgd-mainnet` no longer exist anywhere). This file documents the **live testnet only**.
> If mainnet is ever relaunched it is a separate, coordinated effort — re-derive every value then.

**Repo**: `Integra-layer/integra-chain` (GitHub, branch: `main`)
**Binary**: `intgd` (built from `integra/cmd/intgd`)
**Module**: `github.com/cosmos/evm` (forked from cosmos/evm upstream)

## Chain Info

| | Testnet |
|---|---|
| Chain ID | `integra-testnet-1` |
| EVM Chain ID | `26218` (hex `0x666a`) |
| Token | IRL (`airl`, 18 decimals) |
| CometBFT | v0.38.19 |
| Cosmos SDK | v0.53.5 |
| Go | 1.23.8 |

The binary is built WITHOUT ldflags, so `intgd version` returns empty (`intgd version --long` shows
the SDK/Go build info). Binary at `/usr/local/bin/intgd`; no cosmovisor.

## Validators (4 bonded + 1 jailed)

From `intgd query staking validators` + `curl localhost:26657/validators` (verified 2026-05-29).
Total active voting power ≈ **651M**; the ⅔ quorum threshold ≈ **434M**.

| Moniker | Host / role | IP | Provider | ~VP | EVM RPC exposure |
|---|---|---|---|---|---|
| **Integra-Helsinki** | testnet-gateway — **public RPC origin** + validator | 46.225.231.81 | Hetzner | ~200.3M | Caddy:443 → `localhost:8545` |
| **Integra-Amsterdam** | signer-1 — validator | 45.77.139.208 | Vultr | ~200.3M | own Caddy `:8645` → `127.0.0.1:8545` (ufw-locked to explorer) |
| **Integra-SantaClara** | signer-2 — validator | 159.223.206.94 | DigitalOcean | ~200.5M | own Caddy `:8645` → `127.0.0.1:8545` (ufw-locked to explorer) |
| `integra-validator` | external validator (not Integra-operated) | ~`212.1.103.62` *(UNVERIFIED)* | — | ~50M | n/a |
| `integralayer-local` | **jailed + unbonding** — NOT in the active set | — | — | ~0.06M | — |

**Notes**
- Server hostnames (testnet-gateway, signer-1, signer-2) do **not** match the validator monikers
  (Helsinki / Amsterdam / SantaClara).
- **All three Integra nodes are validators (including the gateway).** The 4th bonded validator
  (`integra-validator`, ~50M, external) is a deliberate **quorum cushion**: with 4 bonded
  validators, taking any single ~200M Integra node offline still leaves ≈69% of voting power
  online (> ⅔), so a node can be restarted without halting the chain.
- Daemon unit on every host is `intgd.service` (bare `ExecStart=/usr/local/bin/intgd start`, no
  flags → `app.toml` is canonical). intgd PIDs (2026-05-29): gateway `2647652`, signer-1 `14783`,
  signer-2 `7187`. (These change on restart; don't hard-code them anywhere.)
- Slashing window: **10,000 blocks at 5% min-signed**. A brief restart (missing ~tens of blocks)
  is far within tolerance.

**Validator restart protocol** (any `app.toml`/config change that needs an `intgd` restart):
1. Confirm all 4 validators are bonded + signing and the chain is producing blocks.
2. Restart **one** node; wait for full recovery (`catching_up=false`, resumes signing) and confirm
   the chain never stopped advancing.
3. Only then move to the next. **NEVER restart two ~200M validators at once** — two big validators
   down simultaneously drops below ⅔ and halts the chain.

## RPC topology

- **Public RPC origin = testnet-gateway** (46.225.231.81). Caddy:443 reverse-proxies
  `/evm`,`/evm/*` → `localhost:8545`; `/rpc`,`/rpc/*` → `localhost:26657`; `/api*` →
  `localhost:1317`; `/ws` → `localhost:8546`.
- **Both signers also serve EVM RPC**: each runs its **own Caddy on `:8645`** → local
  `intgd 127.0.0.1:8545` (json-rpc `enable=true` on the signers). `ufw` allows `:8645` from the
  explorer (and a signer-1 status probe) only — **never public**.
- **Internal RPC load balancer**: `rpc-internal.testnet.integralayer.com` — a Caddy vhost on the
  explorer box, `@internal_only` (loopback + explorer + docker subnets, else `403`), `least_conn`
  across **both signers:8645** with active health checks (`POST eth_blockNumber`, 15s). `ip_hash`
  was removed after the 2026-05-26 outage (it pinned clients to a wedged signer).
- **The explorer indexer and the explorer-UI `/evm` use the internal LB** (`rpc-internal`), NOT the
  gateway, as of 2026-05-29 (see incident note below).

**`app.toml` `[json-rpc]` per node:**

| | Gateway | Signers (1 & 2) |
|---|---|---|
| `enable` | `true` | `true` |
| `api` | `eth,net,web3` | `eth,net,web3` *(debug,txpool DROPPED 2026-05-29)* |
| `gas-cap` | `300000000` | `50000000` |
| `evm-timeout` | `15s` | `8s` |
| `max-open-connections` | `600` *(was 0; bounded 2026-05-29)* | `200` *(was 0; bounded 2026-05-29)* |
| `batch-request-limit` | `10` *(was 1000)* | `100` |
| `batch-response-max-size` | `5000000` *(~5MB, was 25MB)* | `25000000` |
| `block-range-cap` | `5000` *(was 10000)* | `2000` |
| `[state-sync] snapshot-interval` | `0` *(was 1000; 2026-05-29)* | `0` |
| bind (`address`) | `0.0.0.0:8545` (ufw-locked) | `127.0.0.1:8545` (behind Caddy `:8645`) |
| `ws-address` | `127.0.0.1:8546` *(loopback, 2026-05-29)* | `127.0.0.1:8546` |
| `[instrumentation] prometheus` | `true` @ `127.0.0.1:26660` | `true` @ `127.0.0.1:26660` |

The gateway's `gas-cap=300000000` / `evm-timeout=15s` were raised (2026-05-05) to unblock a
~22k-element view-call enumeration in `IRWAWrapper`. **Treat these as load-bearing — do not lower
them** (it silently breaks that legitimate call, and any upstream proxy timeout must sit *above*
the 15s ceiling). Backups: `~/.intgd/config/app.toml.bak.<unix-ts>`.

## 2026-05-29 — EVM RPC flapping incident & fix

- **Symptom:** `https://testnet.integralayer.com/evm` flapping DOWN with "Unexpected end of JSON
  input" (a Caddy `504` returns an empty body, which the status monitor fails to JSON-parse).
- **Root cause:** the Ethernal explorer was the dominant load on the **single** gateway intgd. Its
  indexer (`workspaces.rpcServer`) pointed **directly at `http://46.225.231.81:8545`** — bypassing
  every Caddy control — and its UI `/evm` proxied to the gateway too. Heavy queries saturated the
  one node → `504` storms (~99.8% of recent 504s originated from the explorer IP). Amplified by the
  gateway Caddy `response_header_timeout` having drifted to 25s.
- **Fix (config/infra only — no consensus impact, no intgd restart):**
  1. Repointed the explorer **indexer** (`workspaces.rpcServer`) and the explorer-UI `/evm` to
     `https://rpc-internal.testnet.integralayer.com/evm` (the signer LB) — load now spreads across
     both signers, off the single gateway.
  2. Gateway Caddy `/evm` `response_header_timeout` 25s → **18s** (above intgd's 15s evm-timeout;
     stuck slots recycle faster) — `read`/`write_timeout` left at 25s.
  3. `intgd-throttle.service` **disabled** (its tighten-on-saturation logic backfires — keep off).
- Full write-up + rollback: `docs/findings/2026-05-29-rpc-flapping-explorer-overload/`.

## 2026-05-29 — permanent-fix run (config/architecture remediation, NOT bigger servers)

Root cause of the recurring instability was **config/architecture/software, not capacity** (validators
idle ≤25% CPU). All fixes below are verified; chain stayed healthy (all 4 signing, never halted).

**Explorer (the load-48 fire):** created the missing index `idx_token_transfers_txid` on
`token_transfers("transactionId")` (the 9.5M-row seq-scan per tx-detail query) → load **48→~2**;
`shared_buffers` 256MB→4GB, `max_connections` 800→150, `work_mem`→16MB, `jit=off`; added **pgbouncer**
(transaction pooling, `:6432`) and repointed all app DB conns through it. Home page 2.3s→~1s.
**Never** use `docker compose ... --remove-orphans` here (kills integra-portal).

**Validators (per-node, applied via the restart safety protocol, one node at a time):** dropped
`debug,txpool` from the signer `api`; bounded `max-open-connections` (gw 600 / signers 200); gateway
`batch-request-limit`→10, `batch-response-max-size`→5MB, `block-range-cap`→5000, `snapshot-interval`→0,
WS bound to loopback; CometBFT prometheus on (loopback `:26660`); signer Caddy `:8645` transport
hardened (`max_conns_per_host 150`, `response_header_timeout 12s`). Gateway `MemoryHigh` 12G→infinity
(was causing 2M+ cgroup throttle events). Closed the latent gateway Caddy `/evm`→`:8545` door.

**Hygiene/security:** ufw cleaned (gw del 5433/1317, deny 8546; signers del dead 26657/36656/36657);
unattended-upgrades auto-reboot disabled on all validators (the 2026-05-28 near-halt cause); fixed the
failed `logrotate` on all 4 hosts; removed dead `intgd-mainnet.service` units on the signers; secret
files (`.env.integra` + backups) chmod 600.

**Config drift control (root cause B):** the 3 validators' `app.toml`/`config.toml` are now checked into
`infra/validators/` with `check-drift.sh` + a CI workflow (`.github/workflows/validator-config-drift.yml`).

**Per-server docs:** `/root/SERVER.md` is maintained on all 4 boxes (created on the explorer).

**DEFERRED / needs-credentials (NOT done — see the findings folder):**
- Gateway **IAVL pruning spam — FIXED 2026-05-29** by setting gateway `[base] pruning="nothing"` (archive
  mode) + restart → `version does not exist` spam now 0/min. (snapshot-interval=0 and an offline `intgd
  prune` were both tried first and verified ineffective — the cause was the runtime pruning routine, not a
  prune backlog.) Gateway now keeps full history. The `application.db`≈54G is **un-compacted goleveldb**
  (NOT reclaimed by this; it grows gradually now) — an OPTIONAL **clean-store resync** (copy a compacted
  signer's `~/.intgd/data`, keep this node's keys) reclaims it later. Disk fine (134G free, disk-guard
  monitors). Reversible: `pruning="default"` + restart.
- **Cloudflare edge (3L)** — **SKIPPED 2026-05-29** (decided after live testing): CF free **cannot** do
  testnet-only (subdomain zones are Enterprise-only — `error 1116`; CNAME setup is Business $200/mo), and
  the only free path is a **full apex-zone migration** of all 86 `integralayer.com` records (email + ~30
  prod/dev apps) — declined (blast radius). The testnet is already hardened without CF. Do **not** move the
  public origin onto the validator gateway (consensus risk). Full-migration runbook (if ever wanted) +
  details in `docs/findings/.../ARCHITECTURE-EDGE-DECISION.md`.
- **Telegram bot token** rotation via @BotFather (precautionary; files are now 0600).
- Stale migration dumps (gw ~7.8G, explorer ~13G) + gateway idle docker/pm2 → clean after the
  2026-06-15 rollback window.

Full write-ups: `docs/findings/2026-05-29-rpc-flapping-explorer-overload/`
(`INCIDENT.md`, `EXPLORER-OVERLOAD-PLAN.md`, `ARCHITECTURE-EDGE-DECISION.md`,
`IAVL-PRUNING-AND-PROCESS-AUDIT.md`).

## Testnet block explorer (Ethernal)

Runs on its own dedicated server (migrated off testnet-gateway 2026-05-14).

| | |
|---|---|
| Hostname / IP | `Integra-testnet-explorer` / `91.99.208.48` |
| Provider | Hetzner CCX23, fsn1-dc8 (Falkenstein) — 4 EPYC vCPU / 16 GB / 160 GB NVMe |
| Public URLs | `https://testnet.explorer.integralayer.com` + `https://admin.testnet.explorer.integralayer.com` (real Let's Encrypt cert) |
| Stack | **12 Docker containers**: Ethernal frontend/backend, pm2 indexer, worker-{low,medium,high}, Postgres+TimescaleDB, Redis, Soketi, watchdog, plus co-located `integra-portal` and `integra-faucet` |
| Config dir | `/opt/integra-explorer/` |
| DB | Postgres 14 + TimescaleDB; container `integra-explorer-postgres`; database `ethernal` |
| Internal RPC LB | hosts the `rpc-internal.testnet.integralayer.com` Caddy vhost → both signers:8645 (least_conn + health checks) |
| SSH | `ssh -i ~/.ssh/integra root@91.99.208.48` |

**Tunings to NOT regress** (baked 2026-05-14):
- `ALTER DATABASE ethernal SET statement_timeout = 90000` (the `countActiveWallets` SQL is ~30-45s
  cold on 2.2M tx).
- 4 indexes restored after a pg_dump-induced hypertable rebuild: `idx_transaction_events_workspace_to`,
  `transaction_events_workspaceId_from_idx`, `idx_token_transfer_events_workspace_src`,
  `idx_token_transfer_events_workspace_dst`.
- `token_transfer_events.isReward boolean NOT NULL DEFAULT false` (missing post-rebuild → worker
  INSERT crash loop; ~2.1M rows backfilled).
- Self-hosted stub `hasReachedTransactionQuota()` in `/opt/integra-explorer/run/models/explorer.js`
  (backup `explorer.js.bak.pre-quota-stub`; needs an upstream PR).

**Migration rollback window (expires 2026-06-15):** the OLD co-located explorer on testnet-gateway
is `docker compose stop`'d (NOT `down`'d), volumes preserved. To roll back: `start` the old compose
on 46.225.231.81 + restore `/etc/caddy/Caddyfile.bak.pre-explorer-removal.*` + flip the R53 A
records (hosted zone `Z07594511H8QLFFDPQYUJ`: `testnet.explorer.integralayer.com` +
`admin.testnet.explorer.integralayer.com`). After 2026-06-15 the old volumes may be archived.

## CRITICAL SAFETY RULES

### Never merge consensus-breaking changes without a coordinated upgrade

A "State Machine Breaking" change is anything that alters how blocks are validated or state is computed:
- Transaction processing logic, gas calculations, EVM opcode behavior
- Module state transitions (staking, bank, evm, feemarket, erc20)
- Protobuf message changes that affect state
- Precompile behavior changes

If such a change is merged to `main` and a validator builds from HEAD, their node will produce
different state hashes and either fall out of consensus or get slashed for double-signing.

**Process for consensus-breaking changes:**
1. Create a new tagged release.
2. Submit a software-upgrade governance proposal specifying the upgrade height.
3. ALL validators must upgrade their binary before that height.
4. Use the Cosmos SDK upgrade module (`x/upgrade`).

### Never merge upstream cosmos/evm changes blindly

The upstream `integra-evm-src` repo (`Aboudjem/evm`) tracks newer versions:
- Go 1.25.7 (the live chain uses 1.23.8)
- CometBFT v0.39.0-beta (the live chain uses v0.38.19)
- Cosmos SDK v0.54.0-rc (the live chain uses v0.53.5)

Merging these would break consensus immediately. Only cherry-pick specific fixes after testing.

### Docker builds MUST use the same Go version as the live chain

The Dockerfile pins `golang:1.23.8-alpine`. Do not change this without upgrading all validators.

### What CAN be changed safely (no binary upgrade needed)

- `minimum-gas-prices` (per-validator config, not even governance)
- Base fee / fee market params (`x/feemarket`)
- Staking params (unbonding period, max validators)
- Governance params (voting period, deposit, quorum)
- Slashing params (downtime window, jail duration)
- ERC-20 registration settings
- Per-node RPC/Caddy/firewall config (json-rpc knobs, timeouts, rate limits, ufw)

Query current params: `intgd query params subspace <module> <key>`

### What requires a binary upgrade

- EVM opcode gas costs (hardcoded in go-ethereum fork)
- New precompile contracts
- New Cosmos SDK modules
- Protobuf schema changes
- Bug fixes in state-machine logic

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

- `integra/` — main app, `cmd/intgd` binary entry point
- `x/` — Cosmos SDK custom modules
- `precompiles/` — EVM precompiled contracts (staking, distribution, governance)
- `docker/` — validator Docker setup (Dockerfile, wizard, lib.sh, tests)
- `config/` — chain constants (chain ID, EVM chain ID, denom)
- `contracts/` — Solidity contracts (ERC-20, hardhat config)
- `rpc/` — Custom RPC endpoints

## Endpoints

**Working (testnet — the only live network):**
- Public RPC (CometBFT): `https://testnet.integralayer.com/rpc`
- Public EVM JSON-RPC: `https://testnet.integralayer.com/evm`
- Explorer: `https://testnet.explorer.integralayer.com` + `https://admin.testnet.explorer.integralayer.com`
- Internal RPC LB: `https://rpc-internal.testnet.integralayer.com` (**internal only** — returns `403` externally)

**Dead — DO NOT USE:**
- `rpc.integralayer.com`, `evm.integralayer.com`, `ormos.integralayer.com`, `grpc.integralayer.com`
- All `mainnet.integralayer.com/*` (mainnet shut down)

## SSH Access

```bash
ssh -i ~/.ssh/integra root@46.225.231.81       # testnet-gateway (Integra-Helsinki, public RPC origin)
ssh -i ~/.ssh/integra root@45.77.139.208       # signer-1 (Integra-Amsterdam, validator + :8645 RPC)
ssh -i ~/.ssh/integra root@159.223.206.94      # signer-2 (Integra-SantaClara, validator + :8645 RPC)
ssh -i ~/.ssh/integra root@91.99.208.48        # explorer (Ethernal + rpc-internal LB + portal + faucet)
```

## Change Types (from .clconfig.json)

- `feat-smb` — State Machine Breaking (REQUIRES coordinated upgrade)
- `feat-api` — API Breaking (safe for running chain, may break clients)
- `fix` — Bug fix
- `imp` — Improvement
