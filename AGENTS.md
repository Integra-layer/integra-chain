# AGENTS.md — integra-chain operational guide

Fast context for agents and developers. README.md is for humans introducing the project.
CLAUDE.md holds live operational state (validator topology, RPC knobs, incident notes).
When this file and CLAUDE.md disagree on how the chain deploys or runs, **CLAUDE.md wins** —
it is maintained in-situ during incidents. This file documents the stable build/test/deploy
model and the danger list.

---

## 1. What it is

Integra Chain (`intgd`) is a Cosmos SDK + Cosmos EVM Layer 1 blockchain node for real-world
asset tokenization. The binary is built from `integra/cmd/intgd`.

Stack (from `go.mod` and `docker/Dockerfile`):
- Go **1.23.8** (live chain) / **1.24** used in CI build workflow (see gotcha §9)
- Cosmos SDK **v0.53.5** (`github.com/cosmos/cosmos-sdk v0.53.5-0.20251030204916-768cb210885c`)
- CometBFT **v0.38.19**
- go-ethereum **v1.15.11** (Cosmos EVM fork, module path `github.com/cosmos/evm`)
- IBC-go **v10**
- Solidity contracts in `contracts/` (Hardhat + Foundry)

Network status (verified 2026-05-29): **only `integra-testnet-1` is operational.**
Mainnet shut down 2026-05-14 — do not reference mainnet endpoints.

---

## 2. Architecture / data flow

```
Public internet
  └─► testnet-gateway (46.225.231.81, Hetzner, "Integra-Helsinki")
        Caddy:443 → /evm → localhost:8545 (intgd EVM JSON-RPC)
                  → /rpc → localhost:26657 (CometBFT RPC)
                  → /api → localhost:1317 (Cosmos REST)
                  → /ws  → localhost:8546

Explorer (91.99.208.48, "Integra-testnet-explorer")
  └─► rpc-internal.testnet.integralayer.com  ← Caddy vhost on explorer box
        least_conn across signer-1:8645 + signer-2:8645
        (active health: POST eth_blockNumber, 15s; @internal_only — returns 403 externally)

signer-1 (45.77.139.208, Vultr, "Integra-Amsterdam")
  └─► own Caddy:8645 → 127.0.0.1:8545  (ufw: only explorer + status probe)

signer-2 (159.223.206.94, DigitalOcean, "Integra-SantaClara")
  └─► own Caddy:8645 → 127.0.0.1:8545  (ufw: only explorer + status probe)

4th bonded validator ("integra-validator", ~50M VP, external, not Integra-operated)
```

Source: `CLAUDE.md` §Validators + §RPC topology (all facts verified against live infra
2026-05-29).

---

## 3. Repo layout

```
integra/          — Go module: main app + binary entry point (integra/cmd/intgd)
x/                — Cosmos SDK custom modules (staking overrides, etc.)
precompiles/      — EVM precompiled contracts (staking, distribution, governance)
rpc/              — Custom RPC endpoints (eth_getLogs override, etc.)
config/           — Chain constants: chain ID, EVM chain ID, denom
contracts/        — Solidity (ERC-20 etc.), Hardhat + Foundry config
docker/           — Dockerfile, setup-wizard.sh, lib.sh, entrypoint.sh, bats tests
infra/validators/ — Checked-in baseline app.toml + config.toml per node (gateway, signer-1, signer-2)
                    + check-drift.sh (diffs live vs baseline over SSH)
ops/              — Deployment runbook, cosmovisor-setup.sh, genesis-builder.sh
docs/findings/    — Post-incident write-ups (2026-05-13, 2026-05-14, 2026-05-29)
scripts/          — Utility scripts (Python)
tests/            — Integration + EVM compatibility tests (Foundry, Hardhat, viem, web3js)
```

---

## 4. Build / test / lint / run

All commands from `Makefile` and `.github/workflows/build.yml` CI — not invented.

### Build

```bash
# Local (CGO required):
cd integra && go mod download
make build
# Output: build/intgd

# Validator Docker image (pins Go 1.23.8-alpine):
docker compose -f docker/docker-compose.validator.yml up --build -d
# Image published to ghcr.io/integra-layer/validator:latest on every main merge (CI)
```

`make build` expands to:
```bash
cd integra && CGO_ENABLED=1 go build -tags netgo \
  -ldflags "-X ...Version=<git-tag> -X ...Commit=<sha> -w -s" \
  -o ../build/intgd ./cmd/intgd
```

### Test

```bash
make test                  # alias for test-unit (unit tests, 15-min timeout)
make test-unit-cover       # unit + coverage report → coverage.txt
bats docker/tests/lib_test.bats   # Docker setup wizard tests (requires bats)

# Heavier (not run in standard CI on every push):
make test-all              # evm root + integra module tests
make test-race             # race detector
make test-fuzz             # fuzz tests (CI: only on diff)
```

