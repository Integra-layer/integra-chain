#!/usr/bin/env python3
"""
intgd-throttle — Caddy throttle autoscaler for the Integra testnet validator.

Watches intgd's live goroutine count and block-lag and, when degradation is
detected, lowers Caddy's `max_conns_per_host` on the /evm reverse_proxy blocks.
When health returns, gradually raises the cap back up. Hysteresis prevents
oscillation; hard bounds and validate-before-reload prevent runaway breakage.

Spec: integra-chain/docs/findings/2026-05-13-throttle-autoscaler-spec.md
Skill: integra-chain/.omc/skills/cosmos-evm-getlogs-storm-diagnosis.md
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from urllib.request import urlopen


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

POLL_INTERVAL_S = 30
CONFIRM_COOLER_POLLS = 2          # tighten after N polls below current state
CONFIRM_WARMER_POLLS = 10         # loosen after N polls above current state
MIN_TIME_IN_STATE_S = 300         # don't loosen before 5 min in current state
MEMORY_PANIC_GB = 11.5            # extra safety: force PANIC if heap above this

PPROF_URL = "http://localhost:6060/debug/pprof/goroutine?debug=1"
STATUS_URL = "http://localhost:26657/status"

# (name, goroutines_thr, lag_thr_s, max_conns).
# Selection rule: walk from PANIC down; first row whose thresholds are crossed wins.
# "NORMAL" is the default bucket if nothing colder than COOL applies.
STATES = [
    # name,     g_thr,   l_thr_s, max_conns
    ("PANIC",   30_000, 300,      8),
    ("HOT",     15_000, 60,       16),
    ("WARM",    5_000,  20,       32),
    ("NORMAL",  2_000,  5,        64),   # default-ish bucket
    ("COOL",    0,      0,        128),  # only when goroutines<2000 AND lag<5s
]
STATE_NAMES = [s[0] for s in STATES]
MAX_CONNS_TABLE = {s[0]: s[3] for s in STATES}
ALLOWED_CAPS = sorted(set(MAX_CONNS_TABLE.values()))  # for validation

DEFAULT_CADDYFILE = "/etc/caddy/Caddyfile"
DEFAULT_STATE_DIR = "/var/lib/intgd-throttle"
DEFAULT_STATE_FILE = f"{DEFAULT_STATE_DIR}/state.json"
DEFAULT_LAST_GOOD = f"{DEFAULT_STATE_DIR}/last-good-Caddyfile"

EXPECTED_OCCURRENCES = 4  # number of "max_conns_per_host N" lines we expect


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logger = logging.getLogger("intgd-throttle")


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO

    class JSONFormatter(logging.Formatter):
        def format(self, record):
            payload = {
                "ts": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
                "level": record.levelname,
                "msg": record.getMessage(),
            }
            extra = getattr(record, "extra_fields", None)
            if extra:
                payload.update(extra)
            return json.dumps(payload, ensure_ascii=False)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(level)


def log_event(event: str, **fields) -> None:
    """Emit a structured log line."""
    record = logger.makeRecord(
        name=logger.name,
        level=logging.INFO,
        fn="",
        lno=0,
        msg=event,
        args=None,
        exc_info=None,
    )
    record.extra_fields = {"event": event, **fields}
    logger.handle(record)


# ---------------------------------------------------------------------------
# Metric fetchers (each raises on failure; caller decides to freeze)
# ---------------------------------------------------------------------------

def fetch_pprof_goroutines(timeout: float = 5.0, url: str = PPROF_URL) -> int:
    """Return live goroutine count by parsing pprof's first line."""
    with urlopen(url, timeout=timeout) as r:
        first_line = r.readline().decode("ascii", errors="replace").strip()
    match = re.search(r"total\s+(\d+)", first_line)
    if not match:
        raise RuntimeError(f"pprof first line not parseable: {first_line!r}")
    return int(match.group(1))


def fetch_block_lag_seconds(timeout: float = 10.0, url: str = STATUS_URL) -> int:
    """Return wall_time - latest_block_time, in seconds (non-negative clamp)."""
    with urlopen(url, timeout=timeout) as r:
        body = r.read()
    data = json.loads(body)
    bt_str: str = data["result"]["sync_info"]["latest_block_time"]
    bt_str = re.sub(r"\.\d+", "", bt_str)         # strip fractional seconds
    bt = datetime.fromisoformat(bt_str.replace("Z", "+00:00"))
    wall = datetime.now(timezone.utc)
    lag = int((wall - bt).total_seconds())
    return max(0, lag)


