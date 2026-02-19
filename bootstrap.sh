#!/usr/bin/env bash
#
# bootstrap.sh — First-time NixOS install on a fresh Hetzner VPS
#
# Wipes the disk and installs NixOS via Docker + nixos-anywhere.
# Connects on port 22 (Hetzner default) since NixOS isn't installed yet.
# Provisions the sops age key via --extra-files for automatic secret decryption.
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

# ── Helper: run a command on the remote server ───────────────
# Uses HOST_ALIAS (via SSH config) or root@IP on port 2222.
# Extra SSH options can be passed before the command.
# Usage: remote_ssh [ssh-opts...] <command>
remote_ssh() {
  if [ -n "$HOST_ALIAS" ]; then
    ssh "$HOST_ALIAS" "$@"
  else
    ssh -p 2222 "root@$IP" "$@"
  fi
}

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
  echo "--- Resolving SSH config for host '$HOST_ALIAS'..."
  SSH_INFO="$(ssh -G "$HOST_ALIAS" 2>/dev/null || true)"
  IP="$(printf '%s\n' "$SSH_INFO" | awk '/^hostname / { print $2; exit }')"
  PORTS=("22")
  SSH_CONFIG_PORT="$(printf '%s\n' "$SSH_INFO" | awk '/^port / { print $2; exit }')"
  if [ -n "$SSH_CONFIG_PORT" ] && [ "$SSH_CONFIG_PORT" != "22" ]; then
    PORTS+=("$SSH_CONFIG_PORT")
  fi

  if [ -z "$IP" ] || [ "$IP" = "$HOST_ALIAS" ]; then
    echo "Error: Could not resolve '$HOST_ALIAS' to an IP from SSH config."
    echo "Add a Host entry in ~/.ssh/config with a HostName."
    exit 1
  fi
  echo "    Resolved hostname: $IP"

  while IFS= read -r key; do
    key="${key/#\~/$HOME}"
    if [ -f "$key" ]; then
      SSH_KEY="$key"
      break
    fi
  done < <(printf '%s\n' "$SSH_INFO" | awk '/^identityfile / { print $2 }')

  if [ -n "$SSH_KEY" ]; then
    echo "    Using SSH key: $SSH_KEY"
  else
    echo "    No valid IdentityFile found in SSH config for '$HOST_ALIAS'."
  fi
else
  HOST_LABEL="$IP"

  # In --ip mode, use explicit --ssh-key first, then try OpenSSH defaults.
  if [ -n "$SSH_KEY" ]; then
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    echo "--- Using provided SSH key: $SSH_KEY"
  fi

  if [ -z "$SSH_KEY" ]; then
    echo "--- No SSH key specified, searching defaults..."
    for key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/github_personal"; do
      if [ -f "$key" ]; then
        SSH_KEY="$key"
        echo "    Found default key: $SSH_KEY"
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

# ── Validate age key for sops-nix ─────────────────────────────
if [ ! -f "$SCRIPT_DIR/secrets/age-key.txt" ]; then
  echo "Error: Age key not found at secrets/age-key.txt"
  echo "Generate one with: age-keygen -o secrets/age-key.txt"
  exit 1
fi

SSH_PORT="22"
POST_KEXEC_SSH_PORT="22"
if [ -n "$HOST_ALIAS" ]; then
  echo "--- Testing SSH port 22 for $HOST_ALIAS..."
  if ssh -p 22 -i "$SSH_KEY" \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@"$IP" true 2>/dev/null; then
    SSH_PORT="22"
  else
    for port in "${PORTS[@]}"; do
      if [ "$port" = "22" ]; then
        continue
      fi
      echo "--- Port 22 failed. Trying SSH port $port from config..."
      if ssh -p "$port" -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@"$IP" true 2>/dev/null; then
        SSH_PORT="$port"
        break
      fi
    done
  fi
fi

echo "--- SSH connection info"
if [ -n "$HOST_ALIAS" ]; then
  echo "    Host (alias): $HOST_ALIAS"
  echo "    Host (resolved): $IP"
  UPDATE_ARGS="--host $HOST_ALIAS --system $SYSTEM"
  POST_INSTALL_SSH="ssh $HOST_ALIAS"
else
  echo "    Host: $IP"
  UPDATE_ARGS="--ip $IP --system $SYSTEM"
  POST_INSTALL_SSH="ssh -p 2222 root@$IP"
fi
echo "    SSH key: $SSH_KEY"
echo "    Initial port: $SSH_PORT"
echo "    Post-kexec port: $POST_KEXEC_SSH_PORT"
echo ""

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

