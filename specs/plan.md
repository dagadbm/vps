# Plan: Reproducible NixOS VPS with OpenClaw

## Goal

One command (`./deploy.sh <IP>`) takes a fresh Hetzner Cloud CX23 (4GB RAM) running Ubuntu and turns it into a fully hardened NixOS server running OpenClaw.

The entire setup is reproducible: delete the server, create a new one, run the command again, and you get the exact same system.

## Prerequisites

### On your Mac (one-time setup)

1. **Install Docker Desktop** (for initial install only):
   - Download from https://docs.docker.com/desktop/install/mac-install/
   - Not needed for config updates (`switch` mode uses rsync + SSH)

2. **Have an SSH key** at `~/.ssh/github_personal` (no passphrase)

3. **rsync** (pre-installed on macOS) — used for pushing config updates

### On Hetzner (each time you want a fresh server)

1. Log into Hetzner Cloud console
2. Create a CX23 server (4GB RAM, 40GB disk)
3. Pick Ubuntu as the base OS (nixos-anywhere will replace it)
4. Add your SSH key during creation
5. Note the IP address

## What Gets Built (in order)

### Step 1: flake.nix + disk-config.nix

The foundation. `flake.nix` declares all dependencies (like a `package.json`). `disk-config.nix` tells disko how to partition the hard drive.

### Step 2: configuration.nix

The base NixOS system config. Sets up:
- System locale, timezone
- Your user account with SSH key
- An `openclaw` user for running the service
- Home Manager as a NixOS module
- Imports the security and openclaw modules

### Step 3: modules/security.nix

Server hardening:
- SSH: key-only login, passwords disabled, port 2222
- Firewall: only ports 2222 (SSH) and 443 (HTTPS) open, everything else blocked
- Automatic daily NixOS security updates
- No fail2ban for now (to avoid getting locked out while learning)

### Step 4: modules/openclaw.nix

OpenClaw setup using the official `nix-openclaw` Home Manager module:
- Installs OpenClaw gateway for the `openclaw` user
- Runs as a systemd user service (auto-starts on boot)
- Config lives in `/home/openclaw/.openclaw/`
- Secrets (API keys) loaded from `/home/openclaw/secrets/`

### Step 5: deploy.sh

The "one button" script. No local Nix required.

**First install** (`./deploy.sh <IP>`):
1. Checks Docker is installed and running
2. Validates you passed an IP address
3. Runs a `nixos/nix` Docker container that executes `nixos-anywhere` with `--build-on-remote`
4. Prints next steps (how to SSH in, where to put API keys)

**Config updates** (`./deploy.sh <IP> switch`):
1. Uses rsync to sync Nix files to the server at `/etc/nixos/`
2. SSHs in and runs `nixos-rebuild switch` on the server
3. No Docker or local Nix needed — just rsync and SSH

### Step 6: .gitignore

Ensures `secrets/` directory and any local overrides are never committed.

## Documentation Approach

Every `.nix` and `.sh` file will have detailed comments explaining:
- What each line does
- Why it's there
- Links to relevant documentation

This is a learning resource, not just a config.

## Day-to-Day Workflow

| Action | Command |
|--------|---------|
| First deploy | `./deploy.sh <IP>` |
| Change config | Edit `.nix` files, then `./deploy.sh <IP> switch` |
| Nuke and recreate | Delete server in Hetzner, create new one, `./deploy.sh <NEW-IP>` |
| Rollback a bad change | `ssh -p 2222 root@<IP> nixos-rebuild switch --rollback` |
| Check OpenClaw logs | `ssh -p 2222 openclaw@<IP> journalctl --user -u openclaw-gateway -f` |

## Future Additions (not in this plan)

- fail2ban (once comfortable with SSH access)
- sops-nix for encrypted secrets in the repo
- Telegram/Discord bot integration for OpenClaw
- Caddy reverse proxy with automatic TLS for OpenClaw gateway
- Monitoring/alerting
