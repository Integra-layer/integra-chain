# 2026-05-29 — Gateway IAVL pruning (deferred fix) + 4-server process audit

> **RESOLVED 2026-05-30 — clean-store resync executed.** The gateway was resynced to a clean compacted store
> copied from signer-2 (consistent snapshot via a brief `systemctl stop intgd` + `cp -a`, transferred over an
> ephemeral SSH key, staged into `data.new` while the gateway kept running). In a short downtime window the
> gateway was stopped, its OWN `priv_validator_key.json`/`node_key.json`/`priv_validator_state.json` were
> preserved (the snapshot's `data/priv_validator_state.json` was overwritten with the gateway's own → no
> double-sign), the data dir was swapped, `pruning` set `"nothing"→"default"`, and intgd restarted. It
> blocksynced ~520 blocks (~48s), resumed signing, and the chain never halted. **Result:** `~/.intgd/data`
> **88G→30G**, `application.db` 55G→21G, `version does not exist` spam **0/min** under `pruning="default"` on
> the compacted store (so the runtime pruning routine works fine on a clean store — the bloat itself was the
> problem, not the config). Binary parity (sha256) was verified between signer-2 and the gateway beforehand.
> `data.old.*` was removed after the node was confirmed healthy. The gateway is no longer archive.

## A. Gateway IAVL bloat / pruning spam — REAL cause found (goal assumption was wrong)
The goal expected `snapshot-interval=0` to "kill the per-block 'pruning version does not exist' spam +
the IAVL bloat". **Verified false:** after setting `snapshot-interval=0` and restarting, the gateway
still logs `ERR Error while pruning err="version does not exist" module=server` ~60×/min.

**Real cause:** the gateway's IAVL pruning is broken — it fails every cycle, so old versions are never
deleted and `application.db` keeps all history.
- Evidence: all 3 validators have IDENTICAL pruning config (`pruning="default"`, keep-recent/interval 0,
  min-retain-blocks 0), but only the gateway spams (60/min vs 0 on both signers) and only the gateway's
  store is bloated: `application.db`≈54G, total `~/.intgd/data`≈87G — vs signers ≈18G app.db / ≈29-30G total.
- Not urgent: gateway disk is 155G/301G used (134G free) and the store is stable (not rapidly growing).
  It is non-fatal log noise + slow disk growth, NOT the instability cause, and NOT a config drift.

**UPDATE 2026-05-29 17:16Z — offline `intgd prune default` ATTEMPTED, verified INEFFECTIVE:** ran on
the stopped gateway, completed in ~56s ("successfully pruned the application root multi stores"),
gateway rejoined safely (missed only ~20 blocks, no jail). BUT: app.db stayed **54G** (zero change) and
the `version does not exist` spam **persists at 60/min**. Conclusion: the store is **NOT version-bloated**
(nothing to prune) — the 54G is **un-compacted goleveldb** file bloat (the gateway is the heavy public-RPC
node → SST write-churn not reclaimed; signers hold the SAME consensus state in ~18G compacted). The spam
is **benign runtime log-noise** (pruning manager retrying already-absent versions — a known SDK artifact,
likely from a past state-sync). The node is fully healthy; disk is fine (134G free). A plain prune cannot
fix either. The real fix is a **clean-store resync** (below) — heavier; deferred as it is cosmetic on a
healthy node with ample disk. So success-criterion "#6 pruning spam = 0" stays UNMET by design.

**Real fix (DEFERRED — clean-store resync, needs a maintenance window):** state-sync is unavailable (no
node serves snapshots: snapshot-interval=0 everywhere), so options are: (a) copy a compacted signer's FULL
`~/.intgd/data` to the gateway (keep the gateway's own `priv_validator_key.json`/`node_key.json`/
`priv_validator_state.json`; ~30G copy; gateway down for the copy) — gives a clean compacted store; or
(b) full resync from genesis (hours). Either eliminates the bloat AND the spam. Not worth the
gateway-downtime risk for benign log-noise now.

