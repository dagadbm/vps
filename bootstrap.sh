#!/usr/bin/env bash
#
# bootstrap.sh — First-time NixOS install on a fresh Hetzner VPS
#
# Wipes the disk and installs NixOS via Docker + nixos-anywhere.
# Connects on port 22 (Hetzner default) since NixOS isn't installed yet.
#
# Usage:
#   ./bootstrap.sh --host <HOST> --system <x86|arm>
#   ./bootstrap.sh --ip <IP> --system <x86|arm> [--ssh-key <PATH>]
#
# --host uses ~/.ssh/config to resolve HostName and IdentityFile.
# --ip connects directly and uses --ssh-key (or a detected default key).
# Port and user are ignored — bootstrap always connects on port 22 as root.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage:"
  echo "  ./bootstrap.sh --host <HOST> --system <x86|arm>"
  echo "  ./bootstrap.sh --ip <IP> --system <x86|arm> [--ssh-key <PATH>]"
  echo ""
  echo "Options:"
  echo "  --host <HOST>     SSH config hostname (reads ~/.ssh/config)"
  echo "  --ip <IP>         Server IP address"
  echo "  --ssh-key <PATH>  SSH private key path for --ip mode (optional)"
  echo "  --system <VALUE>  Target architecture: x86 or arm (required)"
  echo ""
  echo "Examples:"
  echo "  ./bootstrap.sh --host host-name --system x86"
  echo "  ./bootstrap.sh --host host-name --system arm"
  echo "  ./bootstrap.sh --ip 46.225.171.96 --system x86 --ssh-key ~/.ssh/github_personal"
}

HOST_ALIAS=""
IP=""
SSH_KEY=""
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
    --ssh-key)
      [ $# -ge 2 ] || { echo "Error: --ssh-key requires a value."; usage; exit 1; }
      SSH_KEY="$2"
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

if [ -n "$HOST_ALIAS" ] && [ -n "$SSH_KEY" ]; then
  echo "Error: --ssh-key can only be used with --ip."
  usage
  exit 1
fi

if [ -n "$HOST_ALIAS" ]; then
  HOST_LABEL="$HOST_ALIAS"
  SSH_INFO="$(ssh -G "$HOST_ALIAS" 2>/dev/null || true)"
  IP="$(printf '%s\n' "$SSH_INFO" | awk '/^hostname / { print $2; exit }')"

  if [ -z "$IP" ] || [ "$IP" = "$HOST_ALIAS" ]; then
    echo "Error: Could not resolve '$HOST_ALIAS' to an IP from SSH config."
    echo "Add a Host entry in ~/.ssh/config with a HostName."
    exit 1
  fi

  while IFS= read -r key; do
    key="${key/#\~/$HOME}"
    if [ -f "$key" ]; then
      SSH_KEY="$key"
      break
    fi
  done < <(printf '%s\n' "$SSH_INFO" | awk '/^identityfile / { print $2 }')
else
  HOST_LABEL="$IP"

  # In --ip mode, use explicit --ssh-key first, then try OpenSSH defaults.
  if [ -n "$SSH_KEY" ]; then
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
  fi

  if [ -z "$SSH_KEY" ]; then
    for key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/github_personal"; do
      if [ -f "$key" ]; then
        SSH_KEY="$key"
        break
      fi
    done
  fi
fi

if [ -z "$SSH_KEY" ] || [ ! -f "$SSH_KEY" ]; then
  echo "Error: Could not find a usable SSH key."
  echo "If using --host, add IdentityFile in ~/.ssh/config."
  echo "If using --ip, pass --ssh-key <PATH>."
  exit 1
fi

if [ -n "$HOST_ALIAS" ]; then
  POST_INSTALL_SSH="ssh $HOST_ALIAS"
  POST_INSTALL_OPENCLAW_SSH="ssh $HOST_ALIAS -l openclaw"
  POST_INSTALL_OPENCLAW_SCP="scp -P 2222 secrets/gateway-token openclaw@$HOST_ALIAS:~/secrets/"
  POST_INSTALL_UPDATE="./update.sh --host $HOST_ALIAS --system $SYSTEM"
else
  POST_INSTALL_SSH="ssh -p 2222 root@$IP"
  POST_INSTALL_OPENCLAW_SSH="ssh -p 2222 openclaw@$IP"
  POST_INSTALL_OPENCLAW_SCP="scp -P 2222 secrets/gateway-token openclaw@$IP:~/secrets/"
  POST_INSTALL_UPDATE="./update.sh --ip $IP --system $SYSTEM"
fi

# ── Check Docker is available ──────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed."
  echo ""
  echo "Install Docker Desktop for Mac:"
  echo "  https://docs.docker.com/desktop/install/mac-install/"
  echo ""
  echo "Then restart your terminal and run this script again."
  exit 1
fi

if ! docker info &>/dev/null; then
  echo "Error: Docker daemon is not running."
  echo ""
  echo "Start Docker Desktop and try again."
  exit 1
fi

echo "==> Installing NixOS on $IP (via $HOST_LABEL)..."
echo "    This will WIPE the disk and install a fresh NixOS system."
echo "    Using Docker to run nixos-anywhere (no local Nix needed)."
echo "    Target architecture: $SYSTEM ($NIX_SYSTEM), flake host: $FLAKE_HOST."
echo ""

# Run nixos-anywhere inside a nixos/nix Docker container.
#
# Mounts:
#   - SSH key as /root/.ssh/id_ed25519 (read-only) so nixos-anywhere can reach the server
#   - Project directory as /work so the flake is available inside the container
#
# The container:
#   1. Enables flakes in the ephemeral Nix config
#   2. Runs nixos-anywhere pointing at the server
#   3. Builds inside the Docker container for the selected target system, NOT on the remote,
#      to avoid OOM on low-memory VPS. The closure is copied over SSH.
#
# Connects on port 22 (Hetzner default for fresh servers).
# SSH options: since the container is ephemeral, we skip host key checking.
docker run --rm -it \
  -v "$SSH_KEY:/root/.ssh/id_ed25519:ro" \
  -v "$SCRIPT_DIR:/work" \
  nixos/nix bash -c "
    mkdir -p /root/.config/nix
    echo 'experimental-features = nix-command flakes' > /root/.config/nix/nix.conf
    chmod 600 /root/.ssh/id_ed25519
    nix run nixpkgs#nixos-anywhere -- \
      --flake /work#$FLAKE_HOST \
      --target-host root@$IP \
      --ssh-option StrictHostKeyChecking=no \
      --ssh-option UserKnownHostsFile=/dev/null
  "

echo ""
echo "==> NixOS installation complete!"
echo ""
echo "Next steps:"
echo "  1. Wait ~30 seconds for the server to reboot"
echo "  2. SSH in:  $POST_INSTALL_SSH"
echo "  3. Set up OpenClaw secrets:"
echo "     $POST_INSTALL_OPENCLAW_SSH 'mkdir -p ~/secrets'"
echo "     $POST_INSTALL_OPENCLAW_SCP"
echo "  4. To update config later:  $POST_INSTALL_UPDATE"
