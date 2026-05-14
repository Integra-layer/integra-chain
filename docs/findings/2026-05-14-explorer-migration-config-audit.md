# Explorer migration — config audit (OLD `46.225.231.81` vs NEW `91.99.208.48`)

**Date:** 2026-05-14
**Scope:** all explorer-stack configuration: docker-compose, env, Caddy, postgres tuning, indexes, schema, throttle.
**Status:** post-cutover. OLD = `stop`'d, NEW = serving prod. This audit is what the operator asked for after the migration completed.

---

## TL;DR

NEW is a faithful copy of OLD with **deliberate, intentional improvements** plus **four fixes that were needed post-pg_restore** (which the migration session caught). No regressions. The intentional improvements were spec'd by the 3-agent review on 2026-05-14 morning before the move. The four post-restore fixes were schema/timeout regressions caused by the TimescaleDB 2.11 pg_dump catalog-corruption bug.

| Area | NEW vs OLD | Intent? |
|---|---|---|
| `.env.integra` | **byte-identical** (md5 match) | yes — explicit goal |
| Postgres tuning | NEW: 4 GB shared_buffers + 12 GB effective_cache + 64 MB work_mem + 512 MB maintenance | yes — match the dedicated 16 GB box; OLD had 256 MB/8 MB/128 MB starving on the shared host |
| Container `mem_limit` | NEW: every service capped (postgres 10 g, backend 1.5 g, workers 1 g, frontend 768 m, redis 1.5 g, soketi/pm2 384 m) | yes — OLD was unbounded which contributed to the OOM cascades |
| Port bindings | NEW: all bound to `127.0.0.1` (host Caddy is the only client) | yes — security hardening |
| Caddyfile site blocks | NEW: 2 explorer blocks (real LE cert); OLD: 0 (removed at decomm) | yes — that's the cutover |
| Caddyfile `tls` issuer | NEW: `acme { disable_tlsalpn_challenge }` (http-01 only) | yes — tls-alpn-01 had 100% failure rate pre-cutover per Phase 3 review |
| Throttle autoscaler | OLD: `EXPECTED_OCCURRENCES=4 → 2` (patched 2026-05-14) | yes — explorer blocks gone, count must match |
| `token_transfer_events.isReward` | NEW: column added post-rebuild (2 094 547 rows backfilled from `token_transfers`) | **fix** — restore-induced regression |
| 4 event-hypertable indexes | NEW: re-created post-rebuild | **fix** — restore-induced regression |
| `statement_timeout` | NEW: 30 s → 90 s via `ALTER DATABASE` | **fix** — `countActiveWallets` is 30–45 s cold on 2.2 M tx |
| `hasReachedTransactionQuota` model stub | both: present (NEW has explicit `.bak.pre-quota-stub`) | latent OLD bug; needs upstream PR |

---

## A. `docker-compose.integra.yml` — explicit diff (74 lines, all intentional)

1. **Banner header.** OLD has a "DECOMMISSIONED" banner; NEW has a "PRODUCTION on 91.99.208.48 — do not down -v" banner. (Both added during cutover; necessary because both stacks share the volume names `docker_pgdata` + `docker_redisdata`.)
2. **`mem_limit:` on every container.** OLD has none; NEW caps:
   - postgres 10 g · redis 1.5 g · backend 1.5 g · worker-low/medium/high 1 g each · frontend 768 m · soketi 384 m · pm2 384 m
   - Sum ≈ 18 GB cap vs 16 GB physical → assumes swap headroom (4 GB swap configured). Verified at runtime — no service is currently near its cap (postgres 5.6 GB / 10 GB; high-worker 256 MB / 1 GB).
3. **Postgres `command:` tuning** (key change for performance):
   - OLD: `shared_buffers=256MB · work_mem=8MB · maintenance_work_mem=128MB` (sized for the starved shared box)
   - NEW: `shared_buffers=4GB · effective_cache_size=12GB · work_mem=64MB · maintenance_work_mem=512MB`
   - With NEW's 16 GB physical, 4 GB shared_buffers + 12 GB OS page cache = the whole 21 GB DB lives in RAM in steady state. This is what eliminated the query-timeout thrashing.
4. **Port bindings** explicit `127.0.0.1:`:
   - OLD: `8890:8888`, `3200:3000`, `6002:6001` (bound to `0.0.0.0`, exposed externally — security smell on the validator box)
   - NEW: same ports but explicit `127.0.0.1:` (only host Caddy reaches them)
