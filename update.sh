#!/usr/bin/env bash
#
# update.sh — Update flake inputs and sync to server
#
# Runs `nix flake update` to update flake.lock, then calls sync.sh
# to push the changes to the server and rebuild.
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

# Determine target label for messages
if [ -n "$HOST_ALIAS" ]; then
  TARGET_LABEL="$HOST_ALIAS"
else
  TARGET_LABEL="$IP"
fi

echo "==> Updating flake inputs..."
echo ""

# Run nix flake update in the project directory
cd "$SCRIPT_DIR"
if ! nix flake update; then
  echo ""
  echo "Error: nix flake update failed."
  exit 1
fi

echo ""
echo "==> Flake inputs updated successfully."
echo "==> Now syncing to $TARGET_LABEL..."
echo ""

# Build sync.sh arguments
SYNC_ARGS=("--system" "$SYSTEM")
if [ -n "$HOST_ALIAS" ]; then
  SYNC_ARGS+=("--host" "$HOST_ALIAS")
else
  SYNC_ARGS+=("--ip" "$IP")
fi

# Call sync.sh to push changes and rebuild
"$SCRIPT_DIR/sync.sh" "${SYNC_ARGS[@]}"

echo ""
echo "==> Update complete!"