def fetch_intgd_memory_gb(timeout: float = 5.0) -> float:
    """Return MemoryCurrent for the intgd unit in GB."""
    r = subprocess.run(
        ["systemctl", "show", "intgd", "-p", "MemoryCurrent"],
        capture_output=True, text=True, timeout=timeout, check=True,
    )
    match = re.search(r"MemoryCurrent=(\d+)", r.stdout)
    if not match:
        raise RuntimeError(f"systemctl show output not parseable: {r.stdout!r}")
    return int(match.group(1)) / (1024 ** 3)


# ---------------------------------------------------------------------------
# State classification
# ---------------------------------------------------------------------------

def classify(goroutines: int, lag_s: int, memory_gb: float) -> str:
    """Return observed state name based on current metrics."""
    if memory_gb >= MEMORY_PANIC_GB:
        return "PANIC"
    if goroutines > 30_000 or lag_s > 300:
        return "PANIC"
    if goroutines > 15_000 or lag_s > 60:
        return "HOT"
    if goroutines > 5_000 or lag_s > 20:
        return "WARM"
    if goroutines >= 2_000 or lag_s >= 5:
        return "NORMAL"
    return "COOL"


def state_idx(name: str) -> int:
    return STATE_NAMES.index(name)


def is_cooler(observed: str, current: str) -> bool:
    """observed is COLDER (tighter) than current — i.e. lower index."""
    return state_idx(observed) < state_idx(current)


def is_warmer(observed: str, current: str) -> bool:
    """observed is WARMER (looser) than current — i.e. higher index."""
    return state_idx(observed) > state_idx(current)


def step_one_warmer(current: str) -> str:
    """Return the next-warmer state, capped at COOL."""
    i = min(state_idx(current) + 1, len(STATE_NAMES) - 1)
    return STATE_NAMES[i]


# ---------------------------------------------------------------------------
# Caddyfile mutation
# ---------------------------------------------------------------------------

CAP_PATTERN = re.compile(r"(max_conns_per_host)\s+\d+")


def caddyfile_set_cap(content: str, new_cap: int) -> str:
    """Replace every `max_conns_per_host N` with the new value. Strict count check."""
    if new_cap not in ALLOWED_CAPS:
        raise ValueError(f"cap {new_cap} not in allowed set {ALLOWED_CAPS}")
    new_content, n = CAP_PATTERN.subn(rf"\1 {new_cap}", content)
    if n != EXPECTED_OCCURRENCES:
        raise RuntimeError(
            f"expected {EXPECTED_OCCURRENCES} max_conns_per_host occurrences, found {n}"
        )
    return new_content


def caddyfile_read_current_cap(content: str) -> Optional[int]:
    """Read the current cap value from Caddyfile. Returns None if not unique."""
    values = [int(m.group(1)) for m in re.finditer(r"max_conns_per_host\s+(\d+)", content)]
    if not values:
        return None
    if len(set(values)) != 1:
        return None  # inconsistent state, don't trust it
    return values[0]


def cap_to_state(cap: int) -> str:
    """Reverse lookup: which state corresponds to a given cap value?"""
    for name, c in MAX_CONNS_TABLE.items():
        if c == cap:
            return name
    return "NORMAL"  # fallback


# ---------------------------------------------------------------------------
# Caddy operations
# ---------------------------------------------------------------------------

def caddy_validate(path: str, timeout: float = 15.0) -> bool:
    r = subprocess.run(
        ["caddy", "validate", "--config", path, "--adapter", "caddyfile"],
        capture_output=True, text=True, timeout=timeout,
    )
    if r.returncode != 0:
        log_event("caddy_validate_failed", stdout=r.stdout[:500], stderr=r.stderr[:500])
    return r.returncode == 0


def caddy_reload(timeout: float = 15.0) -> bool:
    r = subprocess.run(
        ["systemctl", "reload", "caddy"],
        capture_output=True, text=True, timeout=timeout,
    )
    if r.returncode != 0:
        log_event("caddy_reload_failed", stdout=r.stdout[:500], stderr=r.stderr[:500])
    return r.returncode == 0


