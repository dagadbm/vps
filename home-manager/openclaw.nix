# OpenClaw Home Manager configuration for the `openclaw` user
#
# This module sets the OpenClaw-specific options:
# - Gateway mode: local (binds to localhost)
# - Authentication: token loaded from a file on disk
# - Default instance enabled
#
# After deployment, you must manually create the token file:
#   ssh -p 2222 openclaw@<IP>
#   mkdir -p ~/secrets
#   echo "your-api-key" > ~/secrets/gateway-token
#
# If this file is missing, OpenClaw auth will fail at runtime.
{ config, lib, pkgs, ... }:

{
  programs.openclaw = {
    config = {
      gateway = {
        # Local mode — gateway binds to localhost only
        # Use a reverse proxy (e.g. Caddy) to expose it externally
        mode = "local";

        auth = {
          # Path to the API token file on the server
          # This file is NOT managed by Nix — it's manually placed
          # and should be readable by the `openclaw` user only.
          tokenFile = "/home/openclaw/secrets/gateway-token";
        };
      };
    };

    # Enable the default OpenClaw instance
    # This creates a systemd user service that auto-starts on boot
    instances.default.enable = true;
  };
}
