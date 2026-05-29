#!/usr/bin/env bash
# Validator config drift check (INT — 2026-05-29 permanent-fix).
# Diffs the LIVE app.toml/config.toml on each validator against the checked-in baseline
# in infra/validators/<node>/. Exits non-zero if any undeclared drift is found.
#
# Usage (local):   INTEGRA_SSH_KEY=~/.ssh/integra ./infra/validators/check-drift.sh
# Usage (CI):      provide the SSH key via the INTEGRA_SSH_KEY env / a workflow secret.
#
# Per-node fields legitimately differ (gateway is the public backend, signers are RPC-locked):
#   gateway:  gas-cap=300000000  evm-timeout=15s  api="eth,net,web3"  address=0.0.0.0:8545  max-open-connections=600
#   signers:  gas-cap=50000000   evm-timeout=8s   api="eth,net,web3"  address=127.0.0.1:8545 max-open-connections=200
# Each node is diffed against ITS OWN baseline, so these intentional differences are not flagged.
# If you intentionally change a live config, update the matching infra/validators/<node>/ file in the same PR.
set -uo pipefail

KEY="${INTEGRA_SSH_KEY:-$HOME/.ssh/integra}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# node -> IP
NODES=("gateway:46.225.231.81" "signer-1:45.77.139.208" "signer-2:159.223.206.94")

drift=0
for entry in "${NODES[@]}"; do
  node="${entry%%:*}"; host="${entry##*:}"
  for cfg in app.toml config.toml; do
    base="$REPO_DIR/$node/$cfg"
    if [ ! -f "$base" ]; then echo "MISSING BASELINE: $base"; drift=1; continue; fi
    if ! ssh -i "$KEY" -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@"$host" \
         "cat ~/.intgd/config/$cfg" > "/tmp/live-$node-$cfg" 2>/dev/null; then
      echo "ERROR: could not read $node ($host) $cfg over SSH"; drift=1; continue
    fi
    if diff -u "$base" "/tmp/live-$node-$cfg" > "/tmp/drift-$node-$cfg.diff" 2>&1; then
      echo "OK:    $node $cfg matches baseline"
    else
      echo "DRIFT: $node $cfg differs from baseline ($base):"
      sed 's/^/       /' "/tmp/drift-$node-$cfg.diff"
      drift=1
    fi
  done
done

echo "----------------------------------------------------------------"
if [ "$drift" = 0 ]; then
  echo "RESULT: all validator configs match the checked-in baseline (no drift)."
else
  echo "RESULT: CONFIG DRIFT DETECTED. Either (a) the live change is intended -> update"
  echo "        infra/validators/<node>/ to match and commit it, or (b) it is undeclared"
  echo "        drift -> revert the live config to the baseline."
fi
exit "$drift"
