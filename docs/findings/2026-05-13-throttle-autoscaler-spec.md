# Caddy throttle autoscaler — design spec

**Status:** spec, not implemented
**Author:** drafted with Claude after 2026-05-13 testnet validator postmortem
**Decisions locked** (2026-05-13):
- **Level 2** — 5-state thermostat in Python, run as systemd unit on testnet-gateway
- **Mechanism** — sed + `systemctl reload caddy` (file is source of truth, audit-friendly)
- **Scope** — testnet-gateway only for v1. Mainnet (89.167.88.24) is a future port once v1 has run ≥ 1 week clean.

## Problem statement

The 2026-05-13 incident (see `validator-postmortem-2026-05-13.md`) was triaged manually by tightening `max_conns_per_host` on Caddy reverse_proxy /evm blocks (64 → 16) when an `eth_getLogs` storm piled up 34k+ goroutines blocked on goleveldb's LRU mutex. After 50 minutes of triage, the chain recovered. The whole intervention worked but **required a human operator at the console**.

We want a daemon that does the same loop automatically: detect pile-up, tighten Caddy, watch drain, loosen Caddy. With **hysteresis** so it doesn't oscillate, and **safety bounds** so it never strangles the chain or runs wide-open.

## High-level architecture

```
┌──────────────────────┐
│ intgd-throttle.py    │  systemd unit on testnet-gateway
│ (Python daemon, 30s  │
│  poll loop)          │
└──────────┬───────────┘
           │
           │ reads
           ├─→ http://localhost:6060/debug/pprof/goroutine?debug=1  (count)
           ├─→ http://localhost:26657/status                         (block_time → lag)
           ├─→ systemctl show intgd -p MemoryCurrent                 (heap pressure)
           │
           │ writes (only on state transition)
           ├─→ /etc/caddy/Caddyfile  (sed replace max_conns_per_host)
           ├─→ systemctl reload caddy
           │
           │ persists
           ├─→ /var/lib/intgd-throttle/state.json  (current state + last-transition timestamp)
           └─→ /var/log/intgd-throttle.log         (JSON-lines, one entry per poll)
```

## Thermostat states

Five states from PANIC to COOL. Each state binds a `max_conns_per_host` value applied to all 4 `reverse_proxy localhost:8545` blocks in `/etc/caddy/Caddyfile`.

| State | Goroutines | Block lag | max_conns_per_host |
|------|------|------|------|
| `PANIC`  | > 30 000 | > 300 s | 8 |
| `HOT`    | > 15 000 | > 60 s  | 16 |
| `WARM`   | > 5 000  | > 20 s  | 32 |
| `NORMAL` | ≥ 2 000 OR lag ≥ 5 s (default) | — | 64 |
| `COOL`   | < 2 000 AND lag < 5 s | < 5 s | 128 |

**Selection rule (per poll):** start at `COOL` and walk down the table; first row where EITHER threshold is hit is the **observed** state. Then apply transition rules below.

## Transition rules (hysteresis)

The observed state per-poll is NOT applied directly. We apply state changes through these gates:

1. **DOWN transitions (tighter, lower max_conns)** — apply aggressively:
   - Observed state is colder (lower number) than current → apply after **2 consecutive polls** at the colder state (= 60 s of confirmation).
   - PANIC → apply immediately (single poll, no confirmation) — the chain is in distress, no time to wait.

2. **UP transitions (looser, higher max_conns)** — apply slowly:
   - Observed state is warmer (higher number) than current → require **10 consecutive polls** at the warmer state (= 5 min of stable health) **AND** require we have been in the current state for at least **5 min** already.
   - Step up by one state at a time. Never jump COOL → NORMAL directly; must traverse states.

3. **Hard bounds:**
   - `max_conns_per_host` never set below `8` (PANIC) or above `256` (manual emergency only).
   - Daemon never sets a value not in the lookup table → no accidental syntax variants.

