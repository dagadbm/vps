# NixOS VPS Deployment Scripts Specification

## Context

The current deployment workflow has `update.sh` which rsyncs config files to the VPS and runs `nixos-rebuild switch`. However, this doesn't distinguish between:
1. Updating the flake lock file (pulling new nixpkgs versions)
2. Syncing local changes to the remote server

Additionally, there's no rollback mechanism if an update breaks the system. Since `system.autoUpgrade` doesn't update the lock file (no `--update-input` flags), manual control over updates is maintained, but the workflow needs clarity and safety nets.

**Goals:**
- Separate lock file updates from config syncing
- Provide rollback capability to previous NixOS generations
- Maintain consistent argument parsing across all scripts
- Disable auto-upgrades by default in NixOS config (user owns all updates manually)

## Implementation Plan

### 1. Rename `update.sh` to `sync.sh`

**File:** `update.sh` → `sync.sh`

**Changes:**
- Simple file rename using `git mv update.sh sync.sh`
- Update internal comments to reflect new purpose: "Sync config files to VPS"
- Update usage examples to show `./sync.sh` instead of `./update.sh`
- No logic changes

**Lines to update:**
- Line 3: Comment header "sync.sh — Push config updates to an existing NixOS server"
- Lines 9-10, 49-52: Usage examples
- Line 151: Success message

### 2. Create new `update.sh` (Flake Updater + Sync)

**File:** `update.sh` (new)

**Purpose:** Update flake.lock locally, then call sync.sh

**Structure:**
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Argument parsing (--host/--ip/--system)
# Validation (same as sync.sh)
# Run: nix flake update
# Call: ./sync.sh --host/--ip <value> --system <value>
```

**Arguments:**
- `--host <alias>` - SSH config hostname (mutually exclusive with --ip)
- `--ip <address>` - Direct IP (mutually exclusive with --host)
- `--system <x86|arm>` - Required (passed through to sync.sh for nixos-rebuild)

**Why `--system` is needed:** The `--system` flag determines which flake configuration to build on the remote server (`vps-x86` vs `vps-arm`). While `nix flake update` doesn't need this (it updates all inputs regardless of architecture), we need to pass it to `sync.sh`, which calls `nixos-rebuild switch --flake /etc/nixos#vps-x86` (or `#vps-arm`). The system flag determines which flake output to activate.

**Implementation steps:**
1. Parse arguments using same pattern as sync.sh
2. Validate mutually exclusive --host/--ip
3. Run `nix flake update` in project directory
4. Execute `"$SCRIPT_DIR/sync.sh"` with forwarded arguments (--host/--ip, --system)

**Key functions:**
- Standard argument parsing loop
- Error handling for `nix flake update` failures
- Pass-through to sync.sh with same connection parameters

### 3. Create `rollback.sh` (Generation Rollback)

**File:** `rollback.sh` (new)

**Purpose:** Roll back VPS to a previous NixOS generation

**Arguments:**
- `--host <alias>` - SSH config hostname (mutually exclusive with --ip)
- `--ip <address>` - Direct IP (mutually exclusive with --host)
- `--list` - Show available generations (takes action, exits)
- `--previous` - Roll back one generation (takes action)
- `--version <N>` - Roll back to specific generation number (takes action)

