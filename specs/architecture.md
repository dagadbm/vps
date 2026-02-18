# Architecture: Reproducible NixOS VPS

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ Your Mac                                                        │
│                                                                 │
│  dagadbm-vps/           Nix (installed via Determinate Systems) │
│  ├── flake.nix          │                                       │
│  ├── deploy.sh ─────────┼──► nixos-anywhere ──► SSH ──────┐     │
│  ├── ...                │                                 │     │
│  └── secrets/           ▼                                 │     │
│      └── (API keys)   builds the NixOS config             │     │
│                       (or delegates to server              │     │
│                        with --build-on-remote)             │     │
└────────────────────────────────────────────────────────────┼─────┘
                                                            │
                                                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ Hetzner Cloud CX23 (4GB RAM, 40GB disk)                         │
│                                                                 │
│  1. Starts as Ubuntu (Hetzner default)                          │
│  2. nixos-anywhere boots NixOS installer via kexec               │
│  3. disko partitions the disk                                   │
│  4. NixOS is installed from your flake config                   │
│  5. Server reboots into NixOS                                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ NixOS                                                    │    │
│  │                                                          │    │
│  │  ┌──────────────────────┐  ┌──────────────────────────┐ │    │
│  │  │ security.nix         │  │ openclaw.nix              │ │    │
│  │  │                      │  │                           │ │    │
│  │  │ - SSH on port 2222   │  │ - Home Manager module     │ │    │
│  │  │ - Key-only auth      │  │ - official nix-openclaw   │ │    │
│  │  │ - Firewall (2222,443)│  │ - systemd user service    │ │    │
│  │  │ - Auto-updates       │  │ - openclaw-gateway        │ │    │
│  │  └──────────────────────┘  └──────────────────────────┘ │    │
│  │                                                          │    │
│  │  Users:                                                  │    │
│  │  - root (SSH key, no password)                           │    │
│  │  - dagadbm (your user, SSH key, sudo)                    │    │
│  │  - openclaw (service user, runs OpenClaw)                │    │
│  │                                                          │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
dagadbm-vps/
├── flake.nix                  # Dependency declarations (nixpkgs, disko, nix-openclaw, home-manager)
├── flake.lock                 # Pinned versions (auto-generated, committed to git)
├── deploy.sh                  # One-command deploy script
├── disk-config.nix            # Disk partitioning layout for disko
├── configuration.nix          # Main NixOS config (imports modules)
├── modules/
│   ├── security.nix           # SSH, firewall, auto-updates
│   └── openclaw.nix           # OpenClaw via Home Manager + nix-openclaw
├── secrets/                   # .gitignored — API keys, tokens
│   └── .gitkeep
├── specs/
│   ├── plan.md                # This plan
│   └── architecture.md        # This file
└── .gitignore
```

## Component Details

### flake.nix — The Dependency Manager

Think of this as a `package.json` for the entire operating system.

**Inputs** (dependencies):
| Input | What it is | Why we need it |
|-------|-----------|----------------|
| `nixpkgs` | The NixOS package collection | Base packages and NixOS modules |
| `disko` | Declarative disk partitioning | So nixos-anywhere can format the drive |
| `home-manager` | Per-user config management | Required by official nix-openclaw |
| `nix-openclaw` | Official OpenClaw Nix package | Installs and runs OpenClaw |

**Outputs**: A single NixOS system configuration named `dagadbm-vps`.

### disk-config.nix — Disk Layout

Tells disko how to partition the Hetzner server's disk:

```
/dev/sda (40GB)
├── 1MB   - BIOS boot partition (required for GRUB on Hetzner)
├── 512MB - EFI System Partition (/boot), formatted as FAT32
└── rest  - Root partition (/), formatted as ext4
```

GRUB is used instead of systemd-boot because Hetzner Cloud VMs require it.

### configuration.nix — The System Recipe

Base NixOS configuration:
- Sets hostname, timezone, locale
- Creates user accounts (dagadbm with sudo, openclaw for the service)
- Imports Home Manager as a NixOS module
- Imports security.nix and openclaw.nix
- Enables GRUB bootloader
- Allows unfree packages if needed

### modules/security.nix — Hardening

| Feature | Setting | Why |
|---------|---------|-----|
| SSH port | 2222 | Avoids bulk scanners targeting port 22 |
| Password auth | Disabled | Only SSH keys accepted |
| Root login | Key-only | Needed for nixos-rebuild, but no password |
| Firewall | Ports 2222 + 443 only | Block everything else |
| Auto-updates | Daily | Keeps security patches current |
| fail2ban | Not yet | Added later to avoid lockouts while learning |

### modules/openclaw.nix — OpenClaw Service

Uses the official `nix-openclaw` Home Manager module:
- `programs.openclaw.enable = true`
- Gateway runs as systemd user service under the `openclaw` user
- Binds to localhost (not exposed to internet directly)
- State stored in `/home/openclaw/.openclaw/`
- API keys loaded from `/home/openclaw/secrets/`

### deploy.sh — The One Button

```
./deploy.sh <IP>          # First install (wipes disk, installs NixOS)
./deploy.sh <IP> switch   # Push config updates (no reinstall)
```

The script:
1. Checks Nix is installed on your Mac
2. Validates arguments
3. For first install: runs `nixos-anywhere --flake .#dagadbm-vps --target-host root@<IP> --build-on-remote`
4. For updates: runs `nixos-rebuild switch --flake .#dagadbm-vps --target-host root@<IP>`
5. Prints next steps

