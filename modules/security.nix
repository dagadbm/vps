# Security hardening module
#
# - SSH on non-standard port with key-only authentication
# - Minimal firewall (only SSH and HTTPS)
# - fail2ban for SSH brute-force protection
# - Automatic daily NixOS upgrades for security patches
{ config, lib, pkgs, ... }:

{
  # ── SSH daemon ───────────────────────────────────────────────────
  services.openssh = {
    enable = true;

    # Non-standard port reduces noise from automated scanners
    # This replaces the default [22] — sshd will ONLY listen on 2222
    ports = [ 2222 ];

    settings = {
      # Only SSH keys, never passwords
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;

      # Root can SSH in for nixos-rebuild, but only with a key
      PermitRootLogin = "prohibit-password";
    };
  };

  # ── Firewall ─────────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      2222  # SSH
      443   # HTTPS (for OpenClaw gateway / future Caddy reverse proxy)
    ];
    # Everything else is blocked by default
  };

  # ── fail2ban ────────────────────────────────────────────────────
  # Auto-bans IPs after repeated failed SSH attempts.
  # Defense-in-depth: SSH is already key-only, but this stops
  # brute-force scanners from wasting resources and log space.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment.enable = true; # Repeat offenders get longer bans

    jails.sshd = {
      settings = {
        enabled = true;
        port = 2222;
        filter = "sshd";
      };
    };
  };

  # ── Automatic upgrades ──────────────────────────────────────────
  # Disabled: User maintains full manual control over updates.
  # All updates flow through: update.sh → nix flake update → sync.sh
  system.autoUpgrade = {
    enable = false;
  };
}
