#!/usr/bin/env bash
#
# sync.sh — Push config updates to an existing NixOS server
#
# Syncs Nix files via rsync and runs nixos-rebuild switch.
# Uses your SSH config for connection details (port, key, user, etc).
#
# Usage:
#   ./sync.sh --host <HOST> --system <x86|arm>
#   ./sync.sh --ip <IP> --system <x86|arm>
#
# --host uses ~/.ssh/config for host/port/user/key.
# --ip connects directly as root on port 2222.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

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
  echo "  ./sync.sh --host <HOST> --system <x86|arm>"
  echo "  ./sync.sh --ip <IP> --system <x86|arm>"
  echo ""
  echo "Options:"
  echo "  --host <HOST>     SSH config hostname (reads ~/.ssh/config)"
  echo "  --ip <IP>         Server IP address (uses root@IP on port 2222)"
  echo "  --system <VALUE>  Target architecture: x86 or arm (required)"
  echo ""
  echo "Examples:"
  echo "  ./sync.sh --host host-name --system x86"
  echo "  ./sync.sh --host host-name --system arm"
  echo "  ./sync.sh --ip 46.225.171.96 --system arm"
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

validate_system_arg "$SYSTEM" usage
validate_connection_args "$HOST_ALIAS" "$IP" usage
NIX_SYSTEM="$(get_nix_system "$SYSTEM")"
FLAKE_HOST="$(get_flake_host "$SYSTEM")"
TARGET_LABEL="$(first_valid "$HOST_ALIAS" "$IP")"
SSH_TARGET="$(first_valid "$HOST_ALIAS" "$(ssh_uri "$IP" 2222)")"

if [ -n "$HOST_ALIAS" ]; then
  RSYNC_TARGET="$HOST_ALIAS"
  RSYNC_SSH="ssh -o StrictHostKeyChecking=accept-new"
else
  RSYNC_TARGET="root@$IP"
  RSYNC_SSH="ssh -p 2222 -o StrictHostKeyChecking=accept-new"
fi

echo "==> Pushing config update to $TARGET_LABEL..."
echo "    Target architecture: $SYSTEM ($NIX_SYSTEM), flake host: $FLAKE_HOST."
echo ""

# 1. rsync the Nix files to the server
#    --delete removes files in /etc/nixos/ that no longer exist locally
#    -R (--relative) preserves directory structure (e.g. modules/ stays as modules/)
echo "--- Syncing Nix files to $RSYNC_TARGET:/etc/nixos/ ..."
cd "$SCRIPT_DIR"
rsync -avzRi --delete \
  -e "$RSYNC_SSH" \
  "${NIX_FILES[@]}" \
  "$RSYNC_TARGET:/etc/nixos/"

echo ""

# 2. Run nixos-rebuild on the server
echo "--- Running nixos-rebuild switch on $TARGET_LABEL ..."
ssh_exec "$SSH_TARGET" "nixos-rebuild switch --flake /etc/nixos#$FLAKE_HOST"

echo ""
echo "==> Config update complete!"
