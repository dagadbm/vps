#!/usr/bin/env bash
#
# deploy.sh — One-command deploy for the dagadbm-vps NixOS server
#
# Usage:
#   ./deploy.sh <IP>          First install (wipes disk, installs NixOS)
#   ./deploy.sh <IP> switch   Push config updates to an existing NixOS server
#
set -euo pipefail

# ── Check prerequisites ──────────────────────────────────────────
if ! command -v nix &>/dev/null; then
  echo "Error: Nix is not installed."
  echo ""
  echo "Install it with the Determinate Systems installer:"
  echo "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
  echo ""
  echo "Then restart your shell and run this script again."
  exit 1
fi

# ── Validate arguments ───────────────────────────────────────────
if [ $# -lt 1 ]; then
  echo "Usage: ./deploy.sh <IP> [switch]"
  echo ""
  echo "  <IP>          Server IP address"
  echo "  switch        Push config updates (skip full reinstall)"
  echo ""
  echo "Examples:"
  echo "  ./deploy.sh 65.21.x.x          # First install"
  echo "  ./deploy.sh 65.21.x.x switch   # Update config"
  exit 1
fi

IP="$1"
MODE="${2:-install}"

# ── Deploy ────────────────────────────────────────────────────────
if [ "$MODE" = "switch" ]; then
  echo "==> Pushing config update to $IP (port 2222)..."
  echo ""

  # nixos-rebuild connects over SSH to the existing NixOS server
  # Port 2222 because our security.nix configures SSH on that port
  NIX_SSHOPTS="-p 2222" nixos-rebuild switch \
    --flake ".#dagadbm-vps" \
    --target-host "root@$IP" \
    --build-on-remote

  echo ""
  echo "==> Config update complete!"
  echo ""
  echo "Next steps:"
  echo "  ssh -p 2222 root@$IP          # SSH into the server"
  echo "  ssh -p 2222 openclaw@$IP      # SSH as openclaw user"
else
  echo "==> Installing NixOS on $IP..."
  echo "    This will WIPE the disk and install a fresh NixOS system."
  echo ""

  # nixos-anywhere:
  # 1. SSHs into the server (Ubuntu) on the default port 22
  # 2. Boots a temporary NixOS installer via kexec
  # 3. Partitions the disk using disko (disk-config.nix)
  # 4. Builds and installs the NixOS config on the server
  # 5. Reboots into the new NixOS system
  nix run github:nix-community/nixos-anywhere -- \
    --flake ".#dagadbm-vps" \
    --target-host "root@$IP" \
    --build-on-remote

  echo ""
  echo "==> NixOS installation complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Wait ~30 seconds for the server to reboot"
  echo "  2. SSH in:  ssh -p 2222 root@$IP"
  echo "  3. Set up OpenClaw secrets:"
  echo "     ssh -p 2222 openclaw@$IP 'mkdir -p ~/secrets'"
  echo "     scp -P 2222 secrets/gateway-token openclaw@$IP:~/secrets/"
  echo "  4. To update config later:  ./deploy.sh $IP switch"
fi