### secrets/ — Your API Keys

`.gitignored` directory where you store:
- Anthropic API key (for OpenClaw's LLM access)
- Optional: Telegram bot token, Discord bot token
- Optional: any other service credentials

These get manually copied to the server after deploy. Future improvement: use sops-nix to encrypt them in the repo.

## Deployment Flow

```
./deploy.sh 65.21.x.x
        │
        ▼
┌─ Nix on your Mac ──────────────────────────────────┐
│ nix run nixos-anywhere                              │
│   --flake .#dagadbm-vps                             │
│   --target-host root@65.21.x.x                      │
│   --build-on-remote                                 │
└──────────────────────┬──────────────────────────────┘
                       │ SSH
                       ▼
┌─ Hetzner server (Ubuntu) ───────────────────────────┐
│ 1. nixos-anywhere uploads kexec image                │
│ 2. Server boots into temporary NixOS installer       │
│ 3. disko reads disk-config.nix, partitions /dev/sda  │
│ 4. NixOS config is built on the server               │
│ 5. NixOS is installed to disk                        │
│ 6. Server reboots                                    │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─ Hetzner server (NixOS) ────────────────────────────┐
│ - SSH on port 2222 (key-only)                        │
│ - Firewall active                                    │
│ - Auto-updates enabled                               │
│ - OpenClaw gateway running                           │
│ - Ready for API keys                                 │
└──────────────────────────────────────────────────────┘
```

## Technology Choices

| Decision | Choice | Alternatives considered | Why this one |
|----------|--------|------------------------|--------------|
| Deployment tool | nixos-anywhere | nixos-infect | Clean, declarative, not a hack |
| Disk partitioning | disko | Manual partitioning | Declarative, integrated with nixos-anywhere |
| Bootloader | GRUB | systemd-boot | Hetzner Cloud requires GRUB |
| OpenClaw install | Official nix-openclaw | Scout-DJ/openclaw-nix, Docker | Official, maintained by OpenClaw team |
| User management | Home Manager | NixOS system module | Required by official nix-openclaw |
| Secrets | .gitignored directory | sops-nix, agenix | Simple for now, upgradable later |
| Nix installer (Mac) | Determinate Systems | Official NixOS installer | Survives macOS upgrades, clean uninstall |
