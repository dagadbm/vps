# Secret management via sops-nix
#
# Uses a standalone age key (not derived from SSH host keys) so VPS instances
# are fully disposable — no sops updatekeys needed when creating/destroying servers.
#
# The age private key is provisioned during bootstrap via nixos-anywhere's --extra-files.
# Secrets are decrypted at NixOS activation time to /run/secrets/ (tmpfs).
{ config, ... }:

{
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.age.sshKeyPaths = [];
  sops.gnupg.sshKeyPaths = [];

  sops.defaultSopsFile = ../secrets/secrets.yaml;

  sops.secrets."openclaw-gateway-token" = {
    owner = "openclaw";
    group = "users";
    mode = "0400";
  };

  sops.secrets."ssh-public-key-root" = {
    # Used by activation script to install root's authorized_keys file.
  };

  sops.secrets."ssh-public-key-openclaw" = {
    # Used by activation script to install authorized_keys files.
  };
}