CI (`.github/workflows/build.yml`) excludes integration, ledger, and IBC tests from the standard Go test run:
```bash
cd integra && go test $(go list ./... | grep -v '/tests/integration\|/tests/ledger\|/tests/ibc') \
  -count=1 -timeout 300s
```

### Lint

```bash
make lint-go               # golangci-lint v2.10.1 in integra/
make lint                  # lint-go + lint-python (flake8/isort/black via tox) + lint-contracts (solhint)
```

### Format

```bash
make format                # gofmt + black + isort + shfmt
```

### Proto

```bash
make proto-all             # generate + format + lint (requires buf)
```

---

## 5. Branch & deploy model

Source: `.github/workflows/build.yml` + `infra/validators/check-drift.sh`.

| | `main` | `dev` |
|---|---|---|
| State | **Identical to dev** (same commit `7abcc01` — verified 2026-05-29) | Identical to main |
| CI trigger | push + PR | push + PR (same workflow) |
| Docker build | Yes — triggers `docker` job on `github.ref == refs/heads/main` | No docker push |
| Deploy | **Manual** — ops team SSHs into validators and restarts `intgd.service` | — |
| Infra | Hetzner/Vultr/DigitalOcean VMs, **not** App Runner / Vercel / Fly | — |

**No automated deploy pipeline exists.** The chain runs on VMs managed manually via SSH.
Config changes are versioned in `infra/validators/` and drift-checked by
`.github/workflows/validator-config-drift.yml` (daily cron + PR trigger).

Tags: `v1.0.0`, `testnet-v1` (from `git tag`).

AWS App Runner services (`city-of-integra-prod`, `integra-dashboard-backend`, etc.) are
**separate repos** — not this one. integra-chain has no apprunner.yaml.

---

## 6. Security & secrets

- SSH key: `~/.ssh/integra` — used for validator access and the CI drift-check secret
  (`INTEGRA_VALIDATOR_SSH_KEY`). Never commit this key.
- Tracked test env files (`tests/evm-tools-compatibility/foundry/.env`,
  `tests/evm-tools-compatibility/foundry-uniswap-v3/.env`,
  `tests/evm-tools-compatibility/viem/.env`) contain only test RPC URLs (non-sensitive).
  Verify before adding real secrets to these files.
- Secret files on validators (`.env.integra` + backups) are `chmod 600` (applied 2026-05-29).
- Telegram bot token: rotation deferred (marked TODO in `CLAUDE.md`).

---

## 7. DO-NOT / danger list

### Consensus-breaking — NEVER without a coordinated upgrade

- **Never merge state-machine-breaking (SMB) changes to `main`** without a tagged release +
  governance upgrade proposal + ALL validators upgrading before the target block height.
  SMB = any change to EVM opcode gas, module state transitions, protobuf schemas, precompile
  behavior. Merging to main and having a validator build from HEAD causes chain halt or
  double-sign slash. (Source: `CLAUDE.md` §CRITICAL SAFETY RULES)

- **Never blindly merge upstream `Aboudjem/evm` changes.** That repo tracks Go 1.25.7,
  CometBFT v0.39.0-beta, Cosmos SDK v0.54.0-rc — all ahead of live chain. Cherry-pick only
  after testing. (Source: `CLAUDE.md` §Never merge upstream cosmos/evm changes blindly)

- **Never change `FROM golang:1.23.8-alpine` in `docker/Dockerfile`** without upgrading all
  validators first. The live chain runs Go 1.23.8 — a Docker build with a different Go
  version would create a binary that diverges in consensus. (Source: `docker/Dockerfile:3`)

### Validator operations — ALWAYS follow the restart protocol

- **Never restart two ~200 M VP validators simultaneously.** Two big validators down = below
  ⅔ quorum = chain halt. Restart one, wait for `catching_up=false` + resumed signing, then
  move to the next. (Source: `CLAUDE.md` §Validator restart protocol)

- **Never lower gateway `gas-cap` below 300000000 or `evm-timeout` below 15s.** These are
  load-bearing for the `IRWAWrapper` ~22k-element view-call. Lowering silently breaks that
  call. (Source: `CLAUDE.md` §RPC topology; verified in `infra/validators/gateway/app.toml`)

- **Never set `intgd-throttle.service` to enabled.** Its tighten-on-saturation logic
  backfires (disabled 2026-05-29). (Source: `CLAUDE.md` §2026-05-29 fix, `docs/findings/
  2026-05-13-intgd-throttle.service`)

### Explorer / database

- **Never run `docker compose ... --remove-orphans`** on the explorer host — kills
  `integra-portal`. (Source: `CLAUDE.md` §2026-05-29 permanent-fix, Explorer section)

- **Never lower gateway `[json-rpc] max-open-connections` below 600** or signer value
  below 200 — these bounds were set deliberately to prevent the 34k-goroutine OOM spiral
  (2026-05-13 postmortem). (Source: `validator-postmortem-2026-05-13.md`, `CLAUDE.md`)

