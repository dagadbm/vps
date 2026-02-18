# Security hardening module
#
# - SSH on non-standard port with key-only authentication
# - Minimal firewall (only SSH and HTTPS)
# - Automatic daily NixOS upgrades for security patches
# - No fail2ban for now (to avoid lockouts while learning)
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

  # ── Automatic upgrades ──────────────────────────────────────────
  # Pulls the latest NixOS channel and rebuilds daily.
  # This keeps security patches current without manual intervention.
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    dates = "daily";
  };
}
