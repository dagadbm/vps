#!/usr/bin/env bash
#
# update.sh — Push config updates to an existing NixOS server
#
# Syncs Nix files via rsync and runs nixos-rebuild switch.
# Uses your SSH config for connection details (port, key, user, etc).
#
# Usage:
#   ./update.sh --host <HOST>
#   ./update.sh --ip <IP>
#
# --host uses ~/.ssh/config for host/port/user/key.
# --ip connects directly as root on port 2222.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nix files to sync for config updates (relative to project root)
NIX_FILES=(
  flake.nix
  flake.lock
  disk-config.nix
  configuration.nix
  modules/
)

usage() {
  echo "Usage:"
  echo "  ./update.sh --host <HOST>"
  echo "  ./update.sh --ip <IP>"
  echo ""
  echo "Options:"
  echo "  --host <HOST>     SSH config hostname (reads ~/.ssh/config)"
  echo "  --ip <IP>         Server IP address (uses root@IP on port 2222)"
  echo ""
  echo "Examples:"
  echo "  ./update.sh --host host-name"
  echo "  ./update.sh --ip 46.225.171.96"
}

HOST_ALIAS=""
IP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      [ $# -ge 2 ] || { echo "Error: --host requires a value."; usage; exit 1; }
      HOST_ALIAS="$2"
      shift 2
      ;;
    --ip)
      [ $# -ge 2 ] || { echo "Error: --ip requires a value."; usage; exit 1; }
      IP="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'."
      usage
      exit 1
      ;;
  esac
done

if [ -n "$HOST_ALIAS" ] && [ -n "$IP" ]; then
  echo "Error: Use either --host or --ip, not both."
  usage
  exit 1
fi

if [ -z "$HOST_ALIAS" ] && [ -z "$IP" ]; then
  echo "Error: You must provide either --host or --ip."
  usage
  exit 1
fi

if [ -n "$HOST_ALIAS" ]; then
  TARGET="$HOST_ALIAS"
  TARGET_LABEL="$HOST_ALIAS"
  RSYNC_SSH="ssh"
  SSH_OPTS=()
else
  TARGET="root@$IP"
  TARGET_LABEL="$IP"
  RSYNC_SSH="ssh -p 2222"
  SSH_OPTS=(-p 2222)
fi

echo "==> Pushing config update to $TARGET_LABEL..."
echo ""

# 1. rsync the Nix files to the server
#    --delete removes files in /etc/nixos/ that no longer exist locally
#    --rsync-path creates the modules/ directory if it doesn't exist
echo "--- Syncing Nix files to $TARGET:/etc/nixos/ ..."
rsync -avz --delete \
  -e "$RSYNC_SSH" \
  --rsync-path="mkdir -p /etc/nixos/modules && rsync" \
  "${NIX_FILES[@]/#/$SCRIPT_DIR/}" \
  "$TARGET:/etc/nixos/"

echo ""

# 2. Run nixos-rebuild on the server
echo "--- Running nixos-rebuild switch on $TARGET ..."
ssh "${SSH_OPTS[@]}" "$TARGET" "nixos-rebuild switch --flake /etc/nixos#vps-personal"

echo ""
echo "==> Config update complete!"
