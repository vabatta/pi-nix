{
  description = "Nix home-manager module for pi.dev coding agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    {
      homeManagerModules = {
        pi = import ./modules/pi.nix;
        default = self.homeManagerModules.pi;
      };
    };
}