def apply_cap(caddyfile_path: str, last_good_path: str, new_cap: int, dry_run: bool) -> bool:
    """Mutate Caddyfile + validate + reload. Rollback on any failure."""
    with open(caddyfile_path, "r", encoding="utf-8") as f:
        original = f.read()

    try:
        new_content = caddyfile_set_cap(original, new_cap)
    except Exception as e:
        log_event("caddyfile_mutation_failed", error=str(e))
        return False

    if original == new_content:
        log_event("caddyfile_already_at_target", cap=new_cap)
        return True

    if dry_run:
        log_event("dry_run_would_apply", new_cap=new_cap, bytes_changed=len(new_content) - len(original))
        return True

    # Snapshot for rollback (always overwrite — represents last known-good state).
    shutil.copy2(caddyfile_path, last_good_path)

    tmp_path = caddyfile_path + ".new"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(new_content)

    if not caddy_validate(tmp_path):
        os.unlink(tmp_path)
        log_event("apply_aborted_validate_failed")
        return False

    os.replace(tmp_path, caddyfile_path)

    if not caddy_reload():
        # rollback
        shutil.copy2(last_good_path, caddyfile_path)
        caddy_reload()
        log_event("apply_rolled_back_reload_failed")
        return False

    return True


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------

@dataclass
class ThrottleState:
    current: str = "NORMAL"
    since: float = 0.0
    cooler_streak: int = 0
    warmer_streak: int = 0
    version: int = 1


def load_state(path: str) -> ThrottleState:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return ThrottleState(**{k: v for k, v in data.items() if k in ThrottleState.__dataclass_fields__})
    except (FileNotFoundError, json.JSONDecodeError):
        return ThrottleState(current="NORMAL", since=time.time())


def save_state(state: ThrottleState, path: str) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(asdict(state), f, indent=2)
    os.replace(tmp, path)


# ---------------------------------------------------------------------------
# Transition decision
# ---------------------------------------------------------------------------

def decide_transition(state: ThrottleState, observed: str, now: float) -> Optional[str]:
    """Return new state name to apply, or None to stay."""
    if observed == state.current:
        state.cooler_streak = 0
        state.warmer_streak = 0
        return None

    # PANIC is an immediate downward transition regardless of streak
    if observed == "PANIC" and state.current != "PANIC":
        return "PANIC"

    if is_cooler(observed, state.current):
        state.warmer_streak = 0
        state.cooler_streak += 1
        if state.cooler_streak >= CONFIRM_COOLER_POLLS:
            return observed
        return None

    if is_warmer(observed, state.current):
        state.cooler_streak = 0
        # require min time in current state
        if now - state.since < MIN_TIME_IN_STATE_S:
            state.warmer_streak = 0
            return None
        state.warmer_streak += 1
        if state.warmer_streak >= CONFIRM_WARMER_POLLS:
            return step_one_warmer(state.current)
        return None

    return None


# ---------------------------------------------------------------------------
# Main poll loop
# ---------------------------------------------------------------------------

def poll_once(state: ThrottleState, caddyfile: str, last_good: str, dry_run: bool, now_fn=time.time) -> ThrottleState:
    """Run one polling tick. Returns updated state."""
    try:
        g = fetch_pprof_goroutines()
    except Exception as e:
        log_event("fetch_pprof_failed", error=str(e), action="freeze")
        return state
    try:
        l = fetch_block_lag_seconds()
    except Exception as e:
        log_event("fetch_status_failed", error=str(e), action="freeze")
        return state
    try:
        m = fetch_intgd_memory_gb()
    except Exception as e:
        log_event("fetch_memory_failed", error=str(e), action="freeze")
        return state

    observed = classify(g, l, m)
    now = now_fn()
    log_event(
        "poll",
        goroutines=g, lag_s=l, memory_gb=round(m, 2),
        current=state.current, observed=observed,
        cap=MAX_CONNS_TABLE[state.current],
        cooler_streak=state.cooler_streak, warmer_streak=state.warmer_streak,
        time_in_state_s=int(now - state.since),
    )

    new_state_name = decide_transition(state, observed, now)
    if new_state_name is None:
        return state

    new_cap = MAX_CONNS_TABLE[new_state_name]
    log_event(
        "transition_start",
        from_state=state.current, to_state=new_state_name,
        new_cap=new_cap,
        dry_run=dry_run,
    )

    ok = apply_cap(caddyfile, last_good, new_cap, dry_run=dry_run)
    if not ok:
        log_event("transition_failed", to_state=new_state_name)
        return state

    state.current = new_state_name
    state.since = now
    state.cooler_streak = 0
    state.warmer_streak = 0
    log_event("transition_done", to_state=new_state_name, new_cap=new_cap)
    return state


_should_stop = False


def _handle_sigterm(signum, frame):
    global _should_stop
    _should_stop = True
    log_event("signal_received", signum=signum)


