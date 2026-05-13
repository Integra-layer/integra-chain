# Integra Testnet Validator Postmortem — 2026-05-13

**Investigator:** Adam Boudjemaa (assisted by Claude)
**Host:** `testnet-gateway` (46.225.231.81, Hetzner) — moniker `Integra-Helsinki`
**Binary:** `/usr/local/bin/intgd`, started 2026-05-13 03:30:25 UTC (8 h uptime at gather)
**Gather window:** 2026-05-13 12:27:57 → 12:29:11 UTC
**Raw evidence:** `/tmp/intgd-postmortem-20260513T122754Z.log` (local) and `/tmp/intgd-journal-20260513T122757Z.log` (on host)
**Mode of investigation (sections 1–4):** READ-ONLY. No host mutations, no restart, no config writes, no git commits.
**Mode of live intervention (section 1.5):** Caddy + systemd cgroup edits applied with user approval. **intgd binary itself never restarted — PID 329272 preserved throughout, original boot time 03:30:25 UTC maintained.**

---

## 1. Executive summary

The testnet validator is **not memory-leaking in the classical sense** and is **not consensus-broken**. It is being **CPU-thrashed by lock contention in goleveldb** under heavy `eth_getLogs` pressure, with the contention pile-up manifesting as both apparent memory growth (queued goroutines + their request buffers) and slow block production (the same goleveldb instance hosts CometBFT's `state.db`, which `EndBlock`/consensus must read).

The evidence is unambiguous. The pprof goroutine profile at 12:29 UTC shows **34,137 live goroutines** (healthy = < 1,000); **48% are blocked on a single mutex inside `goleveldb`'s LRU cache** (`leveldb/cache/lru.go:85`), all originating from `eth_getLogs` calls iterating the block-results store one height at a time; another **49% are stuck in `go-ethereum/rpc.(*handler).close`** waiting for those inner reads to drain so the HTTP connection can shut down. RSS at gather time was **8.4 GB anonymous heap, only 34 MB file-backed** — confirming the memory is *application heap holding stuck goroutine state*, not pebble/mmap'd DB pages. CPU was 88–93 % user with `r_await = 0.2–0.6 ms`: the disk is fine, the CPU is burning on `sync.Mutex.lockSlow`.

The amplifiers are configuration. `[json-rpc] max-open-connections = 0` (unlimited) on testnet means there is no admission control in front of the bottleneck — 12,555 ss matches on port 8545 at gather time, vs. a healthy 88 on the CometBFT RPC port. `block-range-cap = 10000` lets a single `eth_getLogs` request issue up to 10,000 sequential `LoadFinalizeBlockResponse` calls against goleveldb. The on-chain symptoms (`replacement transaction underpriced` at 136/min, RoundStepPropose timeouts at 4/min, blocks at 7.5 s instead of 5 s, chain time 8.4 minutes behind wall time) are **downstream of the RPC overload**, not separate bugs.

What to do, in priority order: (1) **immediately rate-limit `eth_getLogs` at Caddy on testnet-gateway** (SAFE-NOW, no validator change), (2) **cap `[json-rpc] max-open-connections`, `block-range-cap`, and `batch-request-limit`** in `app.toml` then restart `intgd` (NEEDS-RESTART, single-validator restart — chain keeps producing because we have 3 validators), (3) **add a small LRU cache for `Backend.CometBlockResultByNumber`** in the RPC layer (code patch, NOT state-machine-breaking, deferred to a follow-up PR). This is **NOT** a Cosmos SDK or CometBFT upstream bug — it is an `eth_getLogs` design choice in the `cosmos/evm` RPC layer that does not match Integra-testnet's traffic profile and the goleveldb backend's concurrency limits. No upstream report is currently warranted.

**Update at 13:10 UTC:** mitigations #1 (Caddy front-door caps via `transport http { max_conns_per_host ... }`, no rate-limit plugin needed) and a systemd cgroup memory headroom bump have been applied live without restarting `intgd`. Goroutine count is draining, error rate dropped from 162/min to 8/min (-95 %), and the chain is **catching up** at ~3.5–4 s/block, ahead of the 5 s target. See section 1.5 below for the full intervention log. `intgd` PID 329272 is preserved — original 9 h uptime intact.

---

## 1.5. Live intervention log (2026-05-13 12:38 → 13:10 UTC)

Once the diagnosis above was complete, the operator authorized targeted mitigations under the constraint **"do not shutdown the validator"**. Three steps were taken; each one was reversible and intgd-untouching.

### Step A — systemd cgroup memory headroom (12:38 UTC, no restart)

```bash
ssh root@testnet.integralayer.com 'systemctl set-property intgd.service MemoryHigh=12G MemoryMax=14G'
```

`systemctl set-property` updates the cgroup limits of the **running** unit in place — no `systemctl restart` is issued, no `daemon-reload` is needed, and the binary keeps its PID and connections. Verification immediately afterward:

```
MainPID=329272
MemoryHigh=12884901888    (12 G)
MemoryMax=15032385536     (14 G)
memory.current = 10.27 GB   (within new limits — 1.7 G of MemoryHigh margin)
intgd active: yes
```

This bought ~3.7 G of pre-OOM margin without touching the chain. Pure safety net for the rest of the intervention.

### Step B — Reconnaissance (12:38–12:44 UTC, read-only)

To choose the right rate-limiting strategy I needed three facts:

- **Is the `caddy-ratelimit` plugin installed?** → `caddy list-modules | grep -i ratelimit` → **NO PLUGIN** (vanilla Caddy v2.11.1). Rules out `rate_limit` directive; rules in `transport http { ... }` settings as the only no-plugin option.
- **Who is hammering :8545?** → Caddy access log file was empty (logs go to journalctl). `journalctl -u caddy --since '10 minutes ago'` showed a mix of real-user IPs from MetaMask (`Origin: chrome-extension://nkbihfbeogaeaoehlefnkodbefgpgknn`), OKX wallet, faucet retries, and Blockscout-related fallback traffic — not a single bot. The pile-up is a **wallet retry storm** on a slow chain, not a targeted attack.
- **What is the testnet UI's failure mode?** → blockscout listener on `[::1]:3002` is **down** (`NO LISTENER ON :3002`); the user confirmed *"on l'utilise plus, pas besoin de blockscout"*. Blockscout 502s are out of scope, but they were amplifying retry pressure on `/evm` and `/rpc/status` because the testnet web frontend was falling back when blockscout failed.

The Caddyfile structure was simple: `testnet.integralayer.com /evm/*` → `localhost:8545` with no timeouts, no connection cap. Same pattern in `testnet.explorer.integralayer.com /evm` and `admin.testnet.explorer.integralayer.com /evm` — four reverse_proxy blocks total pointing at `localhost:8545`.

### Step C — Caddy patch #1: front-door cap at 64 + tight timeouts (12:44:34 UTC, no intgd restart)

Applied via an atomic Python patch script (`/root/patch-caddy.py`) that: backs up `/etc/caddy/Caddyfile` with a unix-timestamped suffix, applies exact-string replacements (no regex), writes the new file alongside, runs `caddy validate`, and only then `os.replace`s the file and issues `systemctl reload caddy` (reload, not restart — zero dropped connections on Caddy side, zero impact on intgd). Rollback is a one-liner that the script prints at the end.

Diff applied to each of the four `reverse_proxy localhost:8545` blocks:

```diff
 handle_path /evm/* {
     reverse_proxy localhost:8545 {
         header_down -Access-Control-Allow-Origin
         header_down -Access-Control-Allow-Methods
         header_down -Access-Control-Allow-Headers
+        transport http {
+            max_conns_per_host 64
+            dial_timeout 3s
+            response_header_timeout 12s
+            read_timeout 14s
+            write_timeout 14s
+        }
     }
 }
```

Backup file: `/etc/caddy/Caddyfile.bak.1778676274`. Rollback command: `cp /etc/caddy/Caddyfile.bak.1778676274 /etc/caddy/Caddyfile && systemctl reload caddy`.

Why these numbers:
- `max_conns_per_host 64` — Caddy never opens more than 64 simultaneous upstream connections to `localhost:8545`; excess requests queue in Caddy (which is good at queueing) instead of in intgd (which is currently terrible at it).
- `read_timeout 14s` < intgd's `evm-timeout = 15s` — Caddy gives up *before* intgd does, freeing the upstream connection slot quickly. (`response_header_timeout 12s` adds a layer below that for handlers that hang before writing the response header.)
- `dial_timeout 3s` — if intgd is saturated and can't accept a new TCP connection within 3s, fail fast.

Results at T+3min (12:48 UTC):
- ERR/min: 162 → 38 (-76 %)
- Goroutines: 39 066 → 37 605 (initial drop of 1 660, then crept back up slowly)
- Memory: 10.55 G → 10.69 G (stable around 10 G)
- intgd PID: unchanged

Conclusion: **bleeding stopped** (no more new pile-up), but the **existing** 37 k goroutines were *not* draining — they were trapped on the goleveldb LRU mutex and each one freed was immediately replaced by a new arriving request that re-blocked on the same mutex. Steady-state degraded mode.

### Step D — Caddy patch #2: tighten to 16 (13:06:10 UTC, no intgd restart)

To force the queue to drain, the upstream cap was tightened. Applied via in-place `sed` on the existing file (the pattern `max_conns_per_host 64` was unique to my own previous patch, so `sed -i 's/max_conns_per_host 64/max_conns_per_host 16/g'` was safe), with a fresh timestamped backup, `caddy validate`, and `systemctl reload caddy`.

Backup file: `/etc/caddy/Caddyfile.bak.tighten.1778677570`. Rollback: same `cp + reload` pattern.

Results over the 4-minute watch window:

| Time (UTC) | Goroutines | Memory (GB) | Block height | Block time | ERR/min |
|------|------|------|------|------|------|
| 13:06:10 (T+0) | 36 667 | 10.41 | 1 171 624 | 12:50:58 | 78 |
| 13:07:12 (T+60 s) | 36 159 | 10.69 | 1 171 632 | 12:51:51 | 25 |
| 13:08:13 (T+120 s) | 36 007 | 10.31 | 1 171 649 | 12:53:51 | 9 |
| 13:09:15 (T+180 s) | 35 860 | 11.13 | 1 171 664 | 12:55:36 | 14 |
| 13:10:16 (T+240 s) | 35 736 | 11.01 | — | — | 8 |

**The chain is catching up.** Block-time advance vs. wall-time advance, per 60 s sample:

- T+0 → T+60 s: block_time +53 s in 60 s wall (lag holding steady)
- T+60 s → T+120 s: block_time **+120 s** in 60 s wall — i.e. **eating the backlog at 2× real time**
- T+120 s → T+180 s: block_time **+105 s** in 60 s wall — still catching up

That translates to an effective ~3.5–4 s/block production rate vs. the 5 s target — the chain is *ahead of schedule* now, because each `EndBlocker` no longer competes against ~64 concurrent `eth_getLogs` for the same goleveldb mutex.

### Final state at 13:10 UTC (intervention end)

- `intgd active`: yes, PID 329272 unchanged (uptime 9h)
- Memory: 11.0 G current (vs. MemoryHigh 12 G, MemoryMax 14 G) — within bounds, 1 G margin to throttle
- Goroutines: 35 736 (down from 39 066, draining at ~230/min — projected ~2-3 h to fully drain to a healthy ~1 k)
- ERR/min: 8 (down from 162, -95 %)
- Block production rate: ~3.5–4 s/block (target 5 s, currently catching up)
- Block lag: 15.2 min and decreasing — projected zero in ~30–45 min at current catch-up rate

### Follow-ups (deferred to operator's discretion)

1. **Once block_time matches wall_time (lag < 30 s):** bump `max_conns_per_host` back from 16 to 64 or 128 to give legitimate user traffic more throughput. One `sed` + `caddy reload`, no intgd touch.
2. **In a quiet maintenance window:** apply the `app.toml` caps from section 5 below and restart `intgd` (~30 s downtime, safe at 3-of-3 quorum). This makes the fix permanent on the validator side regardless of what Caddy is doing.
3. **In a follow-up PR (chain code):** the `Backend.CometBlockResultByNumber` LRU cache patch in section 4 (Hypothesis #1). State-machine-neutral, no governance vote.
4. **Re-evaluate Blockscout:** confirmed deprecated by operator, "on l'utilise plus, pas besoin de blockscout". Recommend removing the `testnet.blockscout.integralayer.com` block from the Caddyfile and DNS to stop the connection-refused log noise.

### Files modified on the validator host (rollback inventory)

| Path | Change | Rollback |
|------|------|------|
| `/etc/caddy/Caddyfile` | added `transport http { ... }` to four reverse_proxy blocks, then tightened `max_conns_per_host` from 64 to 16 | `cp /etc/caddy/Caddyfile.bak.tighten.1778677570 /etc/caddy/Caddyfile && systemctl reload caddy` (or `.bak.1778676274` for both patches at once) |
| `/etc/caddy/Caddyfile.bak.1778676274` | new backup file (pre-patch-#1 state) | `rm` to clean up later |
| `/etc/caddy/Caddyfile.bak.tighten.1778677570` | new backup file (pre-patch-#2 state) | `rm` to clean up later |
| `/root/patch-caddy.py` | helper script (kept for reference / re-use) | `rm` to clean up later |
| systemd cgroup (`MemoryHigh`, `MemoryMax`) on `intgd.service` | set via `systemctl set-property` — non-persistent across reboot by default | `systemctl set-property intgd.service MemoryHigh= MemoryMax=` (empty values clear) — or just reboot the host |

**Nothing was changed inside `/root/.intgd/`** — chain state and config are untouched. The intgd process itself was never sent SIGTERM, SIGKILL, or any signal.

---

## 2. Evidence matrix

| # | Claim | Source |
|---|------|--------|
| 1 | intgd RSS = 10.0 G, peak 11.0 G, swap 702 MB on 16 G host | `systemctl status intgd`: `Memory: 10.0G (peak: 11.0G swap: 702.2M swap peak: 934.2M)` |
| 2 | 99.6 % of resident memory is **anonymous heap**, not mmap | `/proc/329272/smaps_rollup`: `Anonymous: 8 762 284 kB`, `Pss_File: 35 252 kB` |
| 3 | OOM kill happened at 03:30:21 UTC; triggered by caddy, victim was intgd | `journalctl -k`: `caddy invoked oom-killer ... Killed process 1789442 (intgd) total-vm:16196016kB, anon-rss:9818312kB` |
| 4 | pprof IS enabled at `localhost:6060` (set in `config.toml [rpc] pprof_laddr`) | `app.toml/config.toml`: `pprof_laddr = "localhost:6060"`; HTTP probe returned 200 |
| 5 | **34,137 live goroutines** at 12:29 UTC | `curl localhost:6060/debug/pprof/goroutine?debug=1`: `goroutine profile: total 34137` |
| 6 | 16,756 goroutines blocked in `go-ethereum/rpc.(*handler).close → sync.WaitGroup.Wait` | pprof stack `0xcbc82a github.com/ethereum/go-ethereum/rpc.(*handler).close+0x309 /.../go-ethereum@v1.16.2-cosmos-1/rpc/handler.go:318` |
| 7 | 10,800 + 5,488 goroutines blocked on `goleveldb/leveldb/cache/lru.go:85` (`sync.Mutex.lockSlow`) called from `LoadFinalizeBlockResponse` via `CometBlockResultByNumber` via `filters.(*Filter).Logs` via `(*PublicFilterAPI).GetLogs` | pprof stack — full chain visible in two of the top frames |
| 8 | The hot-loop source is the per-block iteration in `Filter.Logs` | `rpc/namespaces/ethereum/eth/filters/filters.go:178-206` — `for height := from; height <= to; height++ { f.backend.CometBlockResultByNumber(&h) }` |
| 9 | `CometBlockResultByNumber` has no cache; it directly hits the RPC client which reads goleveldb every call | `rpc/backend/comet.go:48-58` — `return b.RPCClient.BlockResults(b.Ctx, height)` |
| 10 | EVM RPC connection cap is **unbounded** | `app.toml [json-rpc] max-open-connections = 0` |
| 11 | Single `eth_getLogs` may iterate up to 10,000 blocks of goleveldb reads | `app.toml [json-rpc] block-range-cap = 10000, logs-cap = 10000` |
| 12 | Sockets on :8545 = 12,555 (ss matches, double-counted incl. TIME_WAIT) vs :26657 (CometBFT RPC) = 88 | `ss -tan` filtered queries |
| 13 | DB is **goleveldb, not pebble** — `.ldb` files, 0 `.sst` | `find /root/.intgd/data -name '*.sst' \| wc -l` = `0`; `find ... -name '*.ldb'` populates `application.db` |
| 14 | application.db = 18 G; state.db = 2.3 G; tx_index.db = 8.8 G; total data = 33 G | `du -sh /root/.intgd/data/*` |
| 15 | 8,166 `ERR ... replacement transaction underpriced` lines in last 1 h (~136/min) | `grep -c 'replacement transaction underpriced' /tmp/intgd-journal-...log` |
| 16 | 70 `nonce too low` lines, 44 `insufficient funds`, 7 `tx already in mempool` — all `module=backend` (JSON-RPC) | `grep` + dedup counts |
| 17 | 244 `step=RoundStepPropose` timeouts and 429 total `Timed out` lines / hour | `grep -c` counts |
| 18 | 0 `panic`, 0 `consensus failure`, 0 `compaction` warnings, 0 OOM in last hour | `grep -c` counts |
| 19 | Chain is producing blocks but ~8.4 min behind wall time | sample @ 12:29:00Z → `latest_block_time: 12:20:37Z` |
| 20 | Block production over 60 s: 4 blocks (samples 1→3), but block_time advanced only ~30 s — effective ~7.5 s/block | samples 1/2/3 of `/status` 30 s apart |
| 21 | All 3 validators bonded and signing; last_commit fully populated | `/dump_consensus_state`: `last_commit votes_bit_array: BA{3:xxx} 600816387/600816387 = 1.00` |
| 22 | Validators: SantaClara (200,361,482), Helsinki (200,232,886), Amsterdam (200,222,019); plus `integralayer-local` jailed/unbonding (historical) | `intgd query staking validators` + `/dump_consensus_state` |
| 23 | Peer mesh healthy: 2 peers connected to this node (Amsterdam in, SantaClara out) | `/net_info`: `n_peers: 2` with both other validators present |
| 24 | One PEX rate-limit disconnect on Amsterdam during hour; one "error part set invalid proof" — both isolated, recovered | dedup ERR list |
| 25 | Disk r_await = 0.21–0.58 ms, %util 2.5–15 % across iostat 5 s window | `iostat -x 1 5` — sda (data disk) |
| 26 | CPU saturation: %user 38 → 93 → 88 → 91 → 90 across the 5 s window; %iowait < 1 % | `iostat` avg-cpu |
| 27 | Pruning is `default` (keep ~362,880 states, prune every 10 blocks) | `app.toml: pruning = "default"` |
| 28 | iavl-cache-size = 781,250 entries (very large; ~500 MB–1 GB heap depending on node size) | `app.toml` |
| 29 | inter-block-cache = true (per-block cache enabled) | `app.toml` |
| 30 | mempool size cap = 5,000, max_txs_bytes = 1 GiB, cache_size = 10,000 — sane | `config.toml [mempool]` |
| 31 | `enable-profiling = false` on json-rpc (CometBFT pprof is what answered, not the EVM one) | `app.toml [json-rpc]` |
| 32 | Threads (OS) = 224 — moderate; the 34k count is **goroutines**, not threads | `/proc/329272/status: Threads: 224` |

---

## 3. Top-3 hypotheses ranked by likelihood

### #1 — `eth_getLogs` storm serializing on goleveldb's LRU cache mutex (CONFIRMED)

**Confidence:** very high. Direct evidence in the pprof stack (rows 7–9 of the matrix). The two stack frames I quote in rows 7 are visible verbatim in the goroutine profile and together account for 47 % of all live goroutines.

What's happening: the public Caddy endpoint at `testnet.integralayer.com` forwards `eth_getLogs` requests to `localhost:8545`. With `max-open-connections = 0` and no Caddy-side rate limit, the chain accepts unlimited concurrent log queries. Each one hits `PublicFilterAPI.GetLogs → Filter.Logs` and iterates *block by block* across the requested range, calling `Backend.CometBlockResultByNumber → RPCClient.BlockResults → state.dbStore.LoadFinalizeBlockResponse → goleveldb.Get` for every height. The goleveldb cache uses a single mutex (`leveldb/cache/lru.go:85` `Promote`); under N concurrent readers the mutex serializes them, queueing the rest. The queue grows faster than it drains, goroutines pile up, each one holding ~100 KB–1 MB of buffers (request body + bloom + log slice + block result), and the heap balloons.

Why memory keeps climbing across restarts: the load is external and continuous. The 22k-element IRWAWrapper view-call enumeration referenced in `/Users/adamboudj/projects/integra-chain/CLAUDE.md` (testnet `app.toml` adjustment on 2026-05-05) is consistent with this profile — enumerators that iterate addresses typically also call `eth_getLogs` to track events, often with wide block ranges.

### #2 — Slow EndBlock / Propose caused by *the same goleveldb contention*, not by a state-machine bug (CONFIRMED)

**Confidence:** high. The same goleveldb that serves `eth_getLogs` for `state.db` is also read during `BeginBlock`/`EndBlock` (commit results) and CometBFT block validation. When the LRU mutex is contended, ABCI calls share that bottleneck. The signature: chain stays in consensus, votes are clean (matrix row 21), but each block takes 7.5 s instead of 5 s and timestamps lag wall time (rows 19–20). Propose timeouts (row 17) are the wake-up signal — proposer can't gather the block in 3 s because the disk-read side is slow on a contended lock.

This is **not** an `x/vm` or `x/feemarket` EndBlocker bug. The code in those keepers is fast in isolation — but they read the same DB layer that's saturated by the RPC side.

### #3 — Mempool churn from external bots is downstream, not causal (CONFIRMED)

**Confidence:** high. 8,166 `replacement transaction underpriced` errors / hour (row 15) is loud, but `num_unconfirmed_txs = 756` (well under the 5,000 limit) and `module=backend` proves these are RPC-layer rejections, not internal CometBFT mempool errors. Bots are spam-retrying with replacement fees while the chain runs slow; the EVM `txpool` rejects most of the replacements because the bump doesn't beat the price-bump threshold (10 % default in go-ethereum). The mempool is bounded (verified in source: `server/config/config.go:177` — `GlobalSlots=5120`, `GlobalQueue=1024`, `Lifetime=3h`), so this **cannot** be the memory cause. It IS, however, ~136 wasted RPC calls/min adding pressure on top of the `eth_getLogs` load.

### Disconfirmed hypotheses (recorded for completeness)

- **H-A (Pebble bloat):** disconfirmed. Backend is goleveldb, not Pebble; memory is anonymous heap, not file pages (row 2).
- **H-B (goroutine leak in `chainHeadFeed.Subscribe`):** partially disconfirmed. Goroutine accumulation IS present, but the root is RPC reads queueing on the goleveldb mutex, not unbalanced `Subscribe`/`Unsubscribe`. The top stacks (rows 6–7) are not in `event.Feed`.
- **H-F (slow disk):** disconfirmed. r_await ≤ 0.6 ms, %util < 15 % (row 25). Disk is fine.
- **H-G (peer / gossip):** disconfirmed. 3-of-3 validators voting cleanly on the last commit (row 21).
- **EVM-mempool overflow:** disconfirmed by code review (`server/config/config.go:177`) and by `num_unconfirmed_txs = 756`.

---

## 4. Per-hypothesis next-step + patch-shape

### Hypothesis #1 — `eth_getLogs` storm

**Next-step diagnostic** (human operator, ~30 s; SAFE-NOW, read-only):

```bash
ssh -i ~/.ssh/integra root@testnet.integralayer.com '
  echo "--- top eth methods in last 1k requests (Caddy access log) ---"
  tail -1000 /var/log/caddy/access.log 2>/dev/null \
    | grep -oE \"\\\"method\\\":\\\"[a-z_]+\\\"\" \
    | sort | uniq -c | sort -rn | head -10
  echo
  echo "--- live :8545 client IPs ---"
  ss -tan state established \"( sport = :8545 )\" 2>/dev/null \
    | awk \"{print \\\$5}\" | cut -d: -f1 \
    | sort | uniq -c | sort -rn | head -10
'
```

This tells us which method dominates (expect `eth_getLogs` and/or `eth_call`) and which IP is the source — strongly informs the rate-limit policy on Caddy.

**Patch shape — code fix (RPC LAYER, NOT state-machine-breaking):**

Add a small LRU around `Backend.CometBlockResultByNumber` keyed by height. The function currently has no cache; every call is a goleveldb round-trip.

File: `rpc/backend/comet.go` around lines 46–58.

```diff
@@ rpc/backend/comet.go
 package backend
 
 import (
 	"fmt"
+	"sync"
 
 	"github.com/ethereum/go-ethereum/common"
+	lru "github.com/hashicorp/golang-lru/v2"
 	"github.com/pkg/errors"
 
 	cmtrpctypes "github.com/cometbft/cometbft/rpc/core/types"
 
 	rpctypes "github.com/cosmos/evm/rpc/types"
 	"github.com/cosmos/evm/utils"
 )
 
+// blockResultsCache memoizes CometBFT block results by height to avoid
+// hammering state.db on burst eth_getLogs traffic. The lock around
+// goleveldb's LRU cache is a documented contention hotspot when many
+// concurrent readers walk the block-results store. Size is intentionally
+// small (1024) — recent blocks dominate the access pattern and the cost
+// of a miss is a single goleveldb.Get, not a full re-derivation.
+var (
+	blockResultsCache     *lru.Cache[int64, *cmtrpctypes.ResultBlockResults]
+	blockResultsCacheOnce sync.Once
+)
+
+func getBlockResultsCache() *lru.Cache[int64, *cmtrpctypes.ResultBlockResults] {
+	blockResultsCacheOnce.Do(func() {
+		// Error is impossible for a positive size.
+		blockResultsCache, _ = lru.New[int64, *cmtrpctypes.ResultBlockResults](1024)
+	})
+	return blockResultsCache
+}
+
 // CometBlockResultByNumber returns a CometBFT-formatted block result
 // by block number
 func (b *Backend) CometBlockResultByNumber(height *int64) (*cmtrpctypes.ResultBlockResults, error) {
 	if height != nil && *height == 0 {
 		height = nil
 	}
+	if height != nil {
+		if v, ok := getBlockResultsCache().Get(*height); ok {
+			return v, nil
+		}
+	}
 	res, err := b.RPCClient.BlockResults(b.Ctx, height)
 	if err != nil {
 		return nil, fmt.Errorf("failed to fetch block result from CometBFT %d: %w", *height, err)
 	}
+	if height != nil && res != nil {
+		getBlockResultsCache().Add(*height, res)
+	}
 	return res, nil
 }
```

**State-machine impact:** NONE. The function is read-only RPC; its output is the same bytes returned by the underlying client, just cached. Same hash will be returned for the same height. Adding this is a hot-patch level change — safe to ship as a point release without coordinated upgrade.

**Why a tiny (1024-entry) cache works:** `eth_getLogs` workloads cluster on recent blocks (every block-range request the explorer makes hits the most recent N). Even a 1 % hit rate on a contended mutex is huge; in practice the hit rate should be 80–95 %.

**Optional companion patch** (`server/config/config.go`): reduce the *default* `block-range-cap` and `logs-cap` from 10,000 to 1,000 to give operators a sane out-of-the-box ceiling. Not strictly necessary on Integra (we'll override in `app.toml` anyway), but worth landing.

### Hypothesis #2 — Slow Propose from shared goleveldb pressure

**Next-step diagnostic:** if mitigation #1 (rate-limit at Caddy) doesn't bring block time back to 5 s within 10 minutes, run a fresh pprof goroutine profile and confirm the goroutine count dropped below ~2,000 AND the `goleveldb/lru.Promote` stack is no longer in the top-3.

```bash
curl -s http://localhost:6060/debug/pprof/goroutine?debug=1 | head -3
# expect: 'goroutine profile: total <2000'
```

**Patch shape — code fix (NOT state-machine-breaking):**

The longer-term fix here is to move CometBFT's `state.db` off goleveldb onto Pebble (cometbft-db supports it). This is a build-flag change in `integra/cmd/intgd/cmd/creator.go` and a one-time on-disk migration — both are state-machine-NEUTRAL (the bytes are still the same, only the storage engine changes). I'm not drafting the patch here because:

1. It's a multi-step migration that needs its own design doc.
2. The proximate fix in Hypothesis #1 likely removes the urgency.

**State-machine impact:** NONE for the storage-engine swap (it's read/write semantics-equivalent), but **operationally non-trivial** — every validator would need to rebuild state.db once. Park for follow-up.

### Hypothesis #3 — Mempool churn (downstream)

**Next-step diagnostic:** confirm the bots stop retrying after rate-limiting solves the latency problem. The expectation: `replacement transaction underpriced` rate drops by an order of magnitude once block time normalizes.

```bash
ssh -i ~/.ssh/integra root@testnet.integralayer.com \
  'journalctl -u intgd --since "10 minutes ago" | grep -c "replacement transaction underpriced"'
# expect: < 200 (vs ~1360 currently per 10-min window)
```

**Patch shape:** **NONE required.** No code change. The ERRs are not a bug; they are correct rejections of bad client behavior. If a code change *were* warranted (it isn't), it would be a Caddy-side per-IP rate-limit on `eth_sendRawTransaction`.

---

## 5. Recommended mitigations RIGHT NOW

Each command is labeled with blast radius. Read the label before pasting.

> **NOTE (post-intervention):** mitigations **M1** and **M2** below were applied live at 12:38–13:10 UTC on 2026-05-13. The exact form of M1 had to be adapted: the testnet-gateway Caddy build does **not** ship the `caddy-ratelimit` plugin, so the rate-limit directive sketched below was replaced with a `transport http { max_conns_per_host ... }` cap (no plugin needed). See **section 1.5** above for the actual diff, rollback files, and measured results. The text below is kept for reference and for the eventual mainnet equivalent.

### `SAFE-NOW` (no validator change, no restart)

**M1. Add Caddy rate-limit to `eth_getLogs` and `eth_call` on `testnet-gateway`.**
Caddyfile lives at `/etc/caddy/Caddyfile`. The exact directive depends on the Caddy version and which plugin is installed (`caddy-ratelimit` from mholt). Below is a sketch; the operator should adapt to the actual matcher syntax in use:

```caddyfile
# /etc/caddy/Caddyfile snippet (testnet.integralayer.com block)
@evm_logs {
    path /evm
    header Content-Type application/json
    expression {http.request.body} matches "eth_getLogs|eth_call"
}

handle @evm_logs {
    rate_limit {
        zone evm_heavy {
            key {remote_ip}
            events 30
            window 1m
        }
    }
    reverse_proxy localhost:8545
}
```

Apply:
```bash
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```
(`reload`, not `restart` — no dropped connections.)

**M2. Raise systemd MemoryHigh/MemoryMax for headroom WITHOUT restarting intgd.**
A drop-in override file is hot-reloaded by `systemctl daemon-reload`; the cgroup limits update at the next memory accounting tick, no restart of `intgd` required:

```bash
sudo mkdir -p /etc/systemd/system/intgd.service.d
sudo tee /etc/systemd/system/intgd.service.d/memory.conf > /dev/null <<'EOF'
[Service]
MemoryHigh=12G
MemoryMax=14G
EOF
sudo systemctl daemon-reload
# verify (no restart):
systemctl show intgd -p MemoryHigh,MemoryMax
```

Why these numbers: host has 16 G RAM + 4 G swap; 14 G hard cap leaves ~2 G for the kernel + caddy + the explorer. `MemoryHigh=12G` throttles the cgroup BEFORE the kernel OOM-kills, giving the chain a chance to GC instead of dying.

### `NEEDS-RESTART` (single validator down ~30 s — safe with 3-of-3 quorum)

Restarting one of three bonded validators is safe: BFT quorum is 2-of-3, so the chain keeps producing while this node restarts. Slashing window is 10,000 blocks at 5 % min-signed per CLAUDE.md — a 30 s restart is ~6 blocks of missed signing, well under threshold.

**M3. Cap the EVM RPC concurrency and per-request fan-out.**

Edit `/root/.intgd/config/app.toml` `[json-rpc]` section (back it up first):

```toml
[json-rpc]
# was 0 (unlimited) — strangle the storm at the door
max-open-connections = 256

# was 10000 — keep wide queries possible but cap fan-out per request
block-range-cap = 1000
logs-cap = 1000

# was 1000 — batch storms multiply the per-request fan-out
batch-request-limit = 50

# keep filter-cap, gas-cap, evm-timeout AS-IS (the gas-cap=300M and evm-timeout=15s
# were raised on 2026-05-05 for the IRWAWrapper enumeration; reverting them would
# break that legitimate workflow).
```

Apply:
```bash
sudo cp /root/.intgd/config/app.toml /root/.intgd/config/app.toml.bak.$(date +%s)
sudo nano /root/.intgd/config/app.toml   # apply the diff above
sudo systemctl restart intgd
# watch:
journalctl -u intgd -f | grep -E "ERR|Timed out|height="
```

**M4 (optional). Enable the EVM-side pprof for future diagnostics** (currently `enable-profiling = false`). Toggle it on if you want a second pprof endpoint distinct from CometBFT's. Not needed for this fix; CometBFT's pprof at `:6060` already gave us the goroutine profile.

### `NEEDS-GOVERNANCE` (coordinated upgrade)

None of the fixes above touch state machine. Everything is config or RPC-layer code. **No governance proposal is required for this incident.** Logging here only because the plan format calls for it.

---

## 6. Out of scope / unaddressed

- **Caddy access log analysis** to identify the source IPs of the `eth_getLogs` storm. The diagnostic in §4 (Hypothesis #1, "next-step diagnostic") should be run by the operator next; if the load is from internal services (explorer, IRWAWrapper enumeration), the rate-limit policy needs whitelist exceptions.
- **CometBFT `state.db` engine migration** (goleveldb → pebble). Mentioned in §4 H-2 as a longer-term fix; deferred to a follow-up design doc.
- **The 22k-element IRWAWrapper enumeration workload itself** — whether it can be batched into a single `eth_call`/multicall instead of issuing 22k separate calls. That's an application-side optimization, not a chain change.
- **Mainnet exposure.** I did not gather data from `mainnet.integralayer.com`. The mainnet binary v1.0.0 has the same `Backend.CometBlockResultByNumber` codepath (it's in `rpc/backend/comet.go` which is identical between mainnet build commit `0e6a388` and `main`). However mainnet load profile is very different (much less view-call enumeration, public RPC behind different infra). A 1-shot pprof goroutine count on mainnet would tell us if the same pattern is brewing there. **Recommended follow-up:** run §1's gather script against mainnet Gateway (`89.167.88.24`) read-only and compare goroutine counts.
- **The 3 `failed to LoadFinalizeBlockResponse err="could not find results for height #1170920"` errors.** These are old-height misses (heights from earlier in the day). With `pruning="default"` keeping 362,880 states, these heights ARE still pruned-state-eligible — likely the requester is asking for results from before the last pruning sweep. Benign; flagged for completeness.
- **No PR opened.** Per the user's earlier confirmation, only patch-shape goes in the writeup; the operator will decide whether to open the LRU-cache PR.
- **No git branch or commit** drafted. `git status` at end of session shows only this postmortem as new.

---

## Appendix A — Sources reviewed

| Path | Reviewed line range | Purpose |
|------|------|------|
| `rpc/backend/comet.go` | 1–106 (full file) | Confirm no cache on `CometBlockResultByNumber` (the hot function in the pprof stack) |
| `rpc/namespaces/ethereum/eth/filters/filters.go` | 150–250 | Confirm per-block iteration loop at 178–206 |
| `rpc/namespaces/ethereum/eth/filters/api.go` | 200–280 | Confirm `GetLogs` → `Filter.Logs` entry point |
| `mempool/mempool.go` | 92–311 | Confirm `ExperimentalEVMMempool` is bounded (rules out memory overflow there) |
| `mempool/blockchain.go` | 46–222 | Verify `chainHeadFeed` subscription pattern; NOT a leak (goroutine top stacks do not show this path) |
| `server/config/config.go` | 159–187 | Default mempool bounds, RPC caps |
| `x/vm/keeper/abci.go` | 14–54 | EndBlocker hot path (`NotifyNewBlock`) — not directly involved but shares the same DB layer |
| `integra/cmd/intgd/cmd/creator.go` | 40–88 | Pruning/snapshot wiring |
| `/Users/adamboudj/projects/integra-chain/CLAUDE.md` | full | Testnet topology, 2026-05-05 gas-cap raise context |
| `/Users/adamboudj/.claude/projects/.../memory/MEMORY.md` | full | Validator state, mainnet/testnet infra notes |

## Appendix B — Raw evidence files

- Local (this machine): `/tmp/intgd-gather-out-20260513T122754Z.log` (full gather output, 905 lines, 75 KB)
- On host: `/tmp/intgd-postmortem-20260513T122754Z.log`, `/tmp/intgd-journal-20260513T122757Z.log`

## Appendix C — Validator identity

Helsinki signer address (this host): `E52BA176B57A836EA710381C1C95B7DBDEF6B2C1` (consensus pubkey `mkCun/o5hNRAv2AROuOdl3xP9KhQr9GMXol6Fk7wZQ4=`), operator `integravaloper1wry6d9njdpacwnj2mpt82wwln7hcagy9hwue3t`, voting power 200,232,886. Confirmed bonded.
