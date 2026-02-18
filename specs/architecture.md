# Architecture: Reproducible NixOS VPS

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ Your Mac  (no Nix installed)                                     │
│                                                                 │
│  dagadbm-vps/                                                   │
│  ├── flake.nix                                                  │
│  ├── deploy.sh ────┬─── install mode ──► Docker container ─┐    │
│  ├── ...           │                     (nixos/nix image)  │    │
│  └── secrets/      │                     runs nixos-anywhere│    │
│      └── (API keys)│                                        │    │
│                    └─── switch mode ──► rsync + SSH ────────┤    │
│                         (no Docker needed)                  │    │
└────────────────────────────────────────────────────────────┼────┘
                                                             │
                                                             ▼ SSH
┌─────────────────────────────────────────────────────────────────┐
│ Hetzner Cloud CX23 (4GB RAM, 40GB disk)                         │
│                                                                 │
│  Install: Ubuntu → nixos-anywhere → NixOS                       │
│  Update:  rsync Nix files → nixos-rebuild switch                │
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

No local Nix required. The script has two modes:

**Install mode** (`./deploy.sh <IP>`):
1. Checks Docker is installed and running
2. Runs a `nixos/nix` Docker container that executes `nixos-anywhere`
3. Mounts the SSH key and project directory into the container
4. `--build-on-remote` makes the Hetzner server compile the configuration
5. Prints next steps

**Switch mode** (`./deploy.sh <IP> switch`):
1. Uses rsync to sync Nix files (`flake.nix`, `flake.lock`, `configuration.nix`, `disk-config.nix`, `modules/`) to `/etc/nixos/` on the server
2. SSHs in and runs `nixos-rebuild switch --flake /etc/nixos#dagadbm-vps`
3. Only needs rsync and SSH (both pre-installed on macOS)

### secrets/ — Your API Keys

`.gitignored` directory where you store:
- Anthropic API key (for OpenClaw's LLM access)
- Optional: Telegram bot token, Discord bot token
- Optional: any other service credentials

These get manually copied to the server after deploy. Future improvement: use sops-nix to encrypt them in the repo.

## Deployment Flows

### First Install

```
./deploy.sh 65.21.x.x
        │
        ▼
┌─ Docker on your Mac ───────────────────────────────┐
│ docker run nixos/nix                                │
│   ├── mounts SSH key + project directory            │
│   └── nix run nixpkgs#nixos-anywhere                │
│        --flake /work#dagadbm-vps                    │
│        --target-host root@65.21.x.x                 │
│        --build-on-remote                            │
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

### Config Update

```
./deploy.sh 65.21.x.x switch
        │
        ├─ 1. rsync ─────────────────────────────────────────┐
        │   flake.nix, flake.lock, configuration.nix,        │
        │   disk-config.nix, modules/                        │
        │                  ──► root@IP:/etc/nixos/ (port 2222)│
        │                                                     │
        └─ 2. ssh ───────────────────────────────────────────┘
            nixos-rebuild switch --flake /etc/nixos#dagadbm-vps
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
| Local Nix runtime | Docker (nixos/nix image) | Install Nix on Mac | No Mac-side Nix install needed; Docker is ephemeral |
| Config updates | rsync + SSH | nixos-rebuild --target-host | No local Nix needed; rsync ships with macOS |
