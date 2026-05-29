# 2026-05-29 — Explorer box (91.99.208.48) overload — diagnosis + remediation plan

> Diagnosis is read-only and verified against primaries (live `pg_stat_activity`, `pg_indexes`,
> `pg_stat_user_tables`, Caddy journal). **Nothing on the box was changed** to produce this plan.
> Public EVM RPC flapping is already fixed separately (see INCIDENT.md); this covers the box overload
> that fires the **"Explorer DOWN: timeout"** alerts and keeps `/evm` fragile (Caddy is co-resident).

## Symptoms
- Load average **~52 / 48 / 47** on a **4 vCPU** box; `0% idle`; Postgres **347% CPU**.
- Explorer homepage **times out at 12s** → "Explorer (Testnet) DOWN: timeout" alerts.
- Postgres: **133 backends, 102 on `LWLock:BufferMapping`**; slowest active queries **87–89s**.

## Root cause (verified)
1. **Missing index — the driver.** The Ethernal transaction query (`backend-api`, ~96 concurrent
   copies) has a correlated subquery:
   `SELECT COUNT(*) FROM token_transfers WHERE "transactionId" = "Transaction".id AND "isReward" = false`.
   `token_transfers` = **9,481,234 rows / 2,678 MB**, indexed only on `id`, `transactionLogId`,
   `workspaceId` — **no `transactionId` index** (`pg_indexes` confirms; `pg_stat_user_tables.seq_scan = 74,801`).
   So every transaction-detail query **seq-scans 2.6 GB**. (The sibling subqueries on
   `token_balance_changes` and `transaction_trace_steps` *are* indexed on `transactionId` → 0 seq-scans.)
   This is the 2026-05-14 TimescaleDB pg_restore index-loss pattern (see the `timescaledb-restore`
   skill); the `transactionId` index on `token_transfers` was never restored.
2. **Pile-up.** ~1 tx-detail req/s × ~87s/query ⇒ ~96 concurrent identical queries ⇒
   `LWLock:BufferMapping` thrash ⇒ Postgres pegged ⇒ load 52.
3. **Amplifiers:** `shared_buffers = 256 MB` (far too small for a 6.3 GB hot `transactions` table +
   2.6 GB/4.6 GB subquery tables → constant buffer-map churn); `max_connections = 800` (no concurrency
   cap → thundering herd); `jit = on` (overhead on repeated OLTP queries).
4. **Abuse flood (secondary, CPU on Caddy):** ~**447 req/s** to public `testnet.integralayer.com`,
   almost all `/evm`. Status mix (3 min): 58,956×200, **24,282×429**, 9,505×204. The `@flood_*`
   matchers correctly 429 most of it, but **`turfdex.fun` (7,096 req/3min) is NOT in the
   `@flood_referer` regex** (only plotswap|mysteryegg|omnihub|t-bank.finance are). Caddy still spends
   CPU processing the flood. `test-gob.integralayer.com` (City of Integra game, 27,427) is high-volume
   legit `/evm`.

## Remediation plan (prioritized; commands are for the operator — not yet run)

### P0 — Restore the missing index (highest leverage, low risk, reversible)
```sql
-- run inside: docker exec -i integra-explorer-postgres psql -U postgres -d ethernal
-- FIRST confirm token_transfers is NOT a TimescaleDB hypertable (if it is, drop CONCURRENTLY and
-- use Timescale-aware creation; chunks lock briefly):
SELECT * FROM timescaledb_information.hypertables WHERE hypertable_name = 'token_transfers';

-- if a plain table (expected), build without locking writes:
CREATE INDEX CONCURRENTLY IF NOT EXISTS "token_transfers_transactionId_idx"
  ON public.token_transfers ("transactionId");
ANALYZE public.token_transfers;
```
- `CONCURRENTLY` = no exclusive lock; reads/writes continue. It does add IO/CPU while building ~2.6 GB
  on an already-hot box (a few minutes) — acceptable, it's the fix; if it ever fails it leaves an
  INVALID index (just `DROP INDEX` and retry).
- **Expected:** the 87s queries collapse to ms → the 96 concurrent backends drain → Postgres CPU and
  load drop sharply → explorer stops timing out.
- **Verify:** `SELECT seq_scan, idx_scan FROM pg_stat_user_tables WHERE relname='token_transfers';`
  (seq_scan stops climbing); `EXPLAIN` of the tx query shows an Index Scan on the new index;
  `uptime` load falls; explorer home loads in <2s.

### P1 — Postgres memory/config (needs a Postgres restart — blips the explorer, NOT public `/evm`)
- `shared_buffers` **256 MB → 4 GB** (25% of 16 GB) — the real fix for BufferMapping contention.
- `work_mem` 8 MB → **16 MB** (cautious; many connections).
- `jit` **off**.
- `effective_cache_size` ~11 GB (already fine).
- Apply in the postgres container's config (postgresql.conf or compose command/`-c` flags), then
  `docker restart integra-explorer-postgres`. The indexer/backend reconnect and the indexer catches
  up. **Public `/evm` is unaffected** (it is Caddy→signer LB, no Postgres). Do it in a short window.

### P2 — Cap DB concurrency (prevent future thundering herd)
- `max_connections = 800` is far too high for 4 vCPU. Either lower the **Ethernal backend pool size**
  (env/config) to ~20–40, or put **pgbouncer** (transaction pooling) in front so heavy queries can
  never pile to ~100 again.

### P3 — Flood / edge relief
- Add **`turfdex`** to the explorer `@flood_referer` and `@flood_origin` regexes
  (`/etc/caddy/Caddyfile` ~lines 82/84): `(?i)(plotswap|mysteryegg|omnihub|t-bank\.finance|turfdex)`.
  One-line edit + `caddy adapt` validate + `systemctl reload caddy`.
- Re-introduce a **working per-IP rate limit** — the `caddy-ratelimit v0.1.0` module misfires (false
  429s; it was removed today on both boxes). Options: rebuild Caddy with a current caddy-ratelimit via
  xcaddy, OR nftables/iptables that handles HTTP/2-reused/IPv6-mapped conns, OR Cloudflare edge rules.
- **Cloudflare edge** (documented highest-leverage missing control): absorbs the ~447 req/s flood
  upstream and hides the origin. Deferred elsewhere but most impactful for the flood.

### P4 — Architecture (the real root; bigger change)
- Public `testnet.integralayer.com` should **not** live on the overloaded explorer/DB box. Move the
  public RPC origin to the gateway (proxy `/evm`→signer LB) or a dedicated tiny proxy, so public RPC
  availability is decoupled from the explorer + Postgres. Then this box only does explorer + indexer.

## Risk notes
- P0 is the safe high-impact move (no lock with CONCURRENTLY; verify hypertable first).
- P1/P2 require a Postgres restart / pooler — blips the explorer (frontend/indexer) for seconds, not
  the public RPC. Schedule deliberately.
- Per the validator-restart protocol, none of this touches intgd or consensus — it is all explorer-box
  app/DB/edge config.