4. **Failure modes:**
   - pprof unreachable (curl timeout/non-200) → **freeze state**, log warning, skip this poll.
   - `/status` unreachable → same, freeze.
   - `caddy validate` fails after writing the new Caddyfile → **rollback to last-known-good** (we keep a copy in `/var/lib/intgd-throttle/last-good-Caddyfile`), don't reload Caddy.
   - `systemctl reload caddy` returns non-zero → rollback to last-good and re-reload.

## Polling loop (pseudocode)

```python
POLL_INTERVAL = 30  # seconds
STATE_FILE = "/var/lib/intgd-throttle/state.json"
LOG_FILE = "/var/log/intgd-throttle.log"
CADDYFILE = "/etc/caddy/Caddyfile"
LAST_GOOD = "/var/lib/intgd-throttle/last-good-Caddyfile"

STATES = [
    # name,    goroutine_thr,  lag_thr_s,  max_conns
    ("PANIC",  30_000, 300, 8),
    ("HOT",    15_000, 60,  16),
    ("WARM",   5_000,  20,  32),
    ("NORMAL", 2_000,  5,   64),
    ("COOL",   0,      0,   128),  # COOL = below all thresholds
]

def observe():
    goroutines = fetch_pprof()         # int; raises on failure
    block_lag  = fetch_lag()           # int seconds; raises on failure
    memory_gb  = fetch_memory()        # float; raises on failure
    return goroutines, block_lag, memory_gb

def classify(goroutines, block_lag):
    for name, g_thr, l_thr, _ in STATES:
        if name == "COOL":
            return "COOL"
        if goroutines > g_thr or block_lag > l_thr:
            return name
    return "COOL"

def main_loop():
    state = load_state(STATE_FILE)  # dict: current, since, observed_streak
    while True:
        try:
            g, l, m = observe()
        except Exception as e:
            log({"event": "observe_failed", "error": str(e)})
            sleep(POLL_INTERVAL); continue

        observed = classify(g, l)
        log({"event": "poll", "goroutines": g, "lag_s": l, "mem_gb": m,
             "current": state["current"], "observed": observed})

        if observed == state["current"]:
            state["observed_streak"] = 0
            save_state(state); sleep(POLL_INTERVAL); continue

        observed_idx = idx_of(observed)
        current_idx  = idx_of(state["current"])

        if observed == "PANIC":
            # immediate
            apply_transition(state, "PANIC", reason="panic_immediate")
        elif observed_idx < current_idx:
            # colder than current (tighter); 2 polls confirmation
            state["observed_streak"] += 1
            if state["observed_streak"] >= 2:
                apply_transition(state, observed, reason="cooling_confirmed")
        elif observed_idx > current_idx:
            # warmer than current (looser); 10 polls confirmation + 5 min in current
            if time_in_state(state) < 300:
                # too soon to step up; reset streak
                state["observed_streak"] = 0
            else:
                state["observed_streak"] += 1
                if state["observed_streak"] >= 10:
                    next_state_name = STATES[current_idx + 1][0]  # step by one
                    apply_transition(state, next_state_name, reason="warming_confirmed")

        save_state(state)
        sleep(POLL_INTERVAL)

def apply_transition(state, new_name, reason):
    new_cap = max_conns_for(new_name)
    log({"event": "transition_start", "from": state["current"], "to": new_name,
         "new_cap": new_cap, "reason": reason})
    backup_caddyfile(LAST_GOOD)
    new_content = caddyfile_with_cap(CADDYFILE, new_cap)
    write_atomic(CADDYFILE + ".new", new_content)
    if not caddy_validate(CADDYFILE + ".new"):
        os.unlink(CADDYFILE + ".new")
        log({"event": "transition_rollback", "reason": "validate_failed"})
        return
    os.replace(CADDYFILE + ".new", CADDYFILE)
    if not caddy_reload():
        # rollback
        shutil.copy(LAST_GOOD, CADDYFILE)
        caddy_reload()
        log({"event": "transition_rollback", "reason": "reload_failed"})
        return
    state["current"] = new_name
    state["since"] = now()
    state["observed_streak"] = 0
    log({"event": "transition_done", "to": new_name, "new_cap": new_cap})
```

## Caddyfile mutation

The daemon does NOT regenerate the Caddyfile from a template — it does a **strict sed-equivalent** on the existing file:

