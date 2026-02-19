# OpenClaw Home Manager configuration for the `openclaw` user
#
# - Gateway mode: local (binds to localhost)
# - Authentication: token loaded from sops-managed secret
# - Default instance enabled
{ config, lib, pkgs, ... }:

{
  programs.openclaw = {
    config = {
      gateway = {
        # Local mode — gateway binds to localhost only
        # Use a reverse proxy (e.g. Caddy) to expose it externally
        mode = "local";

        auth = {
          # sops-nix decrypts the token to /run/secrets/gateway-token
          tokenFile = "/run/secrets/gateway-token";
        };
      };
    };

    # Enable the default OpenClaw instance
    # This creates a systemd user service that auto-starts on boot
    instances.default.enable = true;
  };
}
