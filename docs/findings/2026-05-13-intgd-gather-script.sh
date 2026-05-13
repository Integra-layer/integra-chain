#!/usr/bin/env bash
# Read-only diagnostic gather for the Integra testnet validator.
# Runs entirely on the validator host. Writes ONLY to /tmp.
set -u

TS=$(date -u +%Y%m%dT%H%M%SZ)
HOST=$(hostname)
PID=$(pgrep -f '/usr/local/bin/intgd' | head -1)
echo "=== TS=$TS HOST=$HOST PID=$PID ==="
echo

# --- 1. Process & memory shape ---------------------------------------------
echo "===== 1. PROCESS / MEMORY ====="
echo "--- systemctl status ---"
systemctl status intgd --no-pager 2>&1 | head -25
echo
echo "--- free -m ---"
free -m
echo
echo "--- swapon --show ---"
swapon --show
echo
echo "--- ps for intgd ---"
ps -o pid,rss,vsz,sz,nlwp,etime,stat,comm -p "$PID" 2>/dev/null
echo
echo "--- /proc/$PID/status ---"
grep -E 'VmPeak|VmRSS|VmHWM|VmSwap|VmData|Threads' /proc/"$PID"/status 2>/dev/null
echo
echo "--- /proc/$PID/smaps_rollup ---"
grep -E 'Rss|Pss|Anonymous|Swap|Private_' /proc/"$PID"/smaps_rollup 2>/dev/null
echo

# --- 2. Logs over the last hour --------------------------------------------
echo "===== 2. JOURNAL (last 1h) ====="
JOURNAL=/tmp/intgd-journal-$TS.log
journalctl -u intgd --since '1 hour ago' --no-pager > "$JOURNAL" 2>/dev/null
echo "journal lines:" $(wc -l < "$JOURNAL")
echo
echo "--- counts ---"
printf 'Timed out:                                  %d\n' "$(grep -c 'Timed out' "$JOURNAL")"
printf 'ERR:                                        %d\n' "$(grep -c 'ERR' "$JOURNAL")"
printf 'panic (should be 0):                        %d\n' "$(grep -ic 'panic' "$JOURNAL")"
printf 'replacement transaction underpriced:        %d\n' "$(grep -c 'replacement transaction underpriced' "$JOURNAL")"
printf 'nonce too low:                              %d\n' "$(grep -c 'nonce too low' "$JOURNAL")"
printf 'consensus failure:                          %d\n' "$(grep -c 'consensus failure' "$JOURNAL")"
printf 'oom / out of memory:                        %d\n' "$(grep -ic 'oom\|out of memory' "$JOURNAL")"
printf 'RoundStepPropose:                           %d\n' "$(grep -c 'RoundStepPropose' "$JOURNAL")"
printf 'compaction:                                 %d\n' "$(grep -ic 'compaction' "$JOURNAL")"
echo
echo "--- last 20 ERR lines (deduped) ---"
grep 'ERR' "$JOURNAL" | awk -F 'ERR ' '{print $2}' | sort | uniq -c | sort -rn | head -20
echo
echo "--- last 10 Timed out lines ---"
grep 'Timed out' "$JOURNAL" | tail -10
echo

# --- 3. Kernel OOM history --------------------------------------------------
echo "===== 3. KERNEL OOM (24h) ====="
journalctl -k --since '24 hours ago' 2>/dev/null | grep -iE 'oom|killed process' | tail -20
echo

# --- 4. Chain liveness (3 samples 30s apart) -------------------------------
echo "===== 4. CHAIN LIVENESS (3 samples 30s apart) ====="
for i in 1 2 3; do
  T=$(date -u +%H:%M:%S)
  echo "--- sample $i @ ${T}Z ---"
  curl -s --max-time 5 http://localhost:26657/status \
    | grep -E '"latest_block_height"|"latest_block_time"|"catching_up"|"earliest_block_height"' \
    | head -10
  if [ $i -lt 3 ]; then sleep 30; fi
done
echo

# --- 5. Topology & peer state ---------------------------------------------
echo "===== 5. TOPOLOGY / PEERS ====="
echo "--- /validators?height=latest (first 200 lines) ---"
curl -s --max-time 5 'http://localhost:26657/validators?height=latest' | head -200
echo
echo "--- /net_info (first 100 lines) ---"
curl -s --max-time 5  http://localhost:26657/net_info               | head -100
echo
echo "--- /num_unconfirmed_txs ---"
curl -s --max-time 5  http://localhost:26657/num_unconfirmed_txs
echo
echo "--- intgd query staking validators (top 5) ---"
intgd query staking validators --output json 2>/dev/null | head -120
echo

