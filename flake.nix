{
  # A flake is a pinned, reproducible entry point for a Nix project.
  # Think of this file as:
  # 1) Inputs: exact upstream dependencies
  # 2) Outputs: what this repo can build (here: one NixOS system)
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

  # `outputs = { ... }: { ... }` is a function:
  # - left side: named inputs passed in
  # - right side: attributes exported by this flake
  outputs = { self, nixpkgs, disko, home-manager, nix-openclaw, ... }:
    let
      mkVps = system: nixpkgs.lib.nixosSystem {
        inherit system;

        # Make nix-openclaw available to all modules via specialArgs
        specialArgs = { inherit nix-openclaw; };

        modules = [
          # Declarative disk partitioning
          disko.nixosModules.disko
          ./modules/disk.nix

          # Home Manager as a NixOS module (not standalone)
          home-manager.nixosModules.home-manager

          # Main system configuration
          ./modules/system.nix
        ];
      };
    in {
      # Target names for deployment commands:
      # nixos-rebuild switch --flake .#vps-x86
      # nixos-rebuild switch --flake .#vps-arm
      nixosConfigurations.vps-x86 = mkVps "x86_64-linux";
      nixosConfigurations.vps-arm = mkVps "aarch64-linux";
    };
}
