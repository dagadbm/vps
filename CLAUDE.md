# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Declarative NixOS VPS configuration for running OpenClaw (AI/LLM gateway) on Hetzner Cloud. The entire server — OS, services, disk layout, firewall — is defined in Nix files and deployed over SSH. The system is fully reproducible: wipe the server, re-run deploy, get the exact same setup.

## Deployment Commands

No local Nix required. First install uses Docker; config updates use rsync + SSH.

```bash
# First install — wipes disk, installs NixOS via Docker + nixos-anywhere (connects on port 22)
./deploy.sh <IP>

# Push config updates to existing server (rsync + nixos-rebuild, connects on port 2222)
./deploy.sh <IP> switch
```

Prerequisites: Docker Desktop (install mode only), SSH key at `~/.ssh/github_personal`, rsync (ships with macOS).

After first install, manually set up the OpenClaw token:
```bash
ssh -p 2222 openclaw@<IP> 'mkdir -p ~/secrets'
scp -P 2222 secrets/gateway-token openclaw@<IP>:~/secrets/
```

## Architecture

**Single flake output**: `nixosConfigurations.dagadbm-vps` (x86_64-linux)

**Module structure**:
- `flake.nix` — Pins dependencies: nixpkgs (unstable), disko, home-manager, nix-openclaw. All inputs follow nixpkgs for version coherence.
- `configuration.nix` — System identity (hostname, timezone, locale), bootloader (GRUB for Hetzner BIOS boot), user accounts (`root` + `openclaw`), Home Manager integration. Imports both modules below.
- `disk-config.nix` — Disko partition layout for `/dev/sda`: BIOS boot (1MB) + ESP (512MB at `/boot`) + root (ext4, remaining space).
- `modules/security.nix` — SSH on port 2222 (key-only, no passwords), firewall (only 2222+443 open), daily auto-upgrades with reboot.
- `modules/openclaw.nix` — OpenClaw via Home Manager for the `openclaw` user. Gateway in local mode (localhost-only), token auth from `/home/openclaw/secrets/gateway-token`, default instance auto-starts.

**Key relationships**:
- `nix-openclaw` is passed to all modules via `specialArgs` and to Home Manager via `extraSpecialArgs`
- The `nix-openclaw.overlays.default` overlay makes OpenClaw packages available system-wide
- OpenClaw runs as a systemd user service under the `openclaw` account (no sudo)
- Secrets are `.gitignored` and manually placed on the server (not Nix-managed)

## Important Constraints

- **GRUB required**: Hetzner Cloud uses BIOS boot. systemd-boot will not work.
- **SSH port 2222**: All SSH commands need `-p 2222` (or `-P 2222` for scp). deploy.sh handles this for the `switch` mode.
- **State version 24.11**: Do not change `system.stateVersion` or `home.stateVersion` after deployment.
- **No fail2ban**: Intentionally omitted for now to avoid lockouts.
- **Secrets not in Nix**: The gateway token file is manually managed. Future plan is sops-nix.
