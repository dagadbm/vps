{
  description = "Reproducible NixOS VPS running OpenClaw on Hetzner Cloud";

  inputs = {
    # NixOS unstable — latest packages and modules
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Declarative disk partitioning — used by nixos-anywhere to format drives
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Per-user configuration management — required by nix-openclaw
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Official OpenClaw Nix package and Home Manager module
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
    };
  };

  outputs = { self, nixpkgs, disko, home-manager, nix-openclaw, ... }: {
    nixosConfigurations.vps-personal = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      # Make nix-openclaw available to all modules via specialArgs
      specialArgs = { inherit nix-openclaw; };

      modules = [
        # Declarative disk partitioning
        disko.nixosModules.disko
        ./disk-config.nix

        # Home Manager as a NixOS module (not standalone)
        home-manager.nixosModules.home-manager

        # Main system configuration
        ./configuration.nix
      ];
    };
  };
}
