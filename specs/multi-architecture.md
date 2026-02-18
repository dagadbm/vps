# Plan: Multi-Architecture Support (x86 + arm)

## Goal

Allow this repo to deploy to both Hetzner x86 and ARM VPS types without manual edits to `flake.nix` each time.

## Current Issue

- `flake.nix` currently hardcodes `system = "x86_64-linux"`.
- When deploying to an ARM VPS, builds fail with:
  - required system: `x86_64-linux`
  - current system: `aarch64-linux`

## Target Design

1. Keep one shared NixOS module stack (`modules/system.nix`, `modules/*`, `modules/disk.nix`).
2. Expose two NixOS outputs in `flake.nix`:
   - `vps-x86` (`x86_64-linux`)
   - `vps-arm` (`aarch64-linux`)
3. Make scripts choose output explicitly with a `--system` flag:
   - `--system x86`
   - `--system arm`
4. Require explicit architecture selection with `--system` in scripts.

## Implementation Steps

### Step 1: Refactor `flake.nix` outputs

- Introduce a small helper function, e.g. `mkVps = system: nixpkgs.lib.nixosSystem { ... }`.
- Keep shared `modules` and `specialArgs` in one place.
- Define:
  - `nixosConfigurations.vps-x86 = mkVps "x86_64-linux";`
  - `nixosConfigurations.vps-arm = mkVps "aarch64-linux";`
Acceptance check:
- `nix flake show` lists both outputs.

### Step 2: Update `bootstrap.sh`

- Add a new argument:
  - `--system <x86|arm>`
- Validate input strictly.
- Set `FLAKE_HOST` from the selected system:
  - x86 -> `vps-x86`
  - arm -> `vps-arm`
- Map friendly values to Nix systems internally:
  - x86 -> `x86_64-linux`
  - arm -> `aarch64-linux`
- Use:
  - `--flake /work#$FLAKE_HOST`
- Update usage/help text and examples.
- Update comments that currently imply x86-only behavior.

Acceptance check:
- `./bootstrap.sh --help` shows `--system`.
- Running with `--system arm` invokes `--flake /work#vps-arm`.

### Step 3: Update `update.sh`

- Add the same `--system` flag and validation.
- Map to selected flake output:
  - `nixos-rebuild switch --flake /etc/nixos#vps-arm` (ARM)
  - `...#vps-x86` (x86)
- Update usage/help text and examples.

Acceptance check:
- `./update.sh --help` shows `--system`.
- Command sent over SSH uses selected flake host.

### Step 4: Documentation updates

- Update `README.md`:
  - Explain architecture choice.
  - Show bootstrap/update commands for both systems.
  - Add a short table: Hetzner server type -> `--system` value.
- Update any stale references in:
  - `CLAUDE.md`
  - `specs/architecture.md`
  - comments in scripts mentioning x86-only assumptions.

Acceptance check:
- No docs claim “single x86 output” anymore.

### Step 5: Validation workflow

Run locally from repo root:

```bash
nix flake show
nix eval .#nixosConfigurations.vps-x86.config.nixpkgs.hostPlatform.system
nix eval .#nixosConfigurations.vps-arm.config.nixpkgs.hostPlatform.system
```

Expected:
- x86 eval returns `"x86_64-linux"`
- arm eval returns `"aarch64-linux"`

Script sanity checks:

```bash
./bootstrap.sh --help
./update.sh --help
```

Optional deployment smoke tests:
1. Boot one x86 VPS and run bootstrap with `--system x86`.
2. Boot one ARM VPS and run bootstrap with `--system arm`.
3. Run `./update.sh` against both targets with matching `--system`.

## Risks and Notes

1. Package compatibility risk:
   - Most config is architecture-independent, but specific packages may fail on ARM.
   - If OpenClaw or dependencies are x86-only, ARM deploy still fails even with correct flake wiring.
2. Disk/boot assumptions:
   - `modules/disk.nix` and GRUB config are likely fine for both Hetzner VM architectures, but validate on first ARM install.
## Suggested Rollout Strategy

1. Merge flake + script + docs changes with explicit architecture selection.
2. Test ARM path on the new ARM VPS.
3. Keep requiring explicit `--system` to prevent accidental mismatch.

## Definition of Done

1. Two flake outputs exist and evaluate correctly.
2. Both scripts support `--system` and pass the correct flake target.
3. Docs show architecture-specific usage clearly.
4. At least one successful bootstrap+update run is completed on ARM.