# ── Remove stale host keys ────────────────────────────────────
# Bootstrap wipes the server, so old SSH host keys are always invalid.
# Remove entries for both the default port and our custom port 2222.
echo "--- Removing stale SSH host keys for $IP..."
ssh-keygen -R "$IP" 2>/dev/null || true
ssh-keygen -R "[$IP]:$SSH_PORT" 2>/dev/null || true
ssh-keygen -R "[$IP]:$POST_KEXEC_SSH_PORT" 2>/dev/null || true
ssh-keygen -R "[$IP]:2222" 2>/dev/null || true
if [ -n "$HOST_ALIAS" ]; then
  ssh-keygen -R "$HOST_ALIAS" 2>/dev/null || true
  ssh-keygen -R "[$HOST_ALIAS]:$SSH_PORT" 2>/dev/null || true
  ssh-keygen -R "[$HOST_ALIAS]:$POST_KEXEC_SSH_PORT" 2>/dev/null || true
  ssh-keygen -R "[$HOST_ALIAS]:2222" 2>/dev/null || true
fi

echo "==> Installing NixOS on $IP (via $HOST_LABEL, initial port $SSH_PORT -> post-kexec port $POST_KEXEC_SSH_PORT)..."
echo "    This will WIPE the disk and install a fresh NixOS system."
echo "    Using Docker to run nixos-anywhere (no local Nix needed)."
echo "    Target architecture: $SYSTEM ($NIX_SYSTEM), flake host: $FLAKE_HOST."
echo ""

# ── Prepare extra-files for sops age key ──────────────────────
# nixos-anywhere's --extra-files copies these into the new system's filesystem.
# This places the age private key where sops-nix expects it.
EXTRA_FILES_DIR="$(mktemp -d)"
mkdir -p "$EXTRA_FILES_DIR/var/lib/sops-nix"
cp "$SCRIPT_DIR/secrets/age-key.txt" "$EXTRA_FILES_DIR/var/lib/sops-nix/key.txt"
chmod 600 "$EXTRA_FILES_DIR/var/lib/sops-nix/key.txt"

# Run nixos-anywhere inside a nixos/nix Docker container.
#
# Mounts:
#   - SSH key as /root/.ssh/id_ed25519 (read-only) so nixos-anywhere can reach the server
#   - Project directory as /work so the flake is available inside the container
#   - Extra-files directory for sops age key provisioning
#
# The container:
#   1. Enables flakes in the ephemeral Nix config
#   2. Runs nixos-anywhere pointing at the server
#   3. Builds inside the Docker container for the selected target system, NOT on the remote,
#      to avoid OOM on low-memory VPS. The closure is copied over SSH.
#
# Connects on port 22 first, then falls back to port(s) from SSH config.
# SSH options: since the container is ephemeral, we skip host key checking.
docker run --rm -it \
  -v vps-nix-store:/nix \
  -v "$SSH_KEY:/root/.ssh/id_ed25519:ro" \
  -v "$SCRIPT_DIR:/work" \
  -v "$EXTRA_FILES_DIR:/extra-files:ro" \
  nixos/nix bash -c "
    mkdir -p /root/.config/nix
    echo 'experimental-features = nix-command flakes' > /root/.config/nix/nix.conf
    chmod 600 /root/.ssh/id_ed25519
    nix run nixpkgs#nixos-anywhere -- \
      --flake /work#$FLAKE_HOST \
      --target-host root@$IP \
      --ssh-port $SSH_PORT \
      --post-kexec-ssh-port $POST_KEXEC_SSH_PORT \
      --extra-files /extra-files \
      --ssh-option StrictHostKeyChecking=no \
      --ssh-option UserKnownHostsFile=/dev/null
  "

# Clean up temporary extra-files directory
rm -rf "$EXTRA_FILES_DIR"

echo ""
echo "==> NixOS installation complete!"
echo ""

# ── Wait for server to come back on port 2222 ────────────────
echo "--- Waiting for server to reboot and become reachable on port 2222..."

for i in $(seq 1 60); do
  if remote_ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    true 2>/dev/null; then
    echo "    Server is up!"
    break
  fi
  if [ "$i" = "60" ]; then
    echo "Error: Server did not become reachable after 5 minutes."
    exit 1
  fi
  sleep 5
done

# ── Run update.sh to ensure full config is applied ───────────
echo "--- Running update.sh to ensure all Nix config is fully applied..."
"$SCRIPT_DIR/update.sh" $UPDATE_ARGS

# ── Optimise the Nix store ───────────────────────────────────
echo "--- Running nix-store --optimise on server..."
remote_ssh "nix-store --optimise"

echo ""
echo "==> Bootstrap fully complete!"
echo ""
echo "Next steps:"
echo "  1. SSH in: $POST_INSTALL_SSH"
echo "  2. To update config later:  ./update.sh $UPDATE_ARGS"
