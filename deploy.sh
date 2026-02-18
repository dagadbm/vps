#!/usr/bin/env bash
#
# deploy.sh — One-command deploy for the dagadbm-vps NixOS server
#
# No local Nix required. Uses Docker for initial install and rsync+SSH for updates.
#
# Usage:
#   ./deploy.sh <IP>          First install (wipes disk, installs NixOS via Docker)
#   ./deploy.sh <IP> switch   Push config updates to an existing NixOS server
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SSH key used for connecting to the server
SSH_KEY="$HOME/.ssh/github_personal"

# Nix files to sync for config updates (relative to project root)
NIX_FILES=(
  flake.nix
  flake.lock
  disk-config.nix
  configuration.nix
  modules/
)

# ── Validate arguments ───────────────────────────────────────────
if [ $# -lt 1 ]; then
  echo "Usage: ./deploy.sh <IP> [switch]"
  echo ""
  echo "  <IP>          Server IP address"
  echo "  switch        Push config updates (skip full reinstall)"
  echo ""
  echo "Examples:"
  echo "  ./deploy.sh 65.21.x.x          # First install (requires Docker)"
  echo "  ./deploy.sh 65.21.x.x switch   # Update config (rsync + SSH)"
  exit 1
fi

IP="$1"
MODE="${2:-install}"

# ── Deploy ────────────────────────────────────────────────────────
if [ "$MODE" = "switch" ]; then
  echo "==> Pushing config update to $IP (port 2222)..."
  echo ""

  # 1. rsync the Nix files to the server
  #    --delete removes files in /etc/nixos/ that no longer exist locally
  #    -e sets the SSH command with custom port
  #    --rsync-path creates the modules/ directory if it doesn't exist
  echo "--- Syncing Nix files to $IP:/etc/nixos/ ..."
  rsync -avz --delete \
    -e "ssh -p 2222 -i $SSH_KEY -o StrictHostKeyChecking=no" \
    --rsync-path="mkdir -p /etc/nixos/modules && rsync" \
    "${NIX_FILES[@]/#/$SCRIPT_DIR/}" \
    "root@$IP:/etc/nixos/"

  echo ""

  # 2. Run nixos-rebuild on the server
  echo "--- Running nixos-rebuild switch on $IP ..."
  ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "root@$IP" \
    "nixos-rebuild switch --flake /etc/nixos#dagadbm-vps"

  echo ""
  echo "==> Config update complete!"
  echo ""
  echo "Next steps:"
  echo "  ssh -p 2222 root@$IP          # SSH into the server"
  echo "  ssh -p 2222 openclaw@$IP      # SSH as openclaw user"
else
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

  echo "==> Installing NixOS on $IP..."
  echo "    This will WIPE the disk and install a fresh NixOS system."
  echo "    Using Docker to run nixos-anywhere (no local Nix needed)."
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
  #   3. --build-on-remote makes the Hetzner server compile everything
  #
  # SSH options: since the container is ephemeral, we skip host key checking
  docker run --rm -it \
    -v "$SSH_KEY:/root/.ssh/id_ed25519:ro" \
    -v "$SCRIPT_DIR:/work" \
    nixos/nix bash -c "
      mkdir -p /root/.config/nix
      echo 'experimental-features = nix-command flakes' > /root/.config/nix/nix.conf
      chmod 600 /root/.ssh/id_ed25519
      nix run nixpkgs#nixos-anywhere -- \
        --flake /work#dagadbm-vps \
        --target-host root@$IP \
        --build-on-remote \
        --ssh-option StrictHostKeyChecking=no \
        --ssh-option UserKnownHostsFile=/dev/null
    "

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
