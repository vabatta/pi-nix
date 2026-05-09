{
  description = "Nix package and home-manager module for pi.dev coding agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forEachSystem = f:
        nixpkgs.lib.genAttrs systems (system:
          f {
            pkgs = nixpkgs.legacyPackages.${system};
            inherit system;
          }
        );
    in
    {
      packages = forEachSystem ({ pkgs, system }: {
        pi = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.pi;
      });

      homeManagerModules = {
        pi = import ./modules/pi.nix;
        default = self.homeManagerModules.pi;
      };

      checks = forEachSystem ({ pkgs, system }: {
        pi = self.packages.${system}.pi;
      });
    };
}
