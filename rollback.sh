#!/usr/bin/env bash
#
# rollback.sh — Roll back VPS to a previous NixOS generation
#
# Provides rollback capabilities to undo broken updates.
#
# Usage:
#   ./rollback.sh --host <HOST> --list
#   ./rollback.sh --host <HOST> --previous
#   ./rollback.sh --host <HOST> --version <N>
#   ./rollback.sh --ip <IP> --list
#   ./rollback.sh --ip <IP> --previous
#   ./rollback.sh --ip <IP> --version <N>
#
# --host uses ~/.ssh/config for host/port/user/key.
# --ip connects directly as root on port 2222.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helper: run a command on the remote server ───────────────
# Uses HOST_ALIAS (via SSH config) or root@IP on port 2222.
# Usage: remote_ssh <command>
remote_ssh() {
  if [ -n "$HOST_ALIAS" ]; then
    ssh "$HOST_ALIAS" "$@"
  else
    ssh -p 2222 "root@$IP" "$@"
  fi
}

usage() {
  echo "Usage:"
  echo "  ./rollback.sh --host <HOST> --list"
  echo "  ./rollback.sh --host <HOST> --previous"
  echo "  ./rollback.sh --host <HOST> --version <N>"
  echo "  ./rollback.sh --ip <IP> --list"
  echo "  ./rollback.sh --ip <IP> --previous"
  echo "  ./rollback.sh --ip <IP> --version <N>"
  echo ""
  echo "Options:"
  echo "  --host <HOST>     SSH config hostname (reads ~/.ssh/config)"
  echo "  --ip <IP>         Server IP address (uses root@IP on port 2222)"
  echo "  --list            Show available generations"
  echo "  --previous        Roll back to previous generation"
  echo "  --version <N>     Roll back to specific generation number"
  echo ""
  echo "Examples:"
  echo "  ./rollback.sh --host host-name --list"
  echo "  ./rollback.sh --host host-name --previous"
  echo "  ./rollback.sh --host host-name --version 285"
  echo "  ./rollback.sh --ip 46.225.171.96 --list"
}

HOST_ALIAS=""
IP=""
ACTION=""
VERSION=""

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
    --list)
      [ -z "$ACTION" ] || { echo "Error: Only one action allowed (--list, --previous, or --version)."; usage; exit 1; }
      ACTION="list"
      shift
      ;;
    --previous)
      [ -z "$ACTION" ] || { echo "Error: Only one action allowed (--list, --previous, or --version)."; usage; exit 1; }
      ACTION="previous"
      shift
      ;;
    --version)
      [ -z "$ACTION" ] || { echo "Error: Only one action allowed (--list, --previous, or --version)."; usage; exit 1; }
      [ $# -ge 2 ] || { echo "Error: --version requires a number."; usage; exit 1; }
      ACTION="version"
      VERSION="$2"
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

# Validate arguments
if [ -z "$ACTION" ]; then
  echo "Error: You must specify one action: --list, --previous, or --version."
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

# Validate version is numeric if provided
if [ "$ACTION" = "version" ]; then
  if ! [[ "$VERSION" =~ ^[0-9]+$ ]]; then
    echo "Error: --version requires a numeric argument."
    usage
    exit 1
  fi
fi

# Determine target label for messages
if [ -n "$HOST_ALIAS" ]; then
  TARGET_LABEL="$HOST_ALIAS"
else
  TARGET_LABEL="$IP"
fi

# Execute the requested action
case "$ACTION" in
  list)
    echo "==> Listing available generations on $TARGET_LABEL..."
    echo ""
    remote_ssh "nixos-rebuild list-generations"
    exit 0
    ;;

  previous)
    echo "==> Rolling back $TARGET_LABEL to previous generation..."
    echo ""
    remote_ssh "nixos-rebuild switch --rollback"
    echo ""
    echo "✅ Rolled back to previous generation."
    echo "    Push a fixed config with './sync.sh' when ready."
    ;;

  version)
    echo "==> Rolling back $TARGET_LABEL to generation $VERSION..."
    echo ""

    # Verify generation exists
    if ! remote_ssh "test -e /nix/var/nix/profiles/system-$VERSION-link"; then
      echo "Error: Generation $VERSION does not exist on $TARGET_LABEL."
      echo "       Run './rollback.sh --host $TARGET_LABEL --list' to see available generations."
      exit 1
    fi

    # Switch to specific generation using the workaround from NixOS issue
    # https://github.com/NixOS/nixpkgs/issues/82851
    # (Direct switch-to-configuration doesn't update GRUB properly without this)
    remote_ssh "nix-env -p /nix/var/nix/profiles/system --set /nix/var/nix/profiles/system-$VERSION-link"
    remote_ssh "/nix/var/nix/profiles/system/bin/switch-to-configuration switch"

    echo ""
    echo "✅ Rolled back to generation $VERSION."
    echo "    Push a fixed config with './sync.sh' when ready."
    ;;
esac