def sync_state_with_caddyfile(state: ThrottleState, caddyfile: str) -> ThrottleState:
    """Reconcile state.current with the Caddyfile's actual cap value.
    If they disagree (e.g. operator hand-edited the file, or state file is stale),
    trust the Caddyfile and update state.current. Resets `since` so any UP transition
    has to re-earn its 5-minute hold time.
    """
    try:
        with open(caddyfile, "r", encoding="utf-8") as f:
            cur_cap = caddyfile_read_current_cap(f.read())
    except FileNotFoundError:
        log_event("caddyfile_missing", path=caddyfile)
        raise
    if cur_cap is None:
        log_event("caddyfile_cap_not_unique", path=caddyfile, action="keep_state")
        return state
    inferred = cap_to_state(cur_cap)
    if inferred != state.current:
        log_event(
            "state_sync_with_caddyfile",
            state_file_value=state.current,
            caddyfile_cap=cur_cap,
            inferred_state=inferred,
        )
        state.current = inferred
        state.since = time.time()
        state.cooler_streak = 0
        state.warmer_streak = 0
    return state


def main_loop(caddyfile: str, state_file: str, last_good: str, dry_run: bool) -> int:
    state = load_state(state_file)
    try:
        state = sync_state_with_caddyfile(state, caddyfile)
    except FileNotFoundError:
        return 1
    save_state(state, state_file)
    log_event("daemon_started", state=state.current, cap=MAX_CONNS_TABLE[state.current], dry_run=dry_run)

    signal.signal(signal.SIGTERM, _handle_sigterm)
    signal.signal(signal.SIGINT, _handle_sigterm)

    while not _should_stop:
        state = poll_once(state, caddyfile, last_good, dry_run=dry_run)
        save_state(state, state_file)
        for _ in range(POLL_INTERVAL_S):
            if _should_stop:
                break
            time.sleep(1)

    log_event("daemon_stopping", state=state.current)
    return 0


# ---------------------------------------------------------------------------
# Inline tests (python3 -m unittest intgd_throttle.Test*)
# ---------------------------------------------------------------------------

SAMPLE_CADDYFILE = """testnet.integralayer.com {
	handle_path /evm/* {
		reverse_proxy localhost:8545 {
			header_down -Access-Control-Allow-Origin
			transport http {
				max_conns_per_host 16
				dial_timeout 3s
				response_header_timeout 12s
				read_timeout 14s
				write_timeout 14s
			}
		}
	}

	handle_path /evm {
		reverse_proxy localhost:8545 {
			header_down -Access-Control-Allow-Origin
			transport http {
				max_conns_per_host 16
				dial_timeout 3s
				response_header_timeout 12s
				read_timeout 14s
				write_timeout 14s
			}
		}
	}
}

testnet.explorer.integralayer.com {
	handle_path /evm {
		reverse_proxy localhost:8545 {
			transport http {
				max_conns_per_host 16
				dial_timeout 3s
				response_header_timeout 12s
				read_timeout 14s
				write_timeout 14s
			}
		}
	}
}

admin.testnet.explorer.integralayer.com {
	handle_path /evm {
		reverse_proxy localhost:8545 {
			transport http {
				max_conns_per_host 16
				dial_timeout 3s
				response_header_timeout 12s
				read_timeout 14s
				write_timeout 14s
			}
		}
	}
}
"""


class TestClassify(unittest.TestCase):
    def test_cool(self):
        self.assertEqual(classify(500, 1, 5.0), "COOL")

    def test_normal(self):
        self.assertEqual(classify(2500, 4, 5.0), "NORMAL")
        self.assertEqual(classify(500, 10, 5.0), "NORMAL")

    def test_warm(self):
        self.assertEqual(classify(6000, 25, 5.0), "WARM")
        self.assertEqual(classify(500, 25, 5.0), "WARM")

    def test_hot(self):
        self.assertEqual(classify(20_000, 30, 5.0), "HOT")
        self.assertEqual(classify(500, 90, 5.0), "HOT")

    def test_panic_via_goroutines(self):
        self.assertEqual(classify(35_000, 10, 5.0), "PANIC")

    def test_panic_via_lag(self):
        self.assertEqual(classify(500, 400, 5.0), "PANIC")

    def test_panic_via_memory(self):
        self.assertEqual(classify(500, 1, 12.0), "PANIC")


