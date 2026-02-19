#!/usr/bin/env bash
#
# update.sh — Push config updates to an existing NixOS server
#
# Syncs Nix files via rsync and runs nixos-rebuild switch.
# Uses your SSH config for connection details (port, key, user, etc).
#
# Usage:
#   ./update.sh --host <HOST> --system <x86|arm>
#   ./update.sh --ip <IP> --system <x86|arm>
#
# --host uses ~/.ssh/config for host/port/user/key.
# --ip connects directly as root on port 2222.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helper: run a command on the remote server ───────────────
# Uses HOST_ALIAS (via SSH config) or root@IP on port 2222.
# Usage: remote_ssh [ssh-opts...] <command>
remote_ssh() {
  if [ -n "$HOST_ALIAS" ]; then
    ssh "$HOST_ALIAS" "$@"
  else
    ssh -p 2222 "root@$IP" "$@"
  fi
}

# Nix files to sync for config updates (relative to project root)
NIX_FILES=(
  flake.nix
  flake.lock
  modules/
  home-manager/
  secrets/secrets.yaml
  .sops.yaml
)

usage() {
  echo "Usage:"
  echo "  ./update.sh --host <HOST> --system <x86|arm>"
  echo "  ./update.sh --ip <IP> --system <x86|arm>"
  echo ""
  echo "Options:"
  echo "  --host <HOST>     SSH config hostname (reads ~/.ssh/config)"
  echo "  --ip <IP>         Server IP address (uses root@IP on port 2222)"
  echo "  --system <VALUE>  Target architecture: x86 or arm (required)"
  echo ""
  echo "Examples:"
  echo "  ./update.sh --host host-name --system x86"
  echo "  ./update.sh --host host-name --system arm"
  echo "  ./update.sh --ip 46.225.171.96 --system arm"
}

HOST_ALIAS=""
IP=""
SYSTEM=""

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
    --system)
      [ $# -ge 2 ] || { echo "Error: --system requires a value."; usage; exit 1; }
      SYSTEM="$2"
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

if [ -z "$SYSTEM" ]; then
  echo "Error: --system is required (x86 or arm)."
  usage
  exit 1
fi

if [ "$SYSTEM" != "x86" ] && [ "$SYSTEM" != "arm" ]; then
  echo "Error: --system must be one of: x86, arm."
  usage
  exit 1
fi

if [ "$SYSTEM" = "arm" ]; then
  NIX_SYSTEM="aarch64-linux"
  FLAKE_HOST="vps-arm"
else
  NIX_SYSTEM="x86_64-linux"
  FLAKE_HOST="vps-x86"
fi

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
  SSH_TARGET="$HOST_ALIAS"
  TARGET_LABEL="$HOST_ALIAS"
  RSYNC_SSH="ssh"
else
  SSH_TARGET="root@$IP"
  TARGET_LABEL="$IP"
  RSYNC_SSH="ssh -p 2222"
fi

echo "==> Pushing config update to $TARGET_LABEL..."
echo "    Target architecture: $SYSTEM ($NIX_SYSTEM), flake host: $FLAKE_HOST."
echo ""

# 1. rsync the Nix files to the server
#    --delete removes files in /etc/nixos/ that no longer exist locally
#    -R (--relative) preserves directory structure (e.g. modules/ stays as modules/)
echo "--- Syncing Nix files to $SSH_TARGET:/etc/nixos/ ..."
cd "$SCRIPT_DIR"
rsync -avzRi --delete \
  -e "$RSYNC_SSH" \
  "${NIX_FILES[@]}" \
  "$SSH_TARGET:/etc/nixos/"

echo ""

# 2. Run nixos-rebuild on the server
echo "--- Running nixos-rebuild switch on $SSH_TARGET ..."
remote_ssh "nixos-rebuild switch --flake /etc/nixos#$FLAKE_HOST"

echo ""
echo "==> Config update complete!"