**Note:** `--system` flag is NOT needed (we're just switching generations, not building)

**Structure:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# remote_ssh helper (same as sync.sh)
# Argument parsing
# Validation: require exactly one of --list/--previous/--version
# Validation: require --host or --ip

# If --list:
#   remote_ssh "nixos-rebuild list-generations"
#   exit 0

# If --previous:
#   remote_ssh "nixos-rebuild switch --rollback"
#   print_success_message

# If --version N:
#   verify generation exists
#   remote_ssh "/nix/var/nix/profiles/system-N-link/bin/switch-to-configuration switch"
#   print_success_message
```

**Critical implementation details:**

**For `--list`:**
```bash
remote_ssh "nixos-rebuild list-generations"
```
Output format (parsed by user manually):
```
 Gen    Build-date          NixOS version     Kernel version    Config Revision
 287                        24.11.20241231.c8ccf49 (current)
 286    2025-02-15 10:23:45 24.11.20241231.c8ccf49
```

**For `--previous`:**
```bash
# Roll back one generation
remote_ssh "nixos-rebuild switch --rollback"

echo "✅ Rolled back to previous generation."
echo "    Push a fixed config with './sync.sh' when ready."
```

**For `--version N`:**
```bash
# Verify generation exists first
if ! remote_ssh "test -e /nix/var/nix/profiles/system-$VERSION-link"; then
  echo "Error: Generation $VERSION does not exist."
  exit 1
fi

# Switch to specific generation using the workaround from NixOS issue https://github.com/NixOS/nixpkgs/issues/82851
# (Direct switch-to-configuration doesn't update GRUB properly without this)
remote_ssh "nix-env -p /nix/var/nix/profiles/system --set /nix/var/nix/profiles/system-$VERSION-link"
remote_ssh "/nix/var/nix/profiles/system/bin/switch-to-configuration switch"

echo "✅ Rolled back to generation $VERSION."
echo "    Push a fixed config with './sync.sh' when ready."
```

**Argument validation:**
- Must have exactly one of: --list, --previous, --version
- Must have --host or --ip (but not both)
- --version requires a numeric argument

### 4. Update `bootstrap.sh` reference

**File:** `bootstrap.sh`

**Line 346:** Change call from `update.sh` to `sync.sh`
```bash
# Before:
"$SCRIPT_DIR/update.sh" --host "$TARGET_HOST" --system "$SYSTEM"

# After:
"$SCRIPT_DIR/sync.sh" --host "$TARGET_HOST" --system "$SYSTEM"
```

**Note:** Keep this change even though we're disabling auto-upgrades, as bootstrap.sh just needs to apply the initial config.

### 5. Disable auto-upgrades in NixOS config

**File:** `modules/security.nix`

**Lines 62-66:** Comment out or set `enable = false`

**Before:**
```nix
system.autoUpgrade = {
  enable = true;
  allowReboot = true;
  dates = "daily";
};
```

**After:**
```nix
system.autoUpgrade = {
  enable = false;
};
```

**Rationale:** User wants full manual control over updates. No automatic nixpkgs updates, no automatic rebuilds. All updates flow through `update.sh` → `nix flake update` → `sync.sh`.

### 6. Update documentation

**File:** `CLAUDE.md`

**Section: "Deployment Commands"** (lines 11-42)

Update examples to reflect new script names:
```bash
# Push config updates to existing server (rsync + nixos-rebuild)
./sync.sh --host host-name --system x86
./sync.sh --ip 123.123.123.123 --system arm

# Update flake inputs and sync to server
./update.sh --host host-name --system x86

# Roll back to previous generation
./rollback.sh --host host-name --previous

# List available generations
./rollback.sh --host host-name --list

# Roll back to specific generation
./rollback.sh --host host-name --version 42
```

Add new section after deployment commands:
```markdown
## Rollback & Recovery

If an update breaks the system, use `rollback.sh` to revert to a working generation:

```bash
# List available versions
./rollback.sh --host host-name --list

# Roll back to previous version
./rollback.sh --host host-name --previous

# Roll back to specific version
./rollback.sh --host host-name --version 285
```

Push a fixed config with `./sync.sh` when ready.
```

**File:** `README.md` (if exists)
- Update any references to `update.sh` → `sync.sh`
- Add rollback examples

## Critical Files

**To modify:**
- `update.sh` → `sync.sh` (rename + comment updates)
- `bootstrap.sh` (line 346: update script call)
- `modules/security.nix` (disable auto-upgrades)
- `CLAUDE.md` (documentation updates)

**To create:**
- `update.sh` (new: flake updater)
- `rollback.sh` (new: generation rollback)

## Verification Steps

### Test sync.sh (renamed update.sh)
```bash
# Should work identically to old update.sh
./sync.sh --host test-server --system x86
# Verify: files synced, nixos-rebuild runs
```

### Test new update.sh
```bash
./update.sh --host test-server --system x86
# Verify: flake.lock updated locally, sync.sh called, changes applied
```

### Test rollback.sh
```bash
# List generations
./rollback.sh --host test-server --list
# Verify: shows generation list with dates and versions

# Roll back to previous
./rollback.sh --host test-server --previous
# Verify:
#   - System switched to previous generation
#   - Success message printed

# Roll back to specific version
./rollback.sh --host test-server --version 285
# Verify:
#   - System switched to generation 285
#   - Success message printed

# Try invalid generation
./rollback.sh --host test-server --version 9999
# Verify: Error message, exits with non-zero
```

### Test bootstrap.sh integration
```bash
# Run fresh bootstrap (test VM recommended)
./bootstrap.sh --host test-vm --system x86
# Verify: calls sync.sh (not update.sh) after installation
```

### End-to-end workflow test
```bash
# 1. Update flake and deploy
./update.sh --host test-server --system x86

# 2. Verify new generation created
./rollback.sh --host test-server --list

# 3. Simulate broken update by rolling back
./rollback.sh --host test-server --previous

# 4. Push fixed config
./sync.sh --host test-server --system x86
```