```python
def caddyfile_with_cap(path, new_cap):
    """Replaces every 'max_conns_per_host N' line with 'max_conns_per_host <new_cap>'.
    Validates that the count of replacements matches the expected 4 occurrences (one per
    /evm reverse_proxy block). Aborts on mismatch — better to freeze than to corrupt."""
    with open(path) as f:
        content = f.read()
    import re
    pattern = re.compile(r'(max_conns_per_host)\s+\d+')
    new_content, n = pattern.subn(rf'\1 {new_cap}', content)
    if n != 4:
        raise RuntimeError(f"expected 4 max_conns_per_host occurrences, found {n}")
    return new_content
```

If the count ever drifts from 4 (someone added/removed a block manually), the daemon freezes and logs an error — operator notified via journald.

## State file format

`/var/lib/intgd-throttle/state.json`:

```json
{
  "current": "WARM",
  "since": 1778677570,
  "observed_streak": 0,
  "version": 1
}
```

Read on daemon start, written after every poll. Survives daemon restart cleanly.

## Logging

`/var/log/intgd-throttle.log` — JSON Lines, one entry per poll + per transition. Example:

```
{"ts": "2026-05-13T14:00:30Z", "event": "poll", "goroutines": 24826, "lag_s": 25, "mem_gb": 10.82, "current": "WARM", "observed": "NORMAL"}
{"ts": "2026-05-13T14:01:00Z", "event": "poll", "goroutines": 21100, "lag_s": 15, "mem_gb": 10.5, "current": "WARM", "observed": "NORMAL"}
...
{"ts": "2026-05-13T14:06:00Z", "event": "transition_start", "from": "WARM", "to": "NORMAL", "new_cap": 64, "reason": "warming_confirmed"}
{"ts": "2026-05-13T14:06:00Z", "event": "transition_done", "to": "NORMAL", "new_cap": 64}
```

Logrotate config: 7-day retention, daily rotation, gzip.

## Metrics surface (optional, for future Prometheus integration)

Write `/var/lib/intgd-throttle/metrics.prom` after every poll:

```
# HELP intgd_throttle_goroutines Live goroutine count from intgd pprof
# TYPE intgd_throttle_goroutines gauge
intgd_throttle_goroutines 24826

# HELP intgd_throttle_block_lag_seconds Time delta between wall and latest block_time
# TYPE intgd_throttle_block_lag_seconds gauge
intgd_throttle_block_lag_seconds 25

# HELP intgd_throttle_max_conns The current max_conns_per_host applied to Caddy
# TYPE intgd_throttle_max_conns gauge
intgd_throttle_max_conns 32

# HELP intgd_throttle_state_idx Current thermostat state (0=PANIC ... 4=COOL)
# TYPE intgd_throttle_state_idx gauge
intgd_throttle_state_idx 2
```

A future node_exporter `textfile collector` can pick this up. No need now.

## systemd unit

`/etc/systemd/system/intgd-throttle.service`:

