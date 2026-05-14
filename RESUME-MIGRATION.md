# Resume prompt — Integra testnet explorer migration POST-CUTOVER follow-ups

The 2026-05-14 migration is **DONE** (Phases 1–8). DNS cut over, real Let's
Encrypt cert live, OLD explorer stopped with volumes preserved, throttle
autoscaler memory-metric bug fixed, indexer caught up to chain tip.

After `/clear`, run with `/goal` pointing at this file. The prompt below
covers the **remaining follow-ups** — one real open issue (removeStalledBlock
backlog) plus the standing hardening items.

---

```
GOAL: Finish the post-cutover follow-ups for the 2026-05-14 Integra testnet
explorer migration. The migration + cutover are DONE and verified. This is
the cleanup/hardening phase plus ONE real open investigation.

CONTEXT YOU MUST LOAD FIRST:
1. /Users/adamboudj/projects/integra-chain/CLAUDE.md
   — read the whole file, especially the "Testnet block explorer (Ethernal)"
   section which describes the post-migration state.
2. /Users/adamboudj/projects/integra-chain/docs/findings/2026-05-14-explorer-migration-config-audit.md
   — the full OLD-vs-NEW config audit.
3. ~/.claude/projects/-Users-adamboudj-projects-integra-chain/memory/MEMORY.md
   and especially memory/project_explorer_migration_2026-05-14.md.

WHAT IS ALREADY DONE (do NOT redo):
- Explorer migrated OFF testnet-gateway (46.225.231.81) ONTO the dedicated
  box 91.99.208.48 (Hetzner CCX23 Falkenstein). Real LE cert through
  2026-08-12. Both testnet.explorer.integralayer.com and
  admin.testnet.explorer.integralayer.com serve HTTP/2 200 via real DNS.
- OLD explorer is `docker compose stop`'d on testnet-gateway, volumes
  preserved for rollback (window expires 2026-06-15).
- intgd validator PID 329272 on testnet-gateway untouched throughout.
- Migration-restore regressions fixed: token_transfer_events.isReward
  column re-added + 2.1M rows backfilled; 4 event-hypertable indexes
  re-created; ALTER DATABASE ethernal statement_timeout=90000; ANALYZE on
  all rebuilt tables.
- Throttle autoscaler (intgd-throttle.service on testnet-gateway) had a
  memory-metric bug: fetch_intgd_memory_gb() read cgroup MemoryCurrent
  which counts ~5.7GB of reclaimable page cache, pinning the autoscaler
  in PANIC permanently (cap=8) even though intgd's real RSS was ~7GB.
  FIXED: rewrote it to read intgd VmRSS from /proc/<MainPID>/status.
  State reset to NORMAL, Caddyfile cap reset to 64. Backup at
  /usr/local/bin/intgd-throttle.py.bak.pre-memfix.*
- After the throttle fix the indexer caught up fast: gap closed from
  ~838 to ~2 blocks. The "Chain may be stalled" banner is cleared
  (latest block age ~9s, banner threshold is 300s).
- intgd-throttle EXPECTED_OCCURRENCES was patched 4->2 during decomm
  (explorer Caddy blocks removed -> only 2 max_conns_per_host lines left).
- Worker concurrency: HIGH=15 / MEDIUM=10 are the AUTHORITATIVE values,
  hard-coded in docker-compose.integra.yml (INT-589 set them, INT-591
  hard-coded them to stop stale .env values overriding). The
  .env.integra HIGH/MEDIUM_WORKER_CONCURRENCY=5 entries are DEAD CONFIG
  (overridden) — leave them at 5, do NOT "fix" them.

CURRENT STATE AT HANDOFF (2026-05-14 ~15:05 UTC):
- Explorer fully operational on 91.99.208.48. Indexer at chain tip.
- NEW box load avg ~20, postgres ~370% CPU — this is the worker pool
  draining backlogs; it is NOT user-visible breakage. Expected to settle.
- ONE REAL OPEN ISSUE: the `removeStalledBlock` BullMQ queue has a
  backlog of ~6,800 jobs in `bull:removeStalledBlock:wait` and it is
  slowly GROWING (~+25/min), not draining. See PHASE A.

EXECUTE IN THIS ORDER:

PHASE A — investigate + fix the removeStalledBlock backlog (the one real
open issue):
A.1 Characterise it. On 91.99.208.48:
    docker exec integra-explorer-redis redis-cli LLEN bull:removeStalledBlock:wait
    docker exec integra-explorer-redis redis-cli LLEN bull:removeStalledBlock:active
    docker exec integra-explorer-redis redis-cli ZCARD bull:removeStalledBlock:delayed
    docker exec integra-explorer-redis redis-cli ZCARD bull:removeStalledBlock:failed
    Sample a failed job to see the actual error:
    docker exec integra-explorer-redis redis-cli LRANGE bull:removeStalledBlock:failed 0 5
    (then HGETALL one of the bull:removeStalledBlock:<id> hashes for failedReason)
A.2 Known facts from the last session:
    - Every block's afterCreate() hook (models/block.js ~line 142)
      enqueues ONE removeStalledBlock job with a 5-min delay
      (delay:300000, attempts:10, exponential backoff, timeout:30000).
    - The job (jobs/removeStalledBlock.js) does
      Block.findByPk(blockId, {include:['transactions']}), checks
      block.transactions for any with state==='syncing' (isSyncing is a
      VIRTUAL column = state==='syncing', NOT a missing DB column —
      that theory was checked and ruled out), and revertIfPartial()s
      the block if so, else returns true.
    - removeStalledBlock is a LOW-priority job; lowPriority.js gives
      EACH job type its own BullMQ Worker at concurrency:10.
    - completed counter showed 10 (trimmed by removeOnComplete:10),
      failed showed 46. The :wait list grows ~25/min.
    The hypothesis to confirm or kill: jobs are failing (the
    Block.findByPk include or the revertIfPartial path throws),
    retrying up to 10x with exponential backoff (hence :delayed also
    growing), and never draining. OR the job is just slow because each
    one loads all of a block's transactions and the low worker can't
    keep up. Get the actual failedReason FIRST, then decide.
A.3 If it's a job-level error: fix the root cause (could be another
    schema/restore artifact, could be a genuine bug). If the jobs are
    fundamentally fine but just backlogged, the cleanest one-time
    drain is to let them run with more headroom — but DO NOT just bump
    concurrency blindly; the box is 4-core and postgres is already
    ~370%. Consider: is the 5-min-delayed per-block enqueue even
    needed on a healthy chain? This job exists to catch blocks stuck
    mid-sync; if the indexer is healthy almost every job is a no-op
    returning true. A pre-existing one-time backlog can be drained by
    temporarily pausing NEW enqueues or by clearing the queue if the
    jobs are confirmed no-ops:
      docker exec integra-explorer-redis redis-cli DEL bull:removeStalledBlock:wait
    — but ONLY after confirming via A.1/A.2 that the waiting jobs are
    genuinely redundant no-ops (they check already-synced blocks).
    Removing genuine stalled-block-cleanup work would be a mistake.
A.4 This backlog is PRE-EXISTING (it was already ~6,084 before the
    last session touched anything — it predates the migration). It is
    NOT causing user-visible breakage: the explorer works, the indexer
    is at tip, the banner is cleared. So it is important but not an
    emergency. Investigate properly; don't rush a destructive fix.

PHASE B — confirm steady state (quick):
B.1 ssh root@91.99.208.48 'uptime' — load should settle toward <8 once
    backlogs drain. If it stays pinned at 20+ for hours, dig into what
    the postgres backends are doing (pg_stat_activity).
B.2 ssh root@46.225.231.81 'journalctl -u intgd-throttle.service
    --since "10 min ago" | grep poll | tail -5' — confirm the
    autoscaler stays NORMAL/cap=64 (memory_gb should read ~7, not ~12;
    if it reads ~12 again the VmRSS fix regressed).
B.3 curl -sI https://testnet.explorer.integralayer.com/ — expect 200,
    real LE cert.

PHASE C — outstanding hardening (no time pressure, in order):
C.1 OOMScoreAdjust=-900 on intgd.service, all 3 testnet validators
    (46.225.231.81, 45.77.139.208, 159.223.206.94):
    for IP in 46.225.231.81 45.77.139.208 159.223.206.94; do
      ssh root@$IP 'mkdir -p /etc/systemd/system/intgd.service.d &&
        printf "[Service]\nOOMScoreAdjust=-900\n" > /etc/systemd/system/intgd.service.d/oom.conf &&
        systemctl daemon-reload &&
        systemctl show intgd.service -p OOMScoreAdjust'
    done
C.2 8 GB swap on signer-2 (159.223.206.94 — currently 0 swap):
    ssh root@159.223.206.94 'fallocate -l 8G /swapfile && chmod 600 /swapfile &&
      mkswap /swapfile && swapon /swapfile &&
      grep -q /swapfile /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab &&
      free -h'
C.3 Reclaim disk on testnet-gateway:
    ssh root@46.225.231.81 'df -h /; docker builder prune -af; docker image prune -af; df -h /'
C.4 Upstream the hasReachedTransactionQuota stub
    (/opt/integra-explorer/run/models/explorer.js on 91.99.208.48,
    backup explorer.js.bak.pre-quota-stub) — open a PR.
C.5 Remove the dark testnet.blockscout.integralayer.com Caddy block on
    testnet-gateway (backup the Caddyfile first; its backend has been
    502'ing for weeks).
C.6 Fix the 3 stock-Ethernal Docker healthchecks flagged "unhealthy"
    (backend, frontend, soketi) — the healthcheck commands assume a
    pm2 version that doesn't match. Either fix the command or drop the
    healthcheck block in docker-compose.integra.yml on 91.99.208.48.

PHASE D — plan only (do NOT execute):
D.1 Write a migration plan for moving the public RPC origin
    (testnet.integralayer.com /{rpc,api,evm,faucet}) OFF testnet-gateway
    onto its own box, same pattern as the explorer move. This is the
    structural fix that ends the validator+RPC co-location risk that
    caused both the 2026-05-13 OOM and the 2026-05-14 explorer
    migration. Save to docs/plans/2026-rpc-origin-migration.md for
    operator review. Don't execute.

PHASE E — calendar (nothing to do until 2026-06-15):
E.1 On/after 2026-06-15 the OLD explorer rollback window closes. Then:
    ssh root@46.225.231.81 'cd /opt/integra-explorer && docker compose
      -f docker/docker-compose.integra.yml --env-file docker/.env.integra down'
    (NO -v yet) then a deliberate second step:
    ssh root@46.225.231.81 'docker volume rm docker_pgdata docker_redisdata'
    then rm -rf /opt/integra-explorer and clean the commented-out
    #PRE-DECOMM-2026-05-14 cron lines from root's crontab.

NON-NEGOTIABLES:
- Do NOT override the intgd-throttle autoscaler manually. If it shows
  PANIC again, check that fetch_intgd_memory_gb() is still reading
  VmRSS (the 2026-05-14 fix) — a regression there would re-break it.
- Do NOT `docker compose down -v` on either box. Identical volume
  names (docker_pgdata, docker_redisdata) on both — wrong-box down -v
  is unrecoverable. Both compose files carry banner warnings.
- Do NOT change docker-compose HIGH/MEDIUM_WORKER_CONCURRENCY (15/10)
  or "fix" the dead .env values (5) — that's INT-589/591 settled.
- Do NOT change intgd-throttle EXPECTED_OCCURRENCES back to 4.
- Do NOT touch DNS, validators, intgd.service, or consensus config
  without explicit operator confirmation.
- For PHASE A: get the actual failedReason before any destructive
  queue operation. A redis DEL on a queue of genuine work is a data-
  integrity mistake.

SUCCESS CRITERIA:
- Phase A: removeStalledBlock backlog root cause identified AND either
  fixed or the queue confirmed-safe-to-drain and drained. :wait should
  be stable/shrinking, not growing.
- Phase B: load settling, throttle NORMAL, explorer 200.
- Phase C: done or explicitly deferred with operator OK.
- Phase D: plan written, not executed.
- Phase E: nothing until 2026-06-15.
When all phases are green or deferred, surface a brief status and stop.
```

---

## Quick instructions for the operator

After `/clear`:

1. Run: `/goal Read /Users/adamboudj/projects/integra-chain/RESUME-MIGRATION.md and execute the prompt inside (Phases A through E in order, respecting the non-negotiables).`
2. The new session reads CLAUDE.md + the audit doc + memory, then starts at
   Phase A (the removeStalledBlock backlog investigation — the one real
   open issue).
3. Everything else (the migration itself, the cutover, the throttle fix,
   the indexer catch-up) is already done and verified.
