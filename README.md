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

## Prerequisites

- Docker Desktop (for `bootstrap.sh`)
- `rsync` and `ssh` (default on macOS)
- A reachable VPS IP
- SSH private key access to the server

If you use `--host`, add an SSH config entry like:

```sshconfig
Host vps-personal
    HostName 46.225.171.96
    User root
    Port 2222
    IdentityFile ~/.ssh/github_personal
```

## First install (destroys existing server data)

Using SSH host alias:

```bash
./bootstrap.sh --host vps-personal
```

Using direct IP:

```bash
./bootstrap.sh --ip 46.225.171.96 --ssh-key ~/.ssh/github_personal
```

Notes:
- Bootstrap connects on port `22` (fresh Hetzner default).
- It runs `nixos-anywhere` via Docker and installs the flake output `vps-personal`.

## Update an existing server

Using SSH host alias:

```bash
./update.sh --host vps-personal
```

Using direct IP:

```bash
./update.sh --ip 46.225.171.96
```

Notes:
- Update mode uses SSH port `2222`.
- It rsyncs Nix files to `/etc/nixos` and runs `nixos-rebuild switch`.

## After first install: add OpenClaw token

```bash
ssh vps-personal -l openclaw 'mkdir -p ~/secrets'
scp -P 2222 secrets/gateway-token openclaw@vps-personal:~/secrets/
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