```ini
[Unit]
Description=Caddy throttle autoscaler for Integra testnet
After=intgd.service caddy.service
Wants=intgd.service caddy.service

[Service]
Type=simple
ExecStart=/usr/local/bin/intgd-throttle.py
Restart=always
RestartSec=10s

# Run as root because we need to write /etc/caddy/Caddyfile and call systemctl reload.
# Acceptable here because the daemon is small and audited; if we want to harden,
# create a dedicated user with sudoers entries for `systemctl reload caddy` only
# and `chown` of /etc/caddy/Caddyfile.
User=root

# Safety: limit resource usage so the autoscaler can never starve the host.
MemoryMax=200M
TasksMax=20
CPUQuota=10%

# Logging to journald (which logrotate handles separately).
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

## Kill switch

To disable the autoscaler at any time:

```bash
systemctl stop intgd-throttle    # freezes at current state; Caddyfile unchanged
systemctl disable intgd-throttle # survives reboot
```

To manually override while daemon is running, the operator can `sed -i 's/max_conns_per_host X/max_conns_per_host Y/g' /etc/caddy/Caddyfile && systemctl reload caddy` — the daemon will see the new value on its next poll, NOT revert it (because it reads only goroutine + lag, not the file), and will treat that as the new floor until thresholds dictate otherwise. So manual overrides survive at least one poll cycle.

To make a manual override permanent: also `systemctl stop intgd-throttle`.

## Test plan (before enabling on testnet)

1. **Unit tests** for `classify()`, `caddyfile_with_cap()`, transition gating logic. No SSH needed.
2. **Local dry-run mode** (`--dry-run` flag): observe + classify + log, but never call `caddy reload` or write Caddyfile. Run for 1 hour locally pointing at testnet, verify the state transitions match the actual incident pattern from 2026-05-13.
3. **Shadow run on testnet-gateway**: copy `Caddyfile` to `/tmp/Caddyfile.shadow`, run the daemon pointing CADDYFILE=/tmp/Caddyfile.shadow with a no-op `caddy_reload`. Observe for 24 h. Verify it would have made sensible transitions through normal day/night cycle.
4. **Stage with permissive bounds**: deploy with `max_conns_per_host` bounds tightened to {32, 48, 64, 96, 128, 192} (less aggressive). Run 48 h with the daemon AUTHORIZED to mutate Caddyfile. Confirm no oscillation.
5. **Production bounds**: switch to the {8, 16, 32, 64, 128} table.

## Open questions for next session

1. **Memory pressure as a 4th input?** Current design uses only goroutines + lag. Memory is observed but unused. Could add `MemoryCurrent > 11.5G → force PANIC` as a safety net. Yes/no?
2. **What about `tx_index.db` size growth?** Out of scope — that's a separate config issue (`tx_index = "kv"` in config.toml indexes everything). Could be a separate alert.
3. **Should the daemon also adjust `app.toml` `[json-rpc] max-open-connections`?** No for v1 — that requires intgd restart. Caddy-only fix in v1.
4. **Per-handler different caps?** Could give `/evm/*` (heavy) a tighter cap than `/rpc/*` (cheap). Not needed for v1, all 4 `localhost:8545` blocks share the cap.
5. **Notification on transition?** Telegram webhook on every transition? Or just on PANIC/HOT entry? Right now → silent. Recommended: ping `@adamboudj` on PANIC entry only.

## Files to create when implementing

| Path | Purpose |
|------|------|
| `/usr/local/bin/intgd-throttle.py` | the daemon (~300 lines) |
| `/etc/systemd/system/intgd-throttle.service` | systemd unit |
| `/var/lib/intgd-throttle/state.json` | persistent state |
| `/var/lib/intgd-throttle/last-good-Caddyfile` | rollback copy |
| `/var/log/intgd-throttle.log` | structured logs |
| `/etc/logrotate.d/intgd-throttle` | logrotate config |
| `docs/findings/2026-05-13-throttle-autoscaler-spec.md` | this file ✓ |
| `docs/findings/2026-05-13-throttle-autoscaler-readme.md` | operator runbook (to draft) |

## Why this is the right design (recap)

- **Hysteresis** prevents oscillation under sustained load
- **Aggressive tightening + slow loosening** matches the asymmetry of the problem (storms appear fast, drain slow)
- **PANIC immediate-action** preserves chain liveness even if the operator is asleep
- **Hard bounds** (8 ≤ N ≤ 256) prevent runaway misconfiguration
- **Freeze-on-error** is safer than guess-on-error — if pprof is down, we don't make blind decisions
- **Validate-before-reload** prevents typo-caused outages
- **Source-of-truth is the Caddyfile** (not a daemon-internal config), so manual overrides work and audits work
- **Resource-capped systemd unit** so the autoscaler can never become the problem itself

## Implementation effort estimate

- Spec: done (this doc).
- Code: ~300 lines Python + ~30 lines unit test. **~4 hours focused work** including local unit tests.
- Deploy + shadow run: **~2 days elapsed time** (passive observation).
- Production cut-over: ~30 minutes after shadow validates.

**Net** : 1 session to write code + tests, then 2 days monitoring before flipping the live switch.