class TestCaddyfileSetCap(unittest.TestCase):
    def test_replace_to_8(self):
        result = caddyfile_set_cap(SAMPLE_CADDYFILE, 8)
        self.assertEqual(result.count("max_conns_per_host 8"), 4)
        self.assertEqual(result.count("max_conns_per_host 16"), 0)

    def test_replace_to_128(self):
        result = caddyfile_set_cap(SAMPLE_CADDYFILE, 128)
        self.assertEqual(result.count("max_conns_per_host 128"), 4)

    def test_rejects_unknown_cap(self):
        with self.assertRaises(ValueError):
            caddyfile_set_cap(SAMPLE_CADDYFILE, 47)

    def test_rejects_wrong_occurrence_count(self):
        broken = SAMPLE_CADDYFILE.replace("max_conns_per_host 16", "max_conns_per_host 16", 2)  # no-op, still 4
        # Now actually break it: remove one occurrence.
        first = broken.find("max_conns_per_host 16")
        broken_3 = broken[:first] + broken[first + len("max_conns_per_host 16"):]
        with self.assertRaises(RuntimeError):
            caddyfile_set_cap(broken_3, 32)

    def test_read_current_cap(self):
        self.assertEqual(caddyfile_read_current_cap(SAMPLE_CADDYFILE), 16)

    def test_read_current_cap_inconsistent(self):
        weird = SAMPLE_CADDYFILE.replace("max_conns_per_host 16", "max_conns_per_host 32", 1)
        self.assertIsNone(caddyfile_read_current_cap(weird))


class TestDecideTransition(unittest.TestCase):
    def test_no_change_same_state(self):
        s = ThrottleState(current="NORMAL", since=0.0)
        self.assertIsNone(decide_transition(s, "NORMAL", now=1000))

    def test_panic_immediate(self):
        s = ThrottleState(current="NORMAL", since=0.0)
        self.assertEqual(decide_transition(s, "PANIC", now=1000), "PANIC")

    def test_cooler_requires_2_polls(self):
        s = ThrottleState(current="NORMAL", since=0.0)
        self.assertIsNone(decide_transition(s, "WARM", now=1000))  # 1 poll
        self.assertEqual(decide_transition(s, "WARM", now=1030), "WARM")  # 2 polls

    def test_warmer_blocked_before_5min(self):
        s = ThrottleState(current="HOT", since=1000.0)
        # Even with 10 confirmations, must wait 5 min in current state.
        for _ in range(15):
            r = decide_transition(s, "WARM", now=1100)  # only 100s in
            self.assertIsNone(r)
        self.assertEqual(s.warmer_streak, 0)

    def test_warmer_after_5min_and_10_polls(self):
        s = ThrottleState(current="HOT", since=0.0)
        for i in range(9):
            r = decide_transition(s, "WARM", now=400 + i)  # 400s+ in state
            self.assertIsNone(r)
        r = decide_transition(s, "WARM", now=410)  # 10th
        self.assertEqual(r, "WARM")  # step one warmer from HOT = WARM ✓

    def test_warmer_steps_one_state_at_a_time(self):
        s = ThrottleState(current="PANIC", since=0.0)
        for _ in range(10):
            r = decide_transition(s, "COOL", now=500)
        self.assertEqual(r, "HOT")  # one step from PANIC, not jump to COOL


class TestCapToState(unittest.TestCase):
    def test_known_caps(self):
        self.assertEqual(cap_to_state(8), "PANIC")
        self.assertEqual(cap_to_state(16), "HOT")
        self.assertEqual(cap_to_state(32), "WARM")
        self.assertEqual(cap_to_state(64), "NORMAL")
        self.assertEqual(cap_to_state(128), "COOL")

    def test_unknown_falls_back(self):
        self.assertEqual(cap_to_state(99), "NORMAL")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def cli() -> int:
    p = argparse.ArgumentParser(description="Caddy throttle autoscaler for intgd")
    p.add_argument("--caddyfile", default=DEFAULT_CADDYFILE)
    p.add_argument("--state-file", default=DEFAULT_STATE_FILE)
    p.add_argument("--last-good", default=DEFAULT_LAST_GOOD)
    p.add_argument("--dry-run", action="store_true",
                   help="observe and decide, but never mutate Caddyfile")
    p.add_argument("--once", action="store_true",
                   help="run a single poll and exit (good for cron / debug)")
    p.add_argument("--verbose", action="store_true")
    p.add_argument("--test", action="store_true",
                   help="run inline unit tests and exit")
    args = p.parse_args()

    setup_logging(verbose=args.verbose)

    if args.test:
        suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
        runner = unittest.TextTestRunner(verbosity=2)
        result = runner.run(suite)
        return 0 if result.wasSuccessful() else 1

    if args.once:
        state = load_state(args.state_file)
        try:
            state = sync_state_with_caddyfile(state, args.caddyfile)
        except FileNotFoundError:
            return 1
        state = poll_once(state, args.caddyfile, args.last_good, dry_run=args.dry_run)
        save_state(state, args.state_file)
        return 0

    return main_loop(args.caddyfile, args.state_file, args.last_good, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(cli())