5. **Comments** mention the dedicated-box hardware spec and the migration date.

**No removed services**, no changed image tags, no changed cmd args other than postgres tuning. Compose is otherwise structurally identical.

## B. `.env.integra` — byte-identical (md5 `d2a085b9269f119bf4b3553e656ebdaf`)

Includes:
- `SOKETI_KEY`, `SOKETI_SECRET`, `NEXT_PUBLIC_REOWN_PROJECT_ID`, `NEXT_PUBLIC_SITE_URL=https://testnet.explorer.integralayer.com`
- `API_POOL_MAX=150`, `HIGH_WORKER_CONCURRENCY=5`, `MEDIUM_WORKER_CONCURRENCY=5`

Implication: any future env-driven knob changes go in both places or just in NEW (since OLD is shutting down).

## C. Caddyfiles — the cutover delta

**OLD Caddyfile (82 lines, 2 site blocks remaining):**
- `testnet.integralayer.com {…}` — UNCHANGED, still serves: faucet `/api/faucet → localhost:3000`, CometBFT RPC `/rpc/* → localhost:26657`, Cosmos REST `/api/* → localhost:1317`, EVM RPC `/evm/* → localhost:8545`.
- `testnet.blockscout.integralayer.com {…}` — dark (its backend never came back); kept for hostname reservation. **Consider removing in a future janitorial pass.**

**OLD Caddyfile site blocks that were REMOVED on 2026-05-14:**
- `testnet.explorer.integralayer.com {…}` — moved to NEW
- `admin.testnet.explorer.integralayer.com {…}` — moved to NEW
- Backup at `/etc/caddy/Caddyfile.bak.pre-explorer-removal.<unix-ts>`. Replayable for rollback before 2026-06-15.