# --- 6. Consensus snapshot --------------------------------------------------
echo "===== 6. CONSENSUS STATE ====="
echo "--- /consensus_state head 200 ---"
curl -s --max-time 5  http://localhost:26657/consensus_state         | head -200
echo
echo "--- /dump_consensus_state head 150 ---"
curl -s --max-time 5  http://localhost:26657/dump_consensus_state    | head -150
echo

# --- 7. DB shape ------------------------------------------------------------
echo "===== 7. DB SHAPE ====="
echo "--- du -sh of data subdirs ---"
du -sh /root/.intgd/data 2>/dev/null
du -sh /root/.intgd/data/application.db 2>/dev/null
du -sh /root/.intgd/data/blockstore.db  2>/dev/null
du -sh /root/.intgd/data/state.db       2>/dev/null
du -sh /root/.intgd/data/tx_index.db    2>/dev/null
du -sh /root/.intgd/data/cs.wal         2>/dev/null
du -sh /root/.intgd/data/evidence.db    2>/dev/null
echo
echo "--- application.db top-level ls ---"
ls -lh   /root/.intgd/data/application.db 2>/dev/null | head -10
echo
echo "--- SST file count (under data/) ---"
find     /root/.intgd/data -maxdepth 3 -name '*.sst' 2>/dev/null | wc -l
echo "--- WAL/MANIFEST files (top of application.db) ---"
find     /root/.intgd/data/application.db -maxdepth 2 \( -name 'MANIFEST-*' -o -name 'CURRENT' -o -name '*.log' \) 2>/dev/null | head -10
echo

# --- 8. Effective config ----------------------------------------------------
echo "===== 8. APP.TOML / CONFIG.TOML KEY VALUES ====="
echo "--- app.toml [json-rpc][api][mempool][pruning] sections ---"
awk 'BEGIN{p=0} /^\[/{p=0} /^\[(json-rpc|api|state-sync)\]/{p=1} p{print}' /root/.intgd/config/app.toml 2>/dev/null | head -120
echo "--- top-level pruning / snapshot keys (app.toml) ---"
grep -E '^(pruning|snapshot|min-retain|halt|inter-block-cache|index-events|iavl-)' /root/.intgd/config/app.toml 2>/dev/null | head -30
echo
echo "--- config.toml [mempool][consensus][tx_index][p2p] ---"
awk 'BEGIN{p=0} /^\[/{p=0} /^\[(mempool|consensus|tx_index|p2p|statesync|rpc|fastsync|blocksync)\]/{p=1} p{print}' /root/.intgd/config/config.toml 2>/dev/null | head -180
echo
echo "--- key knobs grep ---"
grep -E 'pruning|snapshot-interval|snapshot-keep-recent|gas-cap|evm-timeout|max_txs_bytes|cache=|size =|recheck|pprof' \
     /root/.intgd/config/app.toml /root/.intgd/config/config.toml 2>/dev/null
echo

# --- 9. pprof probe ---------------------------------------------------------
echo "===== 9. PPROF PROBE ====="
curl -s --max-time 3 -o /dev/null -w 'pprof_http_root=%{http_code}\n' http://localhost:6060/debug/pprof/ 2>/dev/null
curl -s --max-time 5    http://localhost:6060/debug/pprof/goroutine?debug=1 2>/dev/null | head -200
echo
echo "--- pprof on CometBFT (default 26660 / sometimes :6060 via [rpc] pprof_laddr) ---"
curl -s --max-time 3 -o /dev/null -w 'pprof_tm=%{http_code}\n' http://localhost:26660/debug/pprof/ 2>/dev/null
echo

# --- 10. Disk/CPU/sockets --------------------------------------------------
echo "===== 10. DISK / CPU / SOCKETS ====="
if command -v iostat >/dev/null 2>&1; then
  echo "--- iostat -x 1 5 ---"
  iostat -x 1 5
else
  echo "--- vmstat 1 5 (no iostat) ---"
  vmstat 1 5
fi
echo
echo "--- established sockets ---"
ss -tan state established 2>/dev/null | wc -l
echo "--- :26656 (p2p) listening + established ---"
ss -tan '( sport = :26656 or dport = :26656 )' 2>/dev/null | wc -l
echo "--- :26657 (rpc) ---"
ss -tan '( sport = :26657 or dport = :26657 )' 2>/dev/null | wc -l
echo "--- :8545 (evm rpc) ---"
ss -tan '( sport = :8545  or dport = :8545  )' 2>/dev/null | wc -l
echo "--- :6065 / :8546 (ws) ---"
ss -tan '( sport = :8546  or dport = :8546  )' 2>/dev/null | wc -l

echo
echo "=== END TS=$(date -u +%Y%m%dT%H%M%SZ) ==="
echo "Journal stashed at: $JOURNAL"
