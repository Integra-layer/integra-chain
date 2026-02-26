#!/bin/bash
# cosmovisor-setup.sh — Install and configure Cosmovisor for Integra validators.
#
# Run this on each validator node after intgd is deployed and running.
# It installs Cosmovisor, sets up the directory structure, and updates systemd.
#
# Usage: ./cosmovisor-setup.sh [--go-path /usr/local/go/bin]

set -e

BOLD='\033[1m' GREEN='\033[0;32m' CYAN='\033[0;36m'
YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'

HOME_DIR="${HOME_DIR:-/root/.intgd}"
DAEMON_NAME="intgd"
GO_PATH="${1:-/usr/local/go/bin}"

log()  { echo -e "${CYAN}[cosmovisor]${NC} $*"; }
ok()   { echo -e "${GREEN}[    ok    ]${NC} $*"; }
err()  { echo -e "${RED}[  error   ]${NC} $*" >&2; }

# ---- Step 1: Install Cosmovisor ----
install_cosmovisor() {
  if command -v cosmovisor >/dev/null 2>&1; then
    ok "Cosmovisor already installed: $(cosmovisor version 2>&1 | head -1)"
    return
  fi

  log "Installing Cosmovisor..."
  if ! command -v go >/dev/null 2>&1; then
    if [ -x "$GO_PATH/go" ]; then
      export PATH="$GO_PATH:$PATH"
    else
      err "Go not found. Install Go first or pass --go-path"
      exit 1
    fi
  fi

  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
  ok "Cosmovisor installed: $(cosmovisor version 2>&1 | head -1)"
}

# ---- Step 2: Directory structure ----
setup_directories() {
  log "Setting up Cosmovisor directory structure..."

  mkdir -p "$HOME_DIR/cosmovisor/genesis/bin"
  mkdir -p "$HOME_DIR/cosmovisor/upgrades"

  # Copy current binary
  local intgd_path
  intgd_path=$(command -v intgd)
  if [ -z "$intgd_path" ]; then
    err "intgd binary not found in PATH"
    exit 1
  fi

  cp "$intgd_path" "$HOME_DIR/cosmovisor/genesis/bin/intgd"
  chmod +x "$HOME_DIR/cosmovisor/genesis/bin/intgd"

  ok "Directory structure ready:"
  echo "    $HOME_DIR/cosmovisor/"
  echo "    +-- genesis/bin/intgd"
  echo "    +-- upgrades/"
}

# ---- Step 3: Update systemd ----
update_systemd() {
  log "Updating systemd service..."

  # Find cosmovisor binary
  local cosmovisor_path
  cosmovisor_path=$(command -v cosmovisor || echo "/root/go/bin/cosmovisor")

  cat > /etc/systemd/system/intgd.service << EOF
[Unit]
Description=Integra Layer Node (Cosmovisor)
After=network-online.target

[Service]
User=root
Environment="DAEMON_NAME=${DAEMON_NAME}"
Environment="DAEMON_HOME=${HOME_DIR}"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=false"
ExecStart=${cosmovisor_path} run start --home ${HOME_DIR}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=append:/var/log/intgd/node.log
StandardError=append:/var/log/intgd/error.log

[Install]
WantedBy=multi-user.target
EOF

  mkdir -p /var/log/intgd
  systemctl daemon-reload
  ok "Systemd service updated to use Cosmovisor"
}

# ---- Step 4: Restart ----
restart_service() {
  log "Restarting intgd service..."
  systemctl restart intgd

  # Wait a moment and check
  sleep 3
  if systemctl is-active --quiet intgd; then
    ok "Node running via Cosmovisor"
    echo ""
    log "Verify with:"
    echo "  journalctl -u intgd -f"
    echo "  intgd status --home $HOME_DIR | jq '.sync_info.latest_block_height'"
  else
    err "Service failed to start. Check: journalctl -u intgd --no-pager -n 50"
    exit 1
  fi
}

# ---- Main ----
echo -e "${CYAN}Integra Layer — Cosmovisor Setup${NC}"
echo ""

install_cosmovisor
setup_directories
update_systemd
restart_service

echo ""
ok "Cosmovisor setup complete!"
echo ""
echo -e "  ${CYAN}How upgrades work:${NC}"
echo "  1. Submit governance proposal with upgrade plan (name + height)"
echo "  2. Place new binary at: $HOME_DIR/cosmovisor/upgrades/<name>/bin/intgd"
echo "  3. Cosmovisor auto-switches at the upgrade height"
echo ""
