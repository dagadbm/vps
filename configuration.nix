# Main NixOS configuration for the vps-personal server
#
# This is the "recipe" for the entire system. It defines:
# - System identity (hostname, timezone, locale)
# - User accounts
# - Bootloader
# - Home Manager integration for per-user config
# - Imports for security hardening and OpenClaw service
{ config, pkgs, lib, nix-openclaw, ... }:

{
  imports = [
    ./modules/security.nix
    ./modules/openclaw.nix
  ];

  # ── System identity ──────────────────────────────────────────────
  networking.hostName = "vps-personal";
  time.timeZone = "Europe/Lisbon";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Bootloader ───────────────────────────────────────────────────
  # GRUB is required for Hetzner Cloud VMs (they use BIOS boot, not UEFI)
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # ── Memory management ─────────────────────────────────────────
  # zram provides compressed swap in RAM (~2:1 ratio), giving
  # effectively more usable memory without disk I/O penalty
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Disk-backed swap as a safety net when zram is full
  swapDevices = [{
    device = "/mnt/swapfile";
    size = 4096; # 4GB
  }];

  # ── Nix build settings ────────────────────────────────────────
  # Limit build parallelism to reduce peak memory usage
  nix.settings = {
    max-jobs = 1;
    cores = 1;
  };

  # ── Packages ─────────────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  # Apply the nix-openclaw overlay so its packages are available system-wide
  nixpkgs.overlays = [
    nix-openclaw.overlays.default
  ];

  # ── User accounts ───────────────────────────────────────────────
  #
  # root — used for all admin/deploy operations (nixos-rebuild, nixos-anywhere)
  # openclaw — service user that runs OpenClaw via Home Manager
  #
  # No separate personal user account; root handles all admin tasks.

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDAN0oQS5n8qu/OckmsD0A0Mgp/DO8w6sIdEDe4W6+jB dagadbm@gmail.com"
  ];

  users.users.openclaw = {
    isNormalUser = true; # Required by Home Manager
    description = "OpenClaw service user";
    # No extraGroups — this user has no sudo access
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDAN0oQS5n8qu/OckmsD0A0Mgp/DO8w6sIdEDe4W6+jB dagadbm@gmail.com"
    ];
  };

  # ── Home Manager ─────────────────────────────────────────────────
  # Configured as a NixOS module (not standalone) so it integrates
  # with the system activation and rebuilds.
  home-manager = {
    useGlobalPkgs = true;   # Use the system's nixpkgs instead of a separate instance
    useUserPackages = true;  # Install user packages to /etc/profiles

    # Make nix-openclaw available to Home Manager modules
    extraSpecialArgs = { inherit nix-openclaw; };

    users.openclaw = { pkgs, ... }: {
      imports = [
        nix-openclaw.homeManagerModules.openclaw
      ];

      # Home Manager requires this to be set — must match the NixOS release
      home.stateVersion = "24.11";
    };
  };

  # ── NixOS state version ──────────────────────────────────────────
  # This determines the default settings for stateful data.
  # Do NOT change this after initial deployment.
  # See: https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.11";
}
