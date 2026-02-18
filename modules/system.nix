# Main NixOS configuration for the vps-personal server
#
# This is the "recipe" for the entire system. It defines:
# - System identity (hostname, timezone, locale)
# - User accounts
# - Bootloader
# - Home Manager integration for per-user config
# - Imports for security hardening and OpenClaw service
{ config, pkgs, lib, modulesPath, nix-openclaw, ... }:

{
  imports = [
    # QEMU/KVM guest profile — loads virtio drivers (network, disk, GPU, etc.)
    # for both x86_64 and aarch64 Hetzner Cloud VMs
    (modulesPath + "/profiles/qemu-guest.nix")
    ./security.nix
    ./openclaw.nix
  ];

  # ── System identity ──────────────────────────────────────────────
  networking.hostName = "vps-personal";
  time.timeZone = "Europe/Lisbon";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Bootloader ───────────────────────────────────────────────────
  # GRUB is required for Hetzner Cloud VMs (BIOS boot is expected).
  # This setup keeps EFI compatibility flags so the image remains portable.
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # ── QEMU guest agent ─────────────────────────────────────────────
  # Lets the hypervisor gracefully shutdown the VM, freeze filesystems
  # for consistent snapshots, and sync the clock.
  services.qemuGuest.enable = true;

  # ── Console output ───────────────────────────────────────────────
  # "console=tty" directs kernel output to the current virtual terminal.
  # Works on both x86_64 (CX) and aarch64 (CAX) Hetzner Cloud VMs.
  # The previous "console=ttyS0" was x86-only — ARM uses ttyAMA0 for
  # serial, so a shared config should use the generic "tty" instead.
  boot.kernelParams = [ "console=tty" ];

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
  # Limit build parallelism to reduce peak memory usage on small VPSes.
  # Tradeoff: rebuilds are slower, but less likely to OOM.
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
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtAjf6zeT7Mg7w+zuC9yIN1xEvGZUPdKWwoo29EZEFx dagadbm@gmail.com"
  ];

  users.users.openclaw = {
    isNormalUser = true; # Required by Home Manager
    description = "OpenClaw service user";
    # No extraGroups — this user has no sudo access
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtAjf6zeT7Mg7w+zuC9yIN1xEvGZUPdKWwoo29EZEFx dagadbm@gmail.com"
    ];
  };

  # ── Home Manager ─────────────────────────────────────────────────
  # Configured as a NixOS module (not standalone) so it integrates
  # with the system activation and rebuilds.
  # In practice: one `nixos-rebuild` updates both system + user config.
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