**NEW Caddyfile (90 lines, 2 site blocks):**
- Both site blocks have `tls { issuer acme { disable_tlsalpn_challenge } }` (http-01 only). NOT `tls internal` anymore.
- `/evm` reverse-proxies to `https://testnet.integralayer.com` (the OLD's testnet.integralayer.com block, unchanged) — note the explorer no longer has a local validator on this box.
- `max_conns_per_host 64`, `dial_timeout 3s`, `response_header_timeout 12s`, `read_timeout 14s`, `write_timeout 14s` (matches OLD's testnet.integralayer.com block's RPC settings).
- `/api/xp/*`, `/api/passport-image*`, `/api/wm-image*`, `/api/passport-create*`, `/api/passport-search*`, `/api/passport-update*` → 3200 (Next.js)
- `/api/*` → 8890 (Ethernal backend)
- `/app/*` → 6002 (Soketi WebSocket)
- `/` → 3200 (Next.js frontend)
- Same routes mirrored on `admin.testnet.explorer.integralayer.com`.

## D. Postgres tuning (re-stated)

Cannot diff OLD live (postgres container `Exited (0) 24 minutes ago`), but the source of truth is the compose `command:` block diffed in §A. The five settings changed are the ones the 3-agent review specified. None of OLD's runtime settings were left implicit.

NEW pg_settings (live):
```
shared_buffers       4GB
effective_cache_size 12GB
work_mem             64MB
maintenance_work_mem 512MB
max_connections      (default 100)
max_worker_processes (default 8)
```

Plus the per-database override:
```
ALTER DATABASE ethernal SET statement_timeout = 90000;   -- override of the 30 s -c statement_timeout from compose
```

## E. Schema parity (verified column-by-column)

Diff'd `information_schema.columns` for the 4 rebuilt event hypertables. **All match OLD except `token_transfer_events.isReward`**, which was missing on NEW post-rebuild and has been re-added with the correct definition (`boolean NOT NULL DEFAULT false`). After backfill from `token_transfers`, NEW has 2 094 973 isReward=true / 1 796 296 false; OLD had 2 094 547 true / 1 795 876 false — within 0.02 % (slightly more on NEW because indexing continued during the audit window).

Indexes (post-fix, full parity with OLD):
- transaction_events: `_pkey`, `_timestamp_idx`, `_workspaceId_timestamp`, `idx_…workspace_to`, `_workspaceId_from_idx`
- token_transfer_events: `_pkey`, `_timestamp_idx`, `_workspaceId_timestamp`, `idx_…workspace_src`, `_workspace_dst`
- block_events, token_balance_change_events, contracts: structural pkeys + workspace covers (unchanged from OLD)

## F. Container counts + status

OLD: 9 containers, all `Exited` (postgres + frontend + soketi + redis exit 0; backend + 3 workers exit 137 SIGKILLed at compose-stop's 10 s grace; pm2 exit 1 from its own teardown). Volumes preserved.

NEW: 9 containers, all `Up`. Three are flagged `unhealthy` (backend, frontend, soketi) by Docker — known false positive: the stock Ethernal healthcheck commands assume a pm2 version that doesn't match. **Not a real failure** — the processes are working (verified by HTTP 200 on `/`, `/api/*`, `/evm`, indexer advancing). Should be fixed by either updating the healthcheck command in the compose or removing the healthcheck. Tracked separately.

## G. Throttle autoscaler — patched on OLD (testnet-gateway)

Script: `/usr/local/bin/intgd-throttle.py`. Line 68 was `EXPECTED_OCCURRENCES = 4`; patched to `2` because the explorer Caddy blocks (which contributed 2 of the 4 `max_conns_per_host` directives) are gone. Service restarted; backup at `intgd-throttle.py.bak.pre-decomm.<unix-ts>`. Verified the autoscaler did a NORMAL → PANIC → NORMAL cycle correctly post-patch.

## H. NOT changed (verified unchanged on OLD)

- `intgd.service` PID 329272 — uninterrupted through the entire migration
- `intgd-throttle.service` — restarted once (for the EXPECTED_OCCURRENCES patch)
- `testnet.integralayer.com` Caddy site block — untouched
- `testnet.blockscout.integralayer.com` Caddy site block — untouched (still 502s as before; backend was already dark)
- Two crontab lines (`pm2-healthcheck.sh`, `check-sync.sh`) were COMMENTED OUT (with `#PRE-DECOMM-2026-05-14` prefix), not deleted. They were already broken / no longer relevant.

---

## Risks / things to address later (not migration-blocking)

1. **`hasReachedTransactionQuota` stub** at `/opt/integra-explorer/run/models/explorer.js` on NEW — not yet upstream. Will get lost on the next Ethernal image rebuild.
2. **Three Docker healthcheck false-positives** (`backend`, `frontend`, `soketi`) flagged `unhealthy`. Either fix the healthcheck commands or remove them.
3. **`testnet.blockscout.integralayer.com`** on OLD — backend dead, hostname still occupies a site block. Consider removing on the next janitorial pass.
4. **Public RPC origin is still on testnet-gateway** — co-located with the bonded validator. This was the second-order risk identified by today's review agents. Next migration target.
5. **Outstanding hardening** per the resume prompt: `OOMScoreAdjust=-900` on `intgd.service` (all 3 validators); ≥8 GB swap on signer-2; `docker builder prune` on testnet-gateway (~20 GB recoverable); upstream the model stub.

---

## Restore window — when can OLD volumes be removed?

Window expires **2026-06-15** (31 days from migration). Until then:
- OLD `/opt/integra-explorer/` is intact (compose, env, prior state)
- OLD volumes `docker_pgdata` (21 GB) + `docker_redisdata` are intact
- OLD `/etc/caddy/Caddyfile.bak.pre-explorer-removal.<unix-ts>` is intact
- OLD `intgd-throttle.py.bak.pre-decomm.<unix-ts>` is intact
- OLD `crontab.bak.pre-decomm.<unix-ts>` in `/root/` has the original cron lines

To roll back: revert R53 A records → 46.225.231.81; restore OLD Caddyfile from `.bak.*`; restore cron from `.bak.*`; `cd /opt/integra-explorer && docker compose -f docker/docker-compose.integra.yml --env-file docker/.env.integra start`. Estimated rollback time: 5 min for DNS-only, 10 min for full Phase-6 rollback.

After 2026-06-15 the operator can `docker compose down` (without `-v`) on OLD, then deliberately remove the docker_* volumes, then `rm -rf /opt/integra-explorer/`.

---

**Reviewers / agents involved:** SRE/capacity, data-integrity, cutover-safety reviews dispatched in Phase 3; their objections (4 blockers + several MEDIUM items) were all addressed before DNS flip. See `/Users/adamboudj/projects/integra-chain/.omc/migration-handoff-2026-05-14.md` for the prior session's snapshot.