**Superseded plan (kept for reference — the offline prune above did NOT work):**
```
# Follow the validator restart safety protocol. Precondition: all 4 signing + omeljan up
# (python3 /root/integra-restart-check.py 20 => OMELJAN_FULLY_SIGNING=YES, every line SAFE).
systemctl stop intgd                       # gateway leaves consensus (online ~450M > 2/3=434M IF omeljan stays up)
cp -a ~/.intgd/data/priv_validator_state.json /root/pvs.bak.$(date +%s)   # safety
time intgd prune default --home /root/.intgd      # offline prune to last 362880 states (goleveldb). ~10-40 min on 54G.
systemctl start intgd                      # recover: catching_up=false, resumes signing
```
- RISK: the gateway is offline for the whole prune (~10-40 min) — a long omeljan-dependency window. If
  omeljan drops during it, the chain halts. Only run when omeljan is rock-solid; monitor from a signer.
  If prune fails/corrupts, a resync (hours) may be needed — have a recent snapshot ready.
- Alternative (lower-risk, also downtime): rsync a freshly-pruned signer's `~/.intgd/data` onto the
  gateway (stop intgd, swap data keeping the gateway's own priv_validator_*/node_key, start). Avoids the
  in-place prune risk but copies ~30G.
- After fix: `journalctl -u intgd --since '5 min ago' | grep -c 'version does not exist'` == 0; data store ≈30G.

## B. 4-server process audit (parallel read-only agents) — RESULT: no compromise
Every running service, container, timer, cron, and listener on all 4 boxes was enumerated and
justified. **No miners, no rogue listeners, no backdoors, no unauthorized SSH keys, no live mainnet
anything, no unexpected outbound daemons. No interactive intruders (only the documented team keys
pg@/adam@integralayer.com).** Top CPU/mem everywhere is the expected stack (intgd/caddy/crowdsec;
Ethernal workers/postgres on the explorer).

### Fixed this run (verified)
- **logrotate.service FAILED on ALL 4** (stray `/etc/logrotate.d/rsyslog.bak.*` + a redundant soak
  `00-syslog-sizecap`, both re-declaring /var/log/syslog → logrotate aborted → logs not rotating).
  Removed both (→ `/root/decommissioned-configs/`); stock `rsyslog` (maxsize 500M daily) now rotates.
  All 4 hosts: logrotate Result=success, 0 failed units.
- **Dead `intgd-mainnet.service`** unit files on BOTH signers (disabled+inactive, no `/root/.intgd-mainnet`,
  no mainnet listeners) — removed (→ decommissioned-configs) + daemon-reload. Reality now matches "mainnet is dead".
- **Explorer `.env.integra` (+ backups)** 0644→0600 (held TELEGRAM_BOT_TOKEN + DB_PASSWORD).
- **Explorer `/root/.integra-stress.env`** (plaintext TEST_WALLET_PK, testnet throwaway) → 0600.

### Flagged — deferred / needs-credentials / for operator decision
- **Telegram bot token** present on all boxes (0600, root) and disclosed in audit transcripts → rotate
  via @BotFather (needs-credentials).
- **Stale migration dumps**: gateway /root ~7.8G (`ethernal.dump` etc.), explorer /opt ~13G
  (`ethernal.dump`+`.truncated`) → delete AFTER the 2026-06-15 rollback window.
- **Gateway idle docker+containerd+pm2-root** (pre-migration leftovers, nothing running) → disable after
  2026-06-15 (disk-guard.sh has a soft dep on `docker builder prune`).
- **signer-1 status page** binds `0.0.0.0:3003` (ufw-blocked; should be `127.0.0.1`) and
  **`integra-status-autopull.sh`** auto-deploys `origin/main` as ROOT every 2 min on a ~200M validator
  → supply-chain risk; recommend pinning/removing or moving the status page off the validator.
- **`allow-insecure-unlock=true`** on signers — harmless today (no `personal` namespace in `api`), note only.
- **signer-1 `/opt/integra-chain`** full source checkout + assorted `.bak` files → cleanup candidates.

## RESOLVED 2026-05-29 ~18:10Z — pruning spam = 0 via gateway `pruning="nothing"`
Per user go-ahead, set gateway `[base] pruning="nothing"` (archive mode) + restart (via the safety
protocol; missed ~2 blocks, recovered, omeljan signing throughout). `version does not exist` spam → **0/min**
(criterion #6 met). The runtime pruning routine — not a prune backlog — was the cause; stopping it stops the
spam. Gateway now keeps full history (fine for a public RPC node). The 54G un-compacted goleveldb is NOT
reclaimed (grows gradually; disk fine at 134G free, disk-guard monitors) — an OPTIONAL clean-store resync
reclaims it later. Reversible (`pruning="default"` + restart). Repo baseline `infra/validators/gateway/app.toml`
updated (drift check green).
