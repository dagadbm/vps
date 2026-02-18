Human-readable guide for deploying and maintaining this NixOS VPS.

## What this repo does

This repository defines a full NixOS server for running OpenClaw on Hetzner Cloud:
- OS and disk layout
- SSH/firewall hardening
- OpenClaw service configuration

You can wipe and rebuild the server from this repo.

## Two scripts you will use

- `bootstrap.sh`: first install only (destructive, wipes the disk)
- `update.sh`: push config changes to an existing server

Both scripts are strict: you must pass exactly one of:
- `--host <ssh-alias>`: resolve connection details from `~/.ssh/config`
- `--ip <server-ip>`: connect directly by IP

Architecture selection:
- `--system x86`: targets flake output `vps-x86`
- `--system arm`: targets flake output `vps-arm`

Hetzner server type mapping:
| Hetzner VPS type | Use |
|---|---|
| Intel/AMD VPS (x86_64) | `--system x86` |
| ARM VPS (aarch64) | `--system arm` |

## Prerequisites

- Docker Desktop (for `bootstrap.sh`)
- `rsync` and `ssh` (default on macOS)
- A reachable VPS IP
- SSH private key access to the server

If you use `--host`, add an SSH config entry like:

```sshconfig
Host host-name
    HostName 46.225.171.96
    User root
    Port 2222
    IdentityFile ~/.ssh/github_personal
```

## First install (destroys existing server data)

Using SSH host alias:

```bash
./bootstrap.sh --host host-name --system x86
./bootstrap.sh --host host-name --system arm
```

Using direct IP:

```bash
./bootstrap.sh --ip 46.225.171.96 --ssh-key ~/.ssh/github_personal
./bootstrap.sh --ip 46.225.171.96 --ssh-key ~/.ssh/github_personal --system arm
```

Notes:
- Bootstrap connects on port `22` (fresh Hetzner default).
- It runs `nixos-anywhere` via Docker and installs either `vps-x86` or `vps-arm`.

## Update an existing server

Using SSH host alias:

```bash
./update.sh --host host-name --system x86
./update.sh --host host-name --system arm
```

Using direct IP:

```bash
./update.sh --ip 46.225.171.96 --system x86
./update.sh --ip 46.225.171.96 --system arm
```

Notes:
- Update mode uses SSH port `2222`.
- It rsyncs Nix files to `/etc/nixos` and runs `nixos-rebuild switch`.

## After first install: add OpenClaw token

```bash
ssh host-name -l openclaw 'mkdir -p ~/secrets'
scp -P 2222 secrets/gateway-token openclaw@host-name:~/secrets/
```

If you are using direct IP instead of host alias:

```bash
ssh -p 2222 openclaw@46.225.171.96 'mkdir -p ~/secrets'
scp -P 2222 secrets/gateway-token openclaw@46.225.171.96:~/secrets/
```

## Safety checklist

- `bootstrap.sh` is destructive. Double-check target before running.
- Keep `system.stateVersion` and Home Manager state version stable after deployment.
- Keep secrets out of git (token file is manually managed).

## Nix beginner quickstart

This repo is the server's source code.

- **Nix** is a package/build system focused on reproducibility.
- **NixOS** is Linux configured as code.
- You edit `.nix` files, then apply changes to make the server match.

### Mental model for this repo

- `flake.nix`: project entry point (what can be built/deployed)
- `configuration.nix`: main system settings
- `modules/security.nix`: SSH, firewall, fail2ban, auto updates
- `modules/openclaw.nix`: OpenClaw options
- `disk-config.nix`: disk partition layout for first install

### Which command to use

- First install only (wipes disk): `bootstrap.sh`
- Normal ongoing changes: `update.sh`

### Typical change flow

1. Edit a `.nix` file.
2. Run `./update.sh --host host-name --system x86` (or `--ip ... --system arm`).
3. Verify server behavior.

### Common edits

- Hostname/timezone/locale: `configuration.nix`
- Open/close ports: `modules/security.nix`
- OpenClaw config: `modules/openclaw.nix`
- Disk layout: `disk-config.nix` (destructive during bootstrap)

### Syntax cheat sheet

- `{ ... }` = object/map
- `a.b = value;` = nested setting
- `[ x y z ]` = list
- `# ...` = comment
- assignments end with `;`
