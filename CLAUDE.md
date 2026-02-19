# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Declarative NixOS VPS configuration for running OpenClaw (AI/LLM gateway) on Hetzner Cloud. The entire server — OS, services, disk layout, firewall — is defined in Nix files and deployed over SSH. The system is fully reproducible: wipe the server, re-run deploy, get the exact same setup.

## Deployment Commands

No local Nix required. First install uses Docker; config updates use rsync + SSH. Both scripts accept either `--host <alias>` (from `~/.ssh/config`) or `--ip <address>`, plus required `--system <x86|arm>`.

```bash
# First install — wipes disk, installs NixOS via Docker + nixos-anywhere (connects on port 22)
./bootstrap.sh --host host-name --system x86
./bootstrap.sh --host host-name --system arm

# First install using direct IP (optional explicit key path)
./bootstrap.sh --ip 46.225.171.96 --system x86 --ssh-key ~/.ssh/github_personal
./bootstrap.sh --ip 46.225.171.96 --system arm --ssh-key ~/.ssh/github_personal

# Push config updates to existing server (rsync + nixos-rebuild, uses SSH config)
./update.sh --host host-name --system x86
./update.sh --host host-name --system arm

# Push config updates using direct IP (assumes root@IP on port 2222)
./update.sh --ip 46.225.171.96 --system x86
./update.sh --ip 46.225.171.96 --system arm
```

Prerequisites: Docker Desktop (bootstrap only), rsync (ships with macOS), and either:
- SSH config entry for `--host` mode
- Reachable server IP for `--ip` mode

SSH config example (`~/.ssh/config`):
```
Host host-name
    HostName 46.225.171.96
    User root
    Port 2222
    IdentityFile ~/.ssh/github_personal
```

After first install, manually set up the OpenClaw token:
```bash
ssh host-name -l openclaw 'mkdir -p ~/secrets'
scp -P 2222 secrets/gateway-token openclaw@host-name:~/secrets/
```

## Architecture

**Flake outputs**:
- `nixosConfigurations.vps-x86` (`x86_64-linux`)
- `nixosConfigurations.vps-arm` (`aarch64-linux`)

**Module structure**:
- `flake.nix` — Pins dependencies: nixpkgs (unstable), disko, home-manager, nix-openclaw. All inputs follow nixpkgs for version coherence.
- `modules/system.nix` — System identity (hostname, timezone, locale), bootloader (GRUB for Hetzner BIOS boot), user accounts (`root` + `openclaw`), Home Manager integration. Imports security module below.
- `modules/disk.nix` — Disko partition layout for `/dev/sda`: BIOS boot (1MB) + ESP (512MB at `/boot`) + root (ext4, remaining space).
- `modules/security.nix` — SSH on port 2222 (key-only, no passwords), firewall (only 2222+443 open), fail2ban with SSH jail, daily auto-upgrades with reboot.
- `home-manager/openclaw.nix` — OpenClaw Home Manager module for the `openclaw` user. Gateway in local mode (localhost-only), token auth from `/home/openclaw/secrets/gateway-token`, default instance auto-starts.

**Key relationships**:
- `nix-openclaw` is passed to all modules via `specialArgs` and to Home Manager via `extraSpecialArgs`
- The `nix-openclaw.overlays.default` overlay makes OpenClaw packages available system-wide
- OpenClaw runs as a systemd user service under the `openclaw` account (no sudo)
- Secrets are `.gitignored` and manually placed on the server (not Nix-managed)

## Important Constraints

- **GRUB required**: Hetzner Cloud uses BIOS boot. systemd-boot will not work.
- **SSH port 2222**: All SSH commands need `-p 2222` (or `-P 2222` for scp). `update.sh --ip` applies this automatically; `--host` uses your SSH config.
- **State version 24.11**: Do not change `system.stateVersion` or `home.stateVersion` after deployment.
- **fail2ban enabled**: SSH jail on port 2222, bans after 5 failed attempts, incremental ban times for repeat offenders.
- **Secrets not in Nix**: The gateway token file is manually managed. Future plan is sops-nix.
