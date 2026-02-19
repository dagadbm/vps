Human-readable guide for deploying and maintaining this NixOS VPS.

## What this repo does

This repository defines a full NixOS server for running OpenClaw on Hetzner Cloud:
- OS and disk layout
- SSH/firewall hardening
- OpenClaw service configuration
- Encrypted secrets (sops-nix with age)

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
- `age` and `sops` (`brew install age sops`)
- A reachable VPS IP
- SSH private key access to the server

If you use `--host`, add an SSH config entry like:

```sshconfig
Host host-name
    HostName 123.123.123.123
    User root
    Port 2222
    IdentityFile ~/.ssh/ssh_key
```

## Secrets management

Secrets are encrypted in git via sops-nix. The age private key (`secrets/age-key.txt`) stays local and gitignored.

### One-time setup

```bash
# Generate the age key pair
age-keygen -o secrets/age-key.txt
# Note the public key from the output (starts with "age1...")

# Put the public key in .sops.yaml (replace <AGE_PUBLIC_KEY_PLACEHOLDER>)

# Create and encrypt the secrets file
SOPS_AGE_KEY_FILE=secrets/age-key.txt sops secrets/secrets.yaml
# This opens your $EDITOR — add:
#   openclaw-gateway-token: your-actual-openclaw-token
#   ssh-public-key-root: ssh-ed25519 AAAAC3... root
#   ssh-public-key-openclaw: ssh-ed25519 AAAAC3... openclaw
```

### View or edit existing secrets

```bash
SOPS_AGE_KEY_FILE=secrets/age-key.txt sops secrets/secrets.yaml
```

### Add a new secret

1. Add the value to `secrets/secrets.yaml` via `sops`
2. Declare it in `modules/sops.nix` with owner/permissions
3. Reference its path in the consuming module

### Age key backup

`secrets/age-key.txt` is the **only way** to decrypt secrets. Back it up in a password manager. If lost, you must generate a new key, update `.sops.yaml`, and re-encrypt all secrets.

## First install (destroys existing server data)

Using SSH host alias:

```bash
./bootstrap.sh --host host-name --system x86
./bootstrap.sh --host host-name --system arm
```

Using direct IP:

```bash
./bootstrap.sh --ip 123.123.123.123 --ssh-key ~/.ssh/ssh_key
./bootstrap.sh --ip 123.123.123.123 --ssh-key ~/.ssh/ssh_key --system arm
```

Notes:
- Bootstrap connects on port `22` (fresh Hetzner default).
- It runs `nixos-anywhere` via Docker and installs either `vps-x86` or `vps-arm`.
- The sops age key is automatically provisioned to the server during bootstrap.
- Secrets are decrypted automatically — no manual steps needed.

## Update an existing server

Using SSH host alias:

```bash
./update.sh --host host-name --system x86
./update.sh --host host-name --system arm
```

Using direct IP:

```bash
./update.sh --ip 123.123.123.123 --system x86
./update.sh --ip 123.123.123.123 --system arm
```

Notes:
- Update mode uses SSH port `2222`.
- It rsyncs Nix files (including encrypted secrets) to `/etc/nixos` and runs `nixos-rebuild switch`.

## Safety checklist

- `bootstrap.sh` is destructive. Double-check target before running.
- Keep `system.stateVersion` and Home Manager state version stable after deployment.
- Back up `secrets/age-key.txt` — it's the only way to decrypt secrets.

## Nix beginner quickstart

This repo is the server's source code.

- **Nix** is a package/build system focused on reproducibility.
- **NixOS** is Linux configured as code.
- You edit `.nix` files, then apply changes to make the server match.

### Mental model for this repo

- `flake.nix`: project entry point (what can be built/deployed)
- `modules/system.nix`: main system settings
- `modules/security.nix`: SSH, firewall, fail2ban, auto updates
- `modules/sops.nix`: encrypted secrets (sops-nix with age)
- `home-manager/openclaw.nix`: OpenClaw options
- `modules/disk.nix`: disk partition layout for first install

### Which command to use

- First install only (wipes disk): `bootstrap.sh`
- Normal ongoing changes: `update.sh`

### Typical change flow

1. Edit a `.nix` file.
2. Run `./update.sh --host host-name --system x86` (or `--ip ... --system arm`).
3. Verify server behavior.

### Common edits

- Hostname/timezone/locale: `modules/system.nix`
- Open/close ports: `modules/security.nix`
- OpenClaw config: `home-manager/openclaw.nix`
- Secrets: `SOPS_AGE_KEY_FILE=secrets/age-key.txt sops secrets/secrets.yaml` + declare in `modules/sops.nix`
- Disk layout: `modules/disk.nix` (destructive during bootstrap)

### Syntax cheat sheet

- `{ ... }` = object/map
- `a.b = value;` = nested setting
- `[ x y z ]` = list
- `# ...` = comment
- assignments end with `;`
