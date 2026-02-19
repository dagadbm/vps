# Install SSH authorized_keys from sops at activation time.
#
# This keeps flake evaluation pure (no /run access during eval) while
# still sourcing the key from sops-managed secrets at runtime.
{ config, pkgs, ... }:

let
  rootKeyPath = config.sops.secrets."ssh-public-key-root".path;
  openclawKeyPath = config.sops.secrets."ssh-public-key-openclaw".path;
  install = "${pkgs.coreutils}/bin/install";
in {
  system.activationScripts.install-ssh-authorized-keys = {
    deps = [ "setupSecrets" ];
    text = ''
    if [ ! -f "${rootKeyPath}" ]; then
      echo "Missing root SSH public key at ${rootKeyPath}" >&2
      exit 1
    fi

    if [ ! -f "${openclawKeyPath}" ]; then
      echo "Missing openclaw SSH public key at ${openclawKeyPath}" >&2
      exit 1
    fi

    ${install} -d -m 0755 /etc/ssh/authorized_keys.d
    ${install} -m 0644 "${rootKeyPath}" /etc/ssh/authorized_keys.d/root
    ${install} -m 0644 "${openclawKeyPath}" /etc/ssh/authorized_keys.d/openclaw
    '';
  };
}
