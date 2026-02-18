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

    settings = {
      # Non-standard port reduces noise from automated scanners
      # Remember: ssh -p 2222 root@<IP>
      Port = 2222;

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
  # Pulls the latest NixOS channel and rebuilds daily.
  # This keeps security patches current without manual intervention.
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    dates = "daily";
  };
}