- **Never use `docker compose down`** on testnet-gateway explorer containers before
  2026-06-15 rollback window expires — use `stop` only, volumes preserved.
  (Source: `CLAUDE.md` §Migration rollback window)

### Endpoints

- **Never direct traffic to** `rpc.integralayer.com`, `evm.integralayer.com`,
  `ormos.integralayer.com`, `grpc.integralayer.com`, or any `mainnet.integralayer.com/*` —
  all dead. (Source: `CLAUDE.md` §Endpoints §Dead)

- **Never point the explorer indexer `workspaces.rpcServer` directly at
  `http://46.225.231.81:8545`** — bypasses Caddy controls, caused the 2026-05-29 504 storm.
  Use `https://rpc-internal.testnet.integralayer.com/evm` instead.
  (Source: `CLAUDE.md` §2026-05-29 EVM RPC flapping incident)

---

## 8. Known pitfalls / fixed issues

1. **Gateway IAVL pruning spam (fixed 2026-05-29):** `[base] pruning="nothing"` (archive mode)
   set on gateway — the runtime pruning routine was the cause, not a backlog. Do not revert
   to `"default"` without understanding the spray. `application.db` ≈54 GB (un-compacted
   goleveldb) is expected; use a clean-store resync later if disk pressure mounts.
   (Source: `CLAUDE.md` §DEFERRED)

2. **goleveldb LRU mutex spiral (postmortem 2026-05-13):** `eth_getLogs` with
   `block-range-cap=10000` caused 34k goroutines → chain slowdown. Fixed by capping
   `max-open-connections`, `block-range-cap`, `batch-request-limit` in `~/.intgd/config/app.toml` (per-node live config, not in this repo directly).
   Do not revert these caps. (Source: `validator-postmortem-2026-05-13.md`)

3. **Explorer load-48 (fixed 2026-05-29):** missing `idx_token_transfers_txid` index on
   `token_transfers("transactionId")` caused 9.5 M-row sequential scans per tx-detail query.
   Added index + pgbouncer + Postgres tuning → load 48→2. Do not remove these DB tunings.
   (Source: `CLAUDE.md` §2026-05-29 permanent-fix)

4. **`ip_hash` on internal RPC LB (removed 2026-05-26):** pinned clients to a wedged signer.
   LB now uses `least_conn`. Do not re-add `ip_hash`. (Source: `CLAUDE.md` §RPC topology)

5. **Go version discrepancy in CI:** `docker/Dockerfile` pins `golang:1.23.8-alpine`
   (matches live chain) but `.github/workflows/build.yml` uses `go-version: '1.24'`.
   The Docker image is what validators use; the CI binary may behave slightly differently.
   Unresolved — confirm with maintainer before relying on CI binary for production use.
   (Source: `docker/Dockerfile:3`, `.github/workflows/build.yml`)

6. **`intgd version` returns empty without ldflags:** `make build` injects ldflags; a plain
   `go build` from `integra/` does not. Use `intgd version --long` to see SDK/Go build info.
   (Source: `CLAUDE.md` §Chain Info)

7. **`unattended-upgrades` auto-reboot was enabled (fixed 2026-05-28):** caused a near-halt.
   All validators now have auto-reboot disabled. Do not re-enable.
   (Source: `CLAUDE.md` §2026-05-29 permanent-fix)

8. **`integra-rpc-autoblock` was disabled (2026-05-22):** was silently banning legitimate
   users on log-schema-mismatch + response-signal inversion. Do not re-enable without fixing
   the inversion. (Source: user memory `project_integra_gateway_helsinki.md` — unverified in
   repo; confirm with maintainer)

---

## 9. Deploy flow (testnet — no automated pipeline)

Source: `ops/README.md`, `CLAUDE.md` §Build + §Validator restart protocol.

```
1. Merge PR to main
2. CI builds + runs tests (`.github/workflows/build.yml` — push to ghcr.io/integra-layer/validator:latest)
3. SSH into each validator ONE AT A TIME (follow restart protocol):
     ssh -i ~/.ssh/integra root@<IP>
4. Pull new binary or pull new Docker image
5. Apply config changes to ~/.intgd/config/app.toml / config.toml (if any)
6. Update infra/validators/<node>/app.toml baseline (in this repo) in the same PR
7. sudo systemctl restart intgd.service
8. Verify: curl http://localhost:26657/status | jq .result.sync_info.catching_up
           # must return false before touching next validator
9. Repeat for each validator

Rollback: keep previous binary at /usr/local/bin/intgd.prev; swap + restart
```

SSH IPs (source: `CLAUDE.md` §SSH Access):
- gateway:  `root@46.225.231.81`
- signer-1: `root@45.77.139.208`
- signer-2: `root@159.223.206.94`
- explorer: `root@91.99.208.48`